//
//  MacCardOverlay.swift
//  HazeMac
//
//  Where the iPhone presents a sheet, the Mac floats a card: the same page,
//  centred over a blur of the whole window with only a whisper of scrim, so
//  the sky and the forecast stay in view behind it. Clicking the blur or
//  pressing Escape puts it away.
//

import SwiftUI

struct MacCardOverlay: View {
    let presenter: CardPresenter

    private static let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        ZStack {
            if let card = presenter.card {
                ZStack {
                    BackdropBlurView(radius: 26)
                    Color.black.opacity(0.16)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { presenter.dismissCurrent() }
                .transition(.opacity)

                GeometryReader { geo in
                    card.content
                        .frame(width: min(580, geo.size.width - 80),
                               height: min(780, geo.size.height - 56))
                        .clipShape(Self.shape)
                        .overlay(Self.shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea()
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .id(card.id)
            }
        }
        .animation(UIPrefs.shared.reduceMotion ? nil
                   : .spring(response: 0.35, dampingFraction: 0.88),
                   value: presenter.card?.id)
    }
}
