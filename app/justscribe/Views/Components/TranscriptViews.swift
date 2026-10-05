//
//  TranscriptViews.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 05/10/2026.
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

/// A transcript's paragraphs, one row each, laid out lazily: a long transcript is never
/// measured as a whole, and a new chunk leaves the rows above it alone. Follows new text
/// while `isGrowing` and the view is scrolled to (or near) its end.
struct TranscriptScrollView: View {
    let paragraphs: [TranscriptParagraph]
    let isGrowing: Bool

    /// Whether the transcript is scrolled to (or near) its end; only then does it follow new text.
    @State private var isAtEnd = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        TranscriptParagraphRow(paragraph: paragraphs[index])
                    }
                }
                .padding(12)
                Color.clear.frame(height: 1).id("end")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 40
            } action: { _, atEnd in
                isAtEnd = atEnd
            }
            .onChange(of: paragraphs.last?.text) {
                if isGrowing, isAtEnd { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}

/// A paragraph of the transcript: its time and speaker, then what was said.
struct TranscriptParagraphRow: View {
    let paragraph: TranscriptParagraph

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(paragraph.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }

    private var header: String {
        let label = paragraph.label.map { " " + $0 } ?? ""
        return "[\(TranscriptBuilder.timestamp(paragraph.start))]\(label)"
    }
}
