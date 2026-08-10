//
//  MetricTile.swift
//  Weather
//
//  Compact labelled metric used in the details grid.
//

import SwiftUI

struct MetricTile<Detail: View>: View {
    let icon: String
    let label: String
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    @ViewBuilder var detail: Detail

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(systemImage: icon, title: label)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.serif(.title))
                        .foregroundStyle(.white)
                    if let unit {
                        Text(unit)
                            .font(.serif(.title3, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                detail

                if let caption {
                    Text(caption)
                        .font(.serif(.footnote))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        }
    }
}

extension MetricTile where Detail == EmptyView {
    init(icon: String, label: String, value: String, unit: String? = nil, caption: String? = nil) {
        self.init(icon: icon, label: label, value: value, unit: unit, caption: caption) {
            EmptyView()
        }
    }
}
