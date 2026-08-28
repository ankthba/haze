//
//  RadarTileLoader.swift
//  Weather
//
//  Radar tiles are downloaded and cached by the app rather than left to MapKit.
//  Adding a frame's overlay at alpha 0 does *not* make MapKit fetch its tiles —
//  invisible renderers never draw, so they never load — which meant the first
//  pass through the timeline played against tiles that hadn't started
//  downloading and showed nothing; only the second pass, served from the URL
//  cache, looked right.
//
//  So: the tiles a frame needs are learned from the frame that's on screen (at
//  a given framing every frame needs the exact same tile coordinates), every
//  other frame is fetched up front in playback order, and playback waits on any
//  frame that isn't in the cache yet.
//

import Foundation
import MapKit
import Network

/// Watches the current network path. A full radar timeline is around 35 MB of
/// tiles, so Low Data Mode — the user explicitly asking apps to use less — has
/// to mean something here.
nonisolated final class NetworkConditions: @unchecked Sendable {
    static let shared = NetworkConditions()

    private let lock = NSLock()
    private var constrained = false

    private init() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock { self.constrained = path.isConstrained }
        }
        monitor.start(queue: DispatchQueue(label: "radar.network-conditions"))
    }

    /// True in Low Data Mode.
    var isConstrained: Bool { lock.withLock { constrained } }
}

/// A tile coordinate, in a value type that's safe to hand between actors.
nonisolated struct RadarTilePath: Hashable {
    let x: Int
    let y: Int
    let z: Int

    /// The scale factor is dropped: the tile templates carry no {scale}, so it
    /// can't change which tile is fetched.
    init(_ path: MKTileOverlayPath) {
        x = path.x
        y = path.y
        z = path.z
    }

    var overlayPath: MKTileOverlayPath {
        MKTileOverlayPath(x: x, y: y, z: z, contentScaleFactor: 1)
    }
}

/// In-memory store of downloaded tile PNGs, shared by the prefetcher and the
/// overlays. An empty entry records a tile the server *definitively* doesn't
/// have (a 404 or an empty body), so a real hole in the radar isn't
/// re-requested on every pass. Transport errors are never recorded here —
/// a timeout is not knowledge about the tile.
nonisolated final class RadarTileStore: @unchecked Sendable {
    static let shared = RadarTileStore()

    private let cache = NSCache<NSURL, NSData>()

    private init() { cache.totalCostLimit = 64 * 1024 * 1024 }

    func data(for url: URL) -> Data? {
        cache.object(forKey: url as NSURL).map { $0 as Data }
    }

    func store(_ data: Data, for url: URL) {
        cache.setObject(data as NSData, forKey: url as NSURL, cost: max(data.count, 1))
    }
}

nonisolated enum RadarTileError: Error { case unavailable }

/// Downloads tiles, collapsing duplicate requests for the same URL so a
/// prefetch and an on-screen draw of the same tile share one download.
actor RadarTileFetcher {
    static let shared = RadarTileFetcher()

    private var inFlight: [URL: Task<Data?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // The tile services speak HTTP/1.1, so this is a hard ceiling on how
        // many tiles can be in flight — and tiles are latency-bound (~190 ms
        // each, ~19 KB), not bandwidth-bound. A frame is ~50 tiles and playback
        // wants one every 0.5 s, which needs ~20 in flight; at the default 6 a
        // frame took about 1.9 s, so it stalled permanently. Measured against
        // IEM, throughput scales linearly to at least 24 connections with no
        // errors or throttling — and the total request count is unchanged
        // either way, the requests just stop queueing behind each other.
        config.httpMaximumConnectionsPerHost = 20
        // A stalled tile shouldn't hold playback for a minute.
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    func data(for url: URL) async -> Data? {
        if let cached = RadarTileStore.shared.data(for: url) {
            return cached.isEmpty ? nil : cached
        }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<Data?, Never> { [session] in
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else { return nil }
                // A 404 or a well-formed empty body is the server saying "no
                // tile here" — remember that so the hole isn't re-fetched.
                if http.statusCode == 404
                    || ((200..<300).contains(http.statusCode) && data.isEmpty) {
                    RadarTileStore.shared.store(Data(), for: url)
                    return nil
                }
                // 5xx and other oddities: fail this draw but cache nothing,
                // so the next pass retries.
                guard (200..<300).contains(http.statusCode) else { return nil }
                RadarTileStore.shared.store(data, for: url)
                return data
            } catch {
                // Transport error (timeout, offline blip): cache nothing —
                // the tile heals on the next draw once the network recovers.
                return nil
            }
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        return data
    }
}

/// Fetches every frame's tiles in playback order and reports which frames are
/// complete. `RadarView` only steps onto frames this says are ready.
@MainActor
@Observable
final class RadarPrefetcher {
    /// Frames whose tiles are all in the store.
    private(set) var readyFrames: Set<Int> = []
    /// While false, playback runs unguarded — so if the tile set is never
    /// learned, the timeline behaves exactly as it did before rather than
    /// waiting on downloads that will never be reported.
    private(set) var isActive = false

    private var signature: String?
    private var job: Task<Void, Never>?
    private var hasStarted = false
    private var armTimeout: Task<Void, Never>?

    /// Where playback is now, so a Low Data Mode session can stay just ahead of
    /// it rather than pulling the whole timeline.
    var playbackIndex = 0

    /// How many tiles of one frame download at a time — sized to land a whole
    /// frame inside playback's 0.5 s step (see the session's connection limit).
    private var concurrentTiles: Int { NetworkConditions.shared.isConstrained ? 6 : 20 }

    /// How far ahead of playback the download runs in Low Data Mode: enough to
    /// keep the picture moving, little enough that closing the radar early
    /// doesn't mean having paid for hours you never watched.
    private let constrainedLookahead = 6

    func isReady(_ index: Int) -> Bool { !isActive || readyFrames.contains(index) }

    /// Called as soon as a field loads — before the tile set is known — so
    /// playback doesn't sprint through the opening frames while the very first
    /// tiles are still on the wire. If nothing has started downloading shortly
    /// after, the prefetcher stands down and playback runs unguarded.
    func arm() {
        cancel()
        readyFrames = []
        signature = nil
        hasStarted = false
        isActive = true
        armTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.hasStarted else { return }
            self.isActive = false
        }
    }

    /// `urls` holds one list of tile URLs per frame. `signature` identifies the
    /// field and the tile set, so re-reporting the same work is a no-op.
    func start(signature: String, urls: [[URL]], from startIndex: Int) {
        guard signature != self.signature else { return }
        self.signature = signature
        job?.cancel()
        armTimeout?.cancel()
        readyFrames = []
        isActive = true
        hasStarted = true

        let count = urls.count
        let order = playbackOrder(count: count, from: startIndex)
        job = Task { [weak self] in
            for (position, index) in order.enumerated() {
                if Task.isCancelled { return }
                // In Low Data Mode, wait rather than run away from playback.
                while let self, NetworkConditions.shared.isConstrained,
                      position - Self.position(of: playbackIndex, from: startIndex, count: count)
                          > constrainedLookahead {
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { return }
                }
                guard let limit = self?.concurrentTiles else { return }
                await Self.fetch(urls[index], limit: limit)
                if Task.isCancelled { return }
                self?.readyFrames.insert(index)
            }
        }
    }

    /// How far into the play order a frame sits — playback runs forward from
    /// where the view opened and wraps, so this is the distance in that order.
    private static func position(of index: Int, from start: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index - start) % count + count) % count
    }

    func cancel() {
        job?.cancel()
        job = nil
        armTimeout?.cancel()
        armTimeout = nil
    }

    /// Playback runs forward from wherever the view opens and wraps around, so
    /// download in that order — the frames needed soonest arrive first.
    private func playbackOrder(count: Int, from start: Int) -> [Int] {
        guard count > 0 else { return [] }
        let first = min(max(start, 0), count - 1)
        return Array(first..<count) + Array(0..<first)
    }

    private nonisolated static func fetch(_ urls: [URL], limit: Int) async {
        var pending = urls.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<limit {
                guard let url = pending.next() else { break }
                group.addTask { _ = await RadarTileFetcher.shared.data(for: url) }
            }
            for await _ in group {
                guard !Task.isCancelled, let url = pending.next() else { continue }
                group.addTask { _ = await RadarTileFetcher.shared.data(for: url) }
            }
        }
    }
}

/// A tile overlay that draws from the app's own cache, and reports the tile
/// paths MapKit asks for so the prefetcher knows exactly what to download.
nonisolated final class RadarTileOverlay: MKTileOverlay {
    /// Set on the frame overlays of the animated map only; nil for the static
    /// home-screen preview, which has nothing to prefetch. Immutable on
    /// purpose: `loadTile` runs on MapKit's background queues, so safe
    /// publication has to come from initialization, not call-site ordering.
    let onRequest: (@MainActor (RadarTilePath) -> Void)?

    init(urlTemplate: String?, onRequest: (@MainActor (RadarTilePath) -> Void)? = nil) {
        self.onRequest = onRequest
        super.init(urlTemplate: urlTemplate)
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, (any Error)?) -> Void) {
        let url = url(forTilePath: path)

        if let onRequest {
            let recorded = RadarTilePath(path)
            Task { @MainActor in onRequest(recorded) }
        }

        if let cached = RadarTileStore.shared.data(for: url) {
            result(cached.isEmpty ? nil : cached,
                   cached.isEmpty ? RadarTileError.unavailable : nil)
            return
        }

        Task {
            let data = await RadarTileFetcher.shared.data(for: url)
            result(data, data == nil ? RadarTileError.unavailable : nil)
        }
    }
}
