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

struct GrammarCorrectionModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let provider: String
    let hubID: String
    let approximateSize: String
    let approximateRAM: String
    let approximateRAMInMB: Int

    static let llama3_1_8b_4bit = GrammarCorrectionModel(
        id: "llama-3.1-8b-instruct-4bit",
        displayName: "Llama 3.1 8B Instruct",
        provider: "Meta (4-bit MLX)",
        hubID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        approximateSize: "~4.6 GB",
        approximateRAM: "~5 GB",
        approximateRAMInMB: 5120
    )

    static let allModels: [GrammarCorrectionModel] = [.llama3_1_8b_4bit]

    static func model(forID id: String) -> GrammarCorrectionModel? {
        allModels.first { $0.id == id }
    }
}
