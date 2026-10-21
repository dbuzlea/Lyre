//
//  PodcastDownloads.swift
//  Lyre
//

import Foundation
import CryptoKit
import OSLog
internal import Combine

private let logger = Logger(subsystem: "com.pinkhatcreations.lyreapp", category: "PodcastDownloads")

// MARK: - PodcastDownloads
//
// Saves streamed episodes to the device for listening offline. PodcastStreamPlayer
// plays the saved file whenever there is one, so a downloaded episode plays the same
// way as a streamed one, just without the network.
//
// Downloads run on a background URLSession, so they carry on when the app is
// suspended or even terminated by the system. iOS relaunches the app in the
// background to hand over finished files; AppDelegate passes the completion handler
// in through `backgroundCompletionHandler`.
//
// Files live in Application Support/PodcastDownloads (not Caches — the system must
// not purge an episode the user saved for a flight). Which file belongs to which
// episode is kept in UserDefaults.
//
// Main thread only, apart from the URLSession delegate methods, which are nonisolated
// and hop back to the main thread for any state change.

final class PodcastDownloads: NSObject, ObservableObject {
    static let shared = PodcastDownloads()

    enum State: Equatable {
        case downloading(progress: Double)
        case downloaded
    }

    @Published private(set) var states: [String: State] = [:]

    /// Called by AppDelegate's background-session hook; run once the session has
    /// delivered everything.
    var backgroundCompletionHandler: (() -> Void)?

    /// Settings, shared with the switches in PodcastSearchView through @AppStorage.
    static let autoDownloadNewKey = "podcast.autoDownloadNew"
    static let removeAfterPlayingKey = "podcast.removeAfterPlaying"

    var autoDownloadNew: Bool { UserDefaults.standard.bool(forKey: Self.autoDownloadNewKey) }
    var removeAfterPlaying: Bool { UserDefaults.standard.bool(forKey: Self.removeAfterPlayingKey) }

    private static let sessionIdentifier = "com.pinkhatcreations.lyreapp.podcastDownloads"
    private static let filesKey = "podcast.downloadedFiles"

    /// Episode ID → file name in the downloads directory.
    private var files: [String: String]
    private var session: URLSession!

    private nonisolated static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "PodcastDownloads", directoryHint: .isDirectory)
    }

    private override init() {
        files = UserDefaults.standard.dictionary(forKey: Self.filesKey) as? [String: String] ?? [:]
        super.init()

        // Forget files that have gone missing, so they don't claim to be playable.
        files = files.filter { FileManager.default.fileExists(atPath: Self.directory.appending(path: $0.value).path) }
        UserDefaults.standard.set(files, forKey: Self.filesKey)
        for id in files.keys { states[id] = .downloaded }

        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        // Reattach to downloads that were still running when the app last quit.
        session.getAllTasks { tasks in
            let running = tasks.compactMap(\.taskDescription)
            DispatchQueue.main.async {
                for id in running where self.states[id] == nil {
                    self.states[id] = .downloading(progress: 0)
                }
            }
        }
    }

    // MARK: - Queries

    func state(for episodeID: String) -> State? {
        states[episodeID]
    }

    /// The saved file for an episode, if it has been downloaded.
    func localFile(for episodeID: String) -> URL? {
        files[episodeID].map { Self.directory.appending(path: $0) }
    }

    var hasDownloads: Bool { !files.isEmpty }

    /// Space the saved episodes take up, in bytes.
    func totalSize() -> Int64 {
        files.values.reduce(0) { total, name in
            let size = try? Self.directory.appending(path: name).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return total + Int64(size ?? 0)
        }
    }

    // MARK: - Actions

    /// Starts downloading an episode. `onlyOnWiFi` holds an automatic download back
    /// until the phone is on an unmetered network, rather than spending mobile data
    /// the user didn't ask to spend.
    func download(_ episode: PodcastEpisode, onlyOnWiFi: Bool = false) {
        guard let url = episode.streamURL, states[episode.id] == nil else { return }
        var request = URLRequest(url: url)
        if onlyOnWiFi {
            request.allowsExpensiveNetworkAccess = false
            request.allowsConstrainedNetworkAccess = false
        }
        let task = session.downloadTask(with: request)
        task.taskDescription = episode.id
        states[episode.id] = .downloading(progress: 0)
        task.resume()
        logger.info("Downloading '\(episode.title)'")
    }

    /// Cancels a running download or deletes a finished one.
    func remove(_ episodeID: String) {
        switch states[episodeID] {
        case .downloading:
            session.getAllTasks { tasks in
                tasks.first { $0.taskDescription == episodeID }?.cancel()
            }
            states[episodeID] = nil
        case .downloaded:
            deleteFile(for: episodeID)
        case nil:
            break
        }
    }

    func remove(episodeIDs: [String]) {
        for id in episodeIDs { remove(id) }
    }

    func removeAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        for id in files.keys { deleteFile(for: id) }
        states = [:]
        logger.notice("Removed all podcast downloads")
    }

    // MARK: - Private

    private func deleteFile(for episodeID: String) {
        if let file = localFile(for: episodeID) {
            try? FileManager.default.removeItem(at: file)
        }
        files[episodeID] = nil
        states[episodeID] = nil
        UserDefaults.standard.set(files, forKey: Self.filesKey)
    }

    private func didSave(_ fileName: String, for episodeID: String) {
        // Removed while the last bytes were arriving: honour the removal.
        guard states[episodeID] != nil else {
            try? FileManager.default.removeItem(at: Self.directory.appending(path: fileName))
            return
        }
        files[episodeID] = fileName
        states[episodeID] = .downloaded
        UserDefaults.standard.set(files, forKey: Self.filesKey)
        logger.info("Downloaded episode \(episodeID)")
    }

    /// A stable file name per episode. IDs are feed GUIDs, which can be anything, so
    /// they are hashed rather than used as names.
    nonisolated static func fileName(for episodeID: String, remoteURL: URL?) -> String {
        let hash = SHA256.hash(data: Data(episodeID.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let ext = remoteURL?.pathExtension.lowercased() ?? ""
        let known = ["mp3", "m4a", "aac", "mp4", "m4v", "mov", "wav", "ogg", "opus"]
        return "\(hash).\(known.contains(ext) ? ext : "mp3")"
    }
}

// MARK: - URLSessionDownloadDelegate

extension PodcastDownloads: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let episodeID = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            logger.error("Download of \(episodeID) failed with HTTP \(http.statusCode)")
            return
        }
        // The temporary file is deleted as soon as this returns, so move it now.
        let name = Self.fileName(for: episodeID, remoteURL: downloadTask.originalRequest?.url)
        let destination = Self.directory.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = destination
            try? excluded.setResourceValues(values)
        } catch {
            logger.error("Could not save download \(episodeID): \(error.localizedDescription)")
            return
        }
        DispatchQueue.main.async { self.didSave(name, for: episodeID) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let episodeID = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            // Only whole percents, so a fast download doesn't redraw every few KB.
            guard case .downloading(let previous) = self.states[episodeID],
                  Int(progress * 100) != Int(previous * 100) else { return }
            self.states[episodeID] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let episodeID = task.taskDescription else { return }
        if let error, (error as? URLError)?.code != .cancelled {
            logger.error("Download of \(episodeID) failed: \(error.localizedDescription)")
        }
        DispatchQueue.main.async {
            // Anything that ended without a saved file goes back to not downloaded.
            if case .downloading = self.states[episodeID] { self.states[episodeID] = nil }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
