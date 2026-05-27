//
//  TipJarSettingsSection.swift
//  justscribe
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI
import StoreKit

struct TipJarSettingsSection: View {
    private var service: TipJarService { .shared }

    var body: some View {
        SettingsSectionContainer(title: "Support JustScribe") {
            VStack(alignment: .leading, spacing: 12) {
                Text("JustScribe is free. If it saves you time, a tip helps keep the project going. Tips unlock nothing — they're just a thank-you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if service.totalTipsPurchased > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text(thanksMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                content

                if let error = service.lastError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            await service.loadProducts()
        }
    }

    @ViewBuilder
    private var content: some View {
        if service.isLoadingProducts {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Loading tip options…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if service.products.isEmpty {
            Text("Tip options aren't available right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ForEach(service.products, id: \.id) { product in
                    TipButton(product: product)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var thanksMessage: String {
        let n = service.totalTipsPurchased
        if n == 1 {
            return "Thanks for supporting JustScribe!"
        }
        return "Thanks for supporting JustScribe — \(n) tips and counting!"
    }
}

private struct TipButton: View {
    let product: Product
    private var service: TipJarService { .shared }

    private var isPurchasing: Bool {
        service.purchasingProductID == product.id
    }

    private var isAnythingPurchasing: Bool {
        service.purchasingProductID != nil
    }

    var body: some View {
        Button {
            Task { await service.purchase(product) }
        } label: {
            VStack(spacing: 2) {
                if isPurchasing {
                    ProgressView().scaleEffect(0.7).frame(height: 16)
                } else {
                    Text(displayLabel)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text(product.displayPrice)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pill)
        .disabled(isAnythingPurchasing)
        .opacity(isAnythingPurchasing && !isPurchasing ? 0.5 : 1)
    }

    private var displayLabel: String {
        // App Store Connect display names are like "Small Tip"; strip the
        // " Tip" suffix when present to keep the button compact.
        let name = product.displayName
        if let range = name.range(of: " Tip") {
            return String(name[..<range.lowerBound])
        }
        return name.isEmpty ? "Tip" : name
    }
}
