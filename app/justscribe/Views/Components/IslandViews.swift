//
//  IslandViews.swift
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

/// The listening waveform in the compact island: bars that follow the microphone level.
struct IslandWaveformView: View {
    let bars: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 2, height: 3 + CGFloat(level) * 11)
            }
        }
        .frame(height: 14)
        .animation(.linear(duration: 0.05), value: bars)
    }
}

/// A spinner drawn by hand. The system one takes its colour from the window's appearance,
/// which on the black island in light mode means dark grey on black: an empty space.
struct IslandSpinnerView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .trim(from: 0.2, to: 1)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turn * 360))
        }
    }
}
