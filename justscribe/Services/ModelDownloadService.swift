//
//  ModelDownloadService.swift
//  justscribe
//
//  Created by Antoni Silvestrovic on 24/01/2026.
//

import Foundation
import Combine

@Observable
final class ModelDownloadService: NSObject {
    static let shared = ModelDownloadService()

    private(set) var activeDownloads: [String: DownloadTask] = [:]

    private var urlSession: URLSession!
    private var downloadTasks: [URLSessionDownloadTask: String] = [:]

    struct DownloadTask {
        let modelID: String
        var progress: Double
        var totalBytes: Int64
        var downloadedBytes: Int64
        var error: Error?
        var isCompleted: Bool
    }

    override init() {
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // 1 hour for large models

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func downloadModel(id: String, from url: URL, to destination: URL) async throws {
        // Check if already downloading
        guard activeDownloads[id] == nil else {
            throw DownloadError.alreadyDownloading
        }

        // Create download task
        let task = urlSession.downloadTask(with: url)
        downloadTasks[task] = id

        activeDownloads[id] = DownloadTask(
            modelID: id,
            progress: 0,
            totalBytes: 0,
            downloadedBytes: 0,
            error: nil,
            isCompleted: false
        )

        task.resume()

        // Wait for completion
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                while let download = activeDownloads[id], !download.isCompleted {
                    if let error = download.error {
                        activeDownloads.removeValue(forKey: id)
                        continuation.resume(throwing: error)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }

                if let error = activeDownloads[id]?.error {
                    activeDownloads.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                } else {
                    activeDownloads.removeValue(forKey: id)
                    continuation.resume()
                }
            }
        }
    }

    func cancelDownload(modelID: String) {
        for (task, id) in downloadTasks where id == modelID {
            task.cancel()
            downloadTasks.removeValue(forKey: task)
        }
        activeDownloads.removeValue(forKey: modelID)
    }

    func progress(for modelID: String) -> Double {
        activeDownloads[modelID]?.progress ?? 0
    }

    enum DownloadError: LocalizedError {
        case alreadyDownloading
        case downloadFailed(underlying: Error?)
        case fileMoveFailed

        var errorDescription: String? {
            switch self {
            case .alreadyDownloading:
                return "This model is already being downloaded."
            case .downloadFailed(let error):
                return "Download failed: \(error?.localizedDescription ?? "Unknown error")"
            case .fileMoveFailed:
                return "Failed to save the downloaded model."
            }
        }
    }
}

extension ModelDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelID = downloadTasks[downloadTask] else { return }

        let destinationURL = Constants.Storage.modelsDirectory.appendingPathComponent("\(modelID).bin")

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Move downloaded file
            try FileManager.default.moveItem(at: location, to: destinationURL)

            activeDownloads[modelID]?.isCompleted = true
            activeDownloads[modelID]?.progress = 1.0
        } catch {
            activeDownloads[modelID]?.error = DownloadError.fileMoveFailed
        }

        downloadTasks.removeValue(forKey: downloadTask)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let modelID = downloadTasks[downloadTask] else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        activeDownloads[modelID]?.progress = progress
        activeDownloads[modelID]?.downloadedBytes = totalBytesWritten
        activeDownloads[modelID]?.totalBytes = totalBytesExpectedToWrite
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let modelID = downloadTasks[downloadTask] else { return }

        if let error = error {
            activeDownloads[modelID]?.error = DownloadError.downloadFailed(underlying: error)
            activeDownloads[modelID]?.isCompleted = true
        }

        downloadTasks.removeValue(forKey: downloadTask)
    }
}
