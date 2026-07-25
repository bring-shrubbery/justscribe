//
//  GrammarCorrectionModel.swift
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

import Foundation

/// Which engine runs a given grammar correction model.
nonisolated enum GrammarModelBackend: Hashable {
    /// Apple's on-device foundation model, part of macOS. No download, no RAM budget.
    case apple
    /// An MLX model downloaded from Hugging Face and held in our process.
    case mlx
}

nonisolated struct GrammarCorrectionModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let provider: String
    let backend: GrammarModelBackend
    /// Hugging Face repo. `nil` for backends that don't download anything.
    let hubID: String?
    let approximateSize: String?
    let approximateRAM: String?
    /// Contribution to our own RAM budget. `nil` when the OS owns the memory.
    let approximateRAMInMB: Int?

    static let appleFoundation = GrammarCorrectionModel(
        id: "apple-foundation",
        displayName: "Apple Intelligence",
        provider: "Built into macOS",
        backend: .apple,
        hubID: nil,
        approximateSize: nil,
        approximateRAM: nil,
        approximateRAMInMB: nil
    )

    static let llama3_1_8b_4bit = GrammarCorrectionModel(
        id: "llama-3.1-8b-instruct-4bit",
        displayName: "Llama 3.1 8B Instruct",
        provider: "Meta (4-bit MLX)",
        backend: .mlx,
        hubID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        approximateSize: "~4.6 GB",
        approximateRAM: "~5 GB",
        approximateRAMInMB: 5120
    )

    static let allModels: [GrammarCorrectionModel] = [.appleFoundation, .llama3_1_8b_4bit]

    /// Selected for new installs: no download, no RAM cost.
    static let defaultModelID = appleFoundation.id

    static func model(forID id: String) -> GrammarCorrectionModel? {
        allModels.first { $0.id == id }
    }
}
