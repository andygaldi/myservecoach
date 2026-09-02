import AVFoundation

protocol ChunkVideoConcatenating: Sendable {
    func concatenate(chunkURLs: [URL]) async throws -> URL
}

/// Assembles a Set Goal session's finalized chunk files into one playable video for persistence —
/// `GoalSession.videoURL` mirrors `ServeSession`'s shape, which requires a single file, not a
/// chunk list.
final class ChunkVideoConcatenator: ChunkVideoConcatenating {
    enum ConcatenateError: LocalizedError {
        case noChunks
        case exportSessionCreationFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noChunks:
                return "No recorded chunks to save."
            case .exportSessionCreationFailed:
                return "Could not create a video export session."
            case .exportFailed(let message):
                return "Could not assemble session video: \(message)"
            }
        }
    }

    func concatenate(chunkURLs: [URL]) async throws -> URL {
        guard !chunkURLs.isEmpty else { throw ConcatenateError.noChunks }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw ConcatenateError.exportSessionCreationFailed
        }

        var cursor = CMTime.zero
        for chunkURL in chunkURLs {
            let asset = AVURLAsset(url: chunkURL)
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)
            }
            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConcatenateError.exportSessionCreationFailed
        }
        exportSession.outputFileType = .mov

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        exportSession.outputURL = outputURL

        do {
            try await _export(exportSession)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    private func _export(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let message = session.error?.localizedDescription ?? "Export did not complete."
                    continuation.resume(throwing: ConcatenateError.exportFailed(message))
                default:
                    continuation.resume(throwing: ConcatenateError.exportFailed("Unexpected export status: \(session.status.rawValue)"))
                }
            }
        }
    }
}
