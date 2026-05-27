//
//  RAMEstimate.swift
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

enum RAMEstimate {
    /// Returns the total estimated RAM, in MB, that the currently configured
    /// transcription + grammar correction models would consume if loaded
    /// simultaneously. Returns 0 when nothing is configured.
    static func totalMB(transcriptionModelID: String,
                        grammarEnabled: Bool,
                        grammarModelID: String) -> Int {
        var total = 0
        if let model = UnifiedModelInfo.model(forID: transcriptionModelID) {
            total += model.approximateRAMInMB
        }
        if grammarEnabled,
           let model = GrammarCorrectionModel.model(forID: grammarModelID) {
            total += model.approximateRAMInMB
        }
        return total
    }

    /// Human-friendly formatting: "~480 MB" for sub-gigabyte estimates,
    /// "~5.6 GB" otherwise.
    static func format(totalMB: Int) -> String {
        if totalMB <= 0 { return "\u{2014}" } // em dash
        if totalMB < 1024 {
            return "~\(totalMB) MB"
        }
        let gb = Double(totalMB) / 1024.0
        return String(format: "~%.1f GB", gb)
    }
}
