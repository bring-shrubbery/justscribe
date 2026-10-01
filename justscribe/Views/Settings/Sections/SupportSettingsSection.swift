//
//  SupportSettingsSection.swift
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

struct SupportSettingsSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsSectionContainer(title: "Support JustScribe") {
            VStack(alignment: .leading, spacing: 12) {
                Text("JustScribe is free and open source. If it saves you time, sponsoring helps keep the project going. Sponsoring unlocks nothing — it's just a thank-you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openURL(Constants.URLs.sponsor)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Sponsor on GitHub")
                    }
                }
                .buttonStyle(.pill)
            }
        }
    }
}
