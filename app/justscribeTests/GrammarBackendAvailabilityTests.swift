//
//  GrammarBackendAvailabilityTests.swift
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

import FoundationModels
import Testing
@testable import justscribe

struct GrammarBackendAvailabilityTests {

    @Test func availableMapsToAvailable() {
        #expect(AppleFoundationGrammarBackend.availability(for: .available) == .available)
    }

    @Test func ineligibleDeviceHasNoSettingsLink() {
        // Nothing the user can do in System Settings, so don't offer a button.
        let result = AppleFoundationGrammarBackend.availability(for: .unavailable(.deviceNotEligible))
        guard case .unavailable(let reason, let url) = result else {
            Issue.record("expected .unavailable, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(url == nil)
    }

    @Test func disabledIntelligenceOffersASettingsLink() {
        let result = AppleFoundationGrammarBackend.availability(for: .unavailable(.appleIntelligenceNotEnabled))
        guard case .unavailable(let reason, let url) = result else {
            Issue.record("expected .unavailable, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(url != nil)
    }

    @Test func modelNotReadyOffersASettingsLink() {
        let result = AppleFoundationGrammarBackend.availability(for: .unavailable(.modelNotReady))
        guard case .unavailable(let reason, let url) = result else {
            Issue.record("expected .unavailable, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(url != nil)
    }

    @Test func paddingIsRestoredAroundCorrectedText() {
        // Chunks are trimmed before generation; rejoining must reproduce the spacing.
        let restored = AppleFoundationGrammarBackend.reapplyPadding(from: "  hi there.  ", to: "Hi there.")
        #expect(restored == "  Hi there.  ")
    }

    @Test func paddingIsANoOpWhenThereIsNone() {
        #expect(AppleFoundationGrammarBackend.reapplyPadding(from: "hi", to: "Hi") == "Hi")
    }
}
