//
//  EmojiKeyboard.swift
//  JustScribeKeyboard
//
//  Created by Antoni Silvestrovic on 22/10/2026.
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

import KeyboardCore
import SwiftUI

/// A plain emoji keyboard: one category at a time in a sideways grid, with the
/// categories, ABC and delete along the bottom.
struct EmojiKeyboard: View {

    let actionHandler: KeyboardActionHandler

    @State private var category: EmojiCategory = .smileysAndPeople

    private let rows = Array(repeating: GridItem(.fixed(44), spacing: 2), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 2) {
                    ForEach(category.emojis) { emoji in
                        Button {
                            actionHandler.handle(.emoji(emoji))
                        } label: {
                            Text(emoji.char)
                                .font(.system(size: 32))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            .id(category)

            HStack(spacing: 0) {
                Button("ABC") { actionHandler.handle(.keyboardType(.alphabetic)) }
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 48)
                ForEach(EmojiCategory.standardCategories) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item.emojiIcon)
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(item == category ? Color.primary.opacity(0.12) : .clear, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    actionHandler.handle(.backspace)
                } label: {
                    Image(systemName: "delete.left")
                }
                .frame(width: 48)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 6)
        }
        .frame(height: 5 * 46 + 44)
    }
}
