//
//  LinksSettingsSection.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
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

struct LinksSettingsSection: View {
    var body: some View {
        SettingsSectionContainer(title: "About") {
            VStack(spacing: 0) {
                LinkRow(
                    title: "Website",
                    systemImage: "globe",
                    url: Constants.URLs.website
                )

                Divider()
                    .padding(.leading, 44)

                LinkRow(
                    title: "Privacy Policy",
                    systemImage: "hand.raised",
                    url: Constants.URLs.privacyPolicy
                )

                Divider()
                    .padding(.leading, 44)

                LinkRow(
                    title: "Terms of Service",
                    systemImage: "doc.text",
                    url: Constants.URLs.termsOfService
                )

                Divider()
                    .padding(.leading, 44)

                LinkRow(
                    title: "Credits",
                    systemImage: "heart",
                    url: Constants.URLs.credits
                )

                Divider()
                    .padding(.leading, 44)

                LinkRow(
                    title: "Support",
                    systemImage: "questionmark.circle",
                    url: Constants.URLs.support
                )
            }

            // Version info
            HStack {
                Spacer()
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct LinkRow: View {
    let title: String
    let systemImage: String
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
