//
//  FileTranscriptionView.swift
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

import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @Bindable var model: FileTranscriptionModel
    let openSettings: () -> Void

    @State private var isChoosingFile = false
    @State private var isDropTargeted = false
    /// Whether the transcript is scrolled to (or near) its end; only then does it follow new text.
    @State private var isAtTranscriptEnd = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let job = model.job {
                jobView(job)
            } else {
                startView
            }
        }
        .padding(20)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.audio, .movie]) { result in
            if case .success(let url) = result { model.open(url) }
        }
    }

    // MARK: - Before a file is chosen

    private var startView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Drop an audio or video file here")
                    .font(.headline)
                Button("Choose File…") { isChoosingFile = true }
                    .buttonStyle(.pill)
                    .disabled(!model.hasModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard model.hasModel, let provider = providers.first else { return false }
                // The dropped file's URL as the drag gave it, which the sandbox has granted.
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    Task { @MainActor in
                        if let url { model.open(url) } else { model.refuseDrop() }
                    }
                }
                return true
            }

            if !model.hasModel {
                HStack {
                    Label(FileTranscriptionJob.Message.noModel, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Open Settings", action: openSettings).buttonStyle(.pill)
                }
                .font(.callout)
            }

            speakerOptions

            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var speakerOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identify speakers").font(.body)
                    Text("Labels who said what. Uses a small extra model, downloaded once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $model.identifySpeakers)
                    .toggleStyle(.pill)
                    .labelsHidden()
            }
            // The download reports its two steps separately, so its fraction runs backwards.
            if model.diarization.downloadProgress != nil {
                ProgressView { Text("Downloading the speaker model…").font(.caption) }
                    .progressViewStyle(.linear)
            }
            if model.identifySpeakers {
                HStack {
                    Text("Speakers").font(.callout)
                    TextField("Detect", text: $model.speakerCountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(FileTranscriptionModel.speakerCountHint(for: model.speakerCountText))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - While a file runs, and after

    @ViewBuilder
    private func jobView(_ job: FileTranscriptionJob) -> some View {
        Text(job.url.lastPathComponent)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)

        status(job)

        transcript(job)

        if let notice = model.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
        }

        HStack {
            if job.isRunning {
                Button("Cancel") { model.cancel() }
                    .buttonStyle(.pill)
                    .disabled(job.isCancelling)
            } else {
                Button("Transcribe Another") { model.reset() }.buttonStyle(.pill)
                if job.phase == .failed(FileTranscriptionJob.Message.speakersFailed) {
                    Button("Transcribe Without Speakers") { model.retryWithoutSpeakers() }.buttonStyle(.pill)
                }
                if job.phase == .failed(FileTranscriptionJob.Message.noModel) {
                    Button("Open Settings", action: openSettings).buttonStyle(.pill)
                }
            }
            Spacer()
            // Hidden once a job has ended with nothing, so the retry buttons have room.
            if job.isRunning || !job.paragraphs.isEmpty {
                Button("Copy") { model.copy() }
                    .buttonStyle(.pill)
                    .disabled(job.paragraphs.isEmpty)
                Button("Save…") { model.save() }
                    .buttonStyle(.pill)
                    .disabled(job.paragraphs.isEmpty)
            }
        }
        .lineLimit(1)
    }

    /// One row per paragraph, laid out lazily: a long file's transcript is never measured
    /// as a whole, and a new chunk leaves the rows above it alone.
    private func transcript(_ job: FileTranscriptionJob) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(job.paragraphs.indices, id: \.self) { index in
                        ParagraphRow(paragraph: job.paragraphs[index])
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
            } action: { _, isAtEnd in
                isAtTranscriptEnd = isAtEnd
            }
            .onChange(of: job.paragraphs.last?.text) {
                if job.isRunning, isAtTranscriptEnd { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func status(_ job: FileTranscriptionJob) -> some View {
        switch FileTranscriptionModel.status(of: job) {
        case .working(let text, let progress?):
            ProgressView(value: progress) { statusText(text) }
        case .working(let text, nil):
            ProgressView { statusText(text) }
                .progressViewStyle(.linear)
        case .ended(let text, let systemImage):
            Label(text, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text).font(.caption).lineLimit(1)
    }
}

/// A paragraph of the transcript: its time and speaker, then what was said.
private struct ParagraphRow: View {
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
        let label = paragraph.speaker.map { " Speaker \($0)" } ?? ""
        return "[\(TranscriptBuilder.timestamp(paragraph.start))]\(label)"
    }
}
