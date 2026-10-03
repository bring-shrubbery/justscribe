//
//  VoiceCommandProcessor.swift
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

/// Spoken commands in a transcript: layout ("new line"), editing ("scratch that"), session
/// ("stop recording", "send") and, when turned on, punctuation words. Pure; English phrases.
nonisolated enum VoiceCommandProcessor {

    private enum Command: Equatable {
        /// `anywhere`: "scratch that" fires mid-clause; "delete that" must stand alone ("delete that email").
        case newLine, newParagraph, scratch(anywhere: Bool), stop, send
        case punctuation(String, glue: Glue)
    }
    private enum Glue: Equatable { case previous, next }

    private static let layoutAndEditing: [([String], Command)] = [
        (["new", "paragraph"], .newParagraph),
        (["new", "line"], .newLine),
        (["scratch", "that"], .scratch(anywhere: true)),
        (["delete", "that"], .scratch(anywhere: false)),
    ]
    private static let session: [([String], Command)] = [
        (["stop", "recording"], .stop),
        (["stop", "dictation"], .stop),
        (["press", "enter"], .send),
        (["send"], .send),
    ]
    private static let punctuation: [([String], Command)] = [
        (["full", "stop"], .punctuation(".", glue: .previous)),
        (["period"], .punctuation(".", glue: .previous)),
        (["comma"], .punctuation(",", glue: .previous)),
        (["question", "mark"], .punctuation("?", glue: .previous)),
        (["exclamation", "mark"], .punctuation("!", glue: .previous)),
        (["exclamation", "point"], .punctuation("!", glue: .previous)),
        (["colon"], .punctuation(":", glue: .previous)),
        (["semicolon"], .punctuation(";", glue: .previous)),
        (["open", "quote"], .punctuation("\"", glue: .next)),
        (["close", "quote"], .punctuation("\"", glue: .previous)),
        (["dash"], .punctuation("—", glue: .previous)),
    ]

    /// A whitespace-separated token: the word with the punctuation the model put around it.
    private struct Token {
        var leading: String
        var core: String
        var trailing: String
        var lowercased: String { core.lowercased() }
        var endsSentence: Bool { trailing.contains(where: { ".?!".contains($0) }) }
        var endsClause: Bool { trailing.contains(where: { ".?!,;:".contains($0) }) }
        var text: String { leading + core + trailing }
    }

    private static func tokens(_ text: String) -> [Token] {
        text.split(whereSeparator: \.isWhitespace).map { piece in
            let s = String(piece)
            let coreStart = s.firstIndex(where: { $0.isLetter || $0.isNumber }) ?? s.endIndex
            let coreEnd = s.lastIndex(where: { $0.isLetter || $0.isNumber }).map { s.index(after: $0) } ?? coreStart
            return Token(leading: String(s[..<coreStart]), core: String(s[coreStart..<coreEnd]), trailing: String(s[coreEnd...]))
        }
    }

    /// Applies the commands and returns the text with them removed, plus the actions they asked for.
    /// With no command fired the text comes back as given. In hold mode (`sessionCommandsOn` off)
    /// the session phrases are ordinary words: "I want to stop recording" stays as said.
    static func apply(_ text: String, commandsOn: Bool, punctuationOn: Bool, sessionCommandsOn: Bool) -> (text: String, actions: [DictationAction]) {
        guard commandsOn else { return (text, []) }
        let all = tokens(text)
        var table = layoutAndEditing
        if sessionCommandsOn { table += session }
        if punctuationOn { table += punctuation }
        table.sort { $0.0.count > $1.0.count }   // longest phrase first

        var out: [Piece] = []
        var lastCommandEnd = 0        // index in `out` just after the last command's effect
        var pendingPrefix = ""        // an open quote waiting for the next word
        var actions: [DictationAction] = []
        var anyFired = false          // with none, the text is returned untouched (no re-spacing)
        func perform(_ action: DictationAction) {   // a repeated command asks once
            if !actions.contains(action) { actions.append(action) }
        }
        var i = 0
        while i < all.count {
            if let (phrase, command) = match(at: i, in: all, table: table) {
                let end = i + phrase.count
                let precededByBreak = i == 0 || all[i - 1].endsClause
                let followedByBreak = end == all.count || all[end - 1].endsClause
                let standsAlone = precededByBreak || followedByBreak
                let qualifies: Bool
                switch command {
                case .send: qualifies = precededByBreak && end == all.count
                case .punctuation: qualifies = true      // punctuation words live mid-sentence by nature
                case .scratch(let anywhere): qualifies = anywhere || standsAlone   // a correction follows the slip at once
                default: qualifies = standsAlone
                }
                if qualifies {
                    anyFired = true
                    switch command {
                    case .newLine:
                        out.append(.lineBreak("\n")); lastCommandEnd = out.count
                    case .newParagraph:
                        out.append(.lineBreak("\n\n")); lastCommandEnd = out.count
                    case .scratch:
                        // The sentence end right before the command is the pause before it, not a break
                        // to keep; with nothing new since the last command, remove the previous sentence.
                        var breakAt = max(lastCommandEnd, indexAfterLastSentenceEnd(out, ignoringLast: true))
                        if breakAt >= out.count { breakAt = indexAfterLastSentenceEnd(out, ignoringLast: true) }
                        out.removeSubrange(min(breakAt, out.count)...)
                        lastCommandEnd = out.count
                    case .stop:
                        perform(.stopRecording)
                        lastCommandEnd = out.count
                    case .send:
                        perform(.stopRecording); perform(.pressReturn)
                        lastCommandEnd = out.count
                    case .punctuation(let mark, let glue):
                        switch glue {
                        case .previous:
                            if let last = out.indices.last, case .word(let w) = out[last] { out[last] = .word(w + mark) }
                        case .next:
                            pendingPrefix += mark
                        }
                    }
                    i = end
                    continue
                }
            }
            let token = all[i]
            out.append(.word(pendingPrefix + token.text))
            pendingPrefix = ""
            i += 1
        }
        guard anyFired else { return (text, []) }
        return (render(out), actions)
    }

    /// The session command the streamed text ends with, if any — read live while recording.
    static func terminatingCommand(in streamed: String, sessionCommandsOn: Bool) -> DictationAction? {
        guard sessionCommandsOn else { return nil }
        let all = tokens(streamed)
        for (phrase, command) in session where all.count >= phrase.count {
            let start = all.count - phrase.count
            guard matches(phrase, at: start, in: all) else { continue }
            let precededByBreak = start == 0 || all[start - 1].endsClause
            switch command {
            case .stop: return .stopRecording
            case .send: return precededByBreak ? .pressReturn : nil
            default: continue
            }
        }
        return nil
    }

    // MARK: - Pieces

    private enum Piece { case word(String), lineBreak(String) }

    private static func match(at i: Int, in all: [Token], table: [([String], Command)]) -> ([String], Command)? {
        table.first { matches($0.0, at: i, in: all) }
    }

    private static func matches(_ phrase: [String], at i: Int, in all: [Token]) -> Bool {
        guard i + phrase.count <= all.count else { return false }
        for (offset, word) in phrase.enumerated() where all[i + offset].lowercased != word { return false }
        // Only the phrase's last word may carry punctuation; "new. line" is two words, not a command.
        return !all[i..<(i + phrase.count - 1)].contains(where: { !$0.trailing.isEmpty })
    }

    /// The position after the last sentence end in `out`; with `ignoringLast`, the final piece's own
    /// punctuation does not count (it is the boundary the command sits on).
    private static func indexAfterLastSentenceEnd(_ out: [Piece], ignoringLast: Bool) -> Int {
        let last = ignoringLast ? out.count - 2 : out.count - 1
        guard last >= 0 else { return 0 }
        for index in stride(from: last, through: 0, by: -1) {
            // The punctuation after the last letter or digit, so `yes."` and `done.)` end a sentence.
            if case .word(let w) = out[index],
               w.reversed().prefix(while: { !($0.isLetter || $0.isNumber) }).contains(where: { ".?!".contains($0) }) {
                return index + 1
            }
        }
        return 0
    }

    private static func render(_ pieces: [Piece]) -> String {
        var result = ""
        for piece in pieces {
            switch piece {
            case .lineBreak(let br):
                while result.last == " " { result.removeLast() }
                result += br
            case .word(let w):
                if !result.isEmpty, result.last != "\n" { result += " " }
                result += w
            }
        }
        while result.last == " " { result.removeLast() }   // a line break spoken at the end is kept
        return result
    }
}
