//
//  GrammarCorrectionModel.swift
//  justscribe
//

import Foundation

struct GrammarCorrectionModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let provider: String
    let hubID: String
    let approximateSize: String
    let approximateRAM: String

    static let llama3_1_8b_4bit = GrammarCorrectionModel(
        id: "llama-3.1-8b-instruct-4bit",
        displayName: "Llama 3.1 8B Instruct",
        provider: "Meta (4-bit MLX)",
        hubID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        approximateSize: "~4.6 GB",
        approximateRAM: "~5 GB"
    )

    static let allModels: [GrammarCorrectionModel] = [.llama3_1_8b_4bit]

    static func model(forID id: String) -> GrammarCorrectionModel? {
        allModels.first { $0.id == id }
    }
}
