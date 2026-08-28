//
//  DailyBriefCard.swift
//  Weather
//
//  The standfirst: two or three composed sentences describing the day, set in
//  italic serif like a magazine deck under the headline. This is the editorial
//  identity doing real work — the forecast in prose.
//

import SwiftUI

struct DailyBriefCard: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            // Centered and quiet, like the deck under a headline — it belongs
            // to the hero above it, not to the cards below.
            Text(text)
                .font(.serif(.callout, italic: true))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
        }
    }
}
