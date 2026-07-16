import AVFoundation

protocol VideoReencoding: Sendable {
    func reencode(sourceURL: URL) async throws -> URL
}

/// Re-encodes a video to the fixed portrait resolution/frame rate `segment_serves` is validated
/// against (matching `CameraService`'s Pro 2D live-capture lock), so a Photos-library import
/// arrives at the backend in the same shape as a live-recorded clip.
struct VideoReencoder: VideoReencoding {
    static let targetSize = CGSize(width: 720, height: 1280)
    static let targetFPS: Int32 = 30

    enum ReencodeError: LocalizedError {
        case noVideoTrack
        case exportSessionCreationFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "The selected video has no video track."
            case .exportSessionCreationFailed:
                return "Could not create a video export session."
            case .exportFailed(let message):
                return "Could not process video: \(message)"
            }
        }
    }

    func reencode(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReencodeError.noVideoTrack
        }

        let composition = try await _makeComposition(asset: asset, track: track)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ReencodeError.exportSessionCreationFailed
        }
        exportSession.videoComposition = composition
        exportSession.outputFileType = .mov

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        exportSession.outputURL = outputURL

        do {
            try await _export(exportSession)
        } catch {
            // AVAssetExportSession can write a partial file at outputURL before failing/
            // cancelling — clean it up so a failed re-encode doesn't leak a temp file.
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    // MARK: - Private

    private func _makeComposition(asset: AVURLAsset, track: AVAssetTrack) async throws -> AVMutableVideoComposition {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)

        // The track's raw pixel buffer is in sensor orientation; preferredTransform rotates it
        // into display orientation (e.g. portrait for a live-recorded Pro 2D clip). Apply that
        // rotation first, then scale+center the now-correctly-oriented content into targetSize
        // (aspect-fit, so the full frame is preserved — no cropping that could cut off part of
        // the serve motion).
        let rotatedSize = naturalSize.applying(preferredTransform)
        let sourceSize = CGSize(width: abs(rotatedSize.width), height: abs(rotatedSize.height))

        let scale = min(Self.targetSize.width / sourceSize.width, Self.targetSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let tx = (Self.targetSize.width - scaledSize.width) / 2
        let ty = (Self.targetSize.height - scaledSize.height) / 2

        let finalTransform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(finalTransform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = Self.targetSize
        composition.frameDuration = CMTime(value: 1, timescale: Self.targetFPS)
        composition.instructions = [instruction]
        return composition
    }

    private func _export(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let message = session.error?.localizedDescription ?? "Export did not complete."
                    continuation.resume(throwing: ReencodeError.exportFailed(message))
                default:
                    continuation.resume(throwing: ReencodeError.exportFailed("Unexpected export status: \(session.status.rawValue)"))
                }
            }
        }
    }
}
