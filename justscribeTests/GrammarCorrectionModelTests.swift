//
//  GrammarCorrectionModelTests.swift
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

import Testing
@testable import justscribe

struct GrammarCorrectionModelTests {

    @Test func appleModelIsTheDefault() {
        #expect(GrammarCorrectionModel.defaultModelID == GrammarCorrectionModel.appleFoundation.id)
    }

    @Test func appleModelIsListedFirst() {
        #expect(GrammarCorrectionModel.allModels.first?.id == GrammarCorrectionModel.appleFoundation.id)
    }

    @Test func appleModelNeedsNoDownload() {
        let model = GrammarCorrectionModel.appleFoundation
        #expect(model.backend == .apple)
        #expect(model.hubID == nil)
        #expect(model.approximateRAMInMB == nil)
    }

    @Test func llamaModelKeepsItsExistingIdentifier() {
        // Persisted in UserDefaults by existing installs; changing it would silently
        // reset their selection.
        let model = GrammarCorrectionModel.llama3_1_8b_4bit
        #expect(model.id == "llama-3.1-8b-instruct-4bit")
        #expect(model.backend == .mlx)
        #expect(model.hubID == "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit")
    }

    @Test func lookupFindsBothModels() {
        #expect(GrammarCorrectionModel.model(forID: "apple-foundation") != nil)
        #expect(GrammarCorrectionModel.model(forID: "llama-3.1-8b-instruct-4bit") != nil)
        #expect(GrammarCorrectionModel.model(forID: "nope") == nil)
    }

    // `RAMEstimate` is a plain enum in the app target, so it inherits that target's
    // MainActor default isolation. This test must hop to the main actor to call it.
    @MainActor
    @Test func appleModelContributesNothingToTheRAMEstimate() {
        // The OS owns the foundation model's memory, not us.
        let total = RAMEstimate.totalMB(
            transcriptionModelID: "",
            grammarEnabled: true,
            grammarModelID: "apple-foundation"
        )
        #expect(total == 0)
    }

    @Test func aBlankStoredSelectionBecomesTheAppleModel() {
        // Installs that never picked a model should land on the zero-cost default.
        #expect(AppSettings.normalizedGrammarModelID("") == "apple-foundation")
    }

    @Test func anExistingLlamaSelectionIsPreserved() {
        // Explicit user choices are never overridden.
        #expect(
            AppSettings.normalizedGrammarModelID("llama-3.1-8b-instruct-4bit")
                == "llama-3.1-8b-instruct-4bit"
        )
    }

    @Test func anUnknownStoredSelectionFallsBackToTheDefault() {
        #expect(AppSettings.normalizedGrammarModelID("deleted-model") == "apple-foundation")
    }
}
