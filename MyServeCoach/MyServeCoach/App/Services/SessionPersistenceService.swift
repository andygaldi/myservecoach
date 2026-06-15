import CoreMedia
import Foundation
import SwiftData
import UIKit

struct SessionPersistenceService {
    func save(
        confirmedFrames: [PhaseFrame],
        referenceLibrary: ReferenceFrameLibrary,
        inputType: String,
        videoURL: URL?,
        into context: ModelContext
    ) {
        let session = ServeSession(inputType: inputType, videoURL: videoURL)
        for frame in confirmedFrames {
            let imageData = frame.thumbnail?.thumbnailData() ?? Data()
            let timestamp = CMTimeGetSeconds(frame.timestamp)
            let refURLs = referenceLibrary.referenceFrames[frame.phase.backendKey]?.map(\.imageURL.absoluteString) ?? []
            let record = PhaseRecord(
                phaseKey: frame.phase.backendKey,
                label: frame.phase.rawValue,
                frameImageData: imageData,
                frameTimestamp: timestamp,
                referenceFrameURLs: refURLs
            )
            record.session = session
            session.phases.append(record)
        }
        context.insert(session)
    }
}

private extension UIImage {
    // Scales down to fit within 512×512 (never upscales) then JPEG-encodes.
    func thumbnailData() -> Data? {
        let maxDimension: CGFloat = 512
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        if scale >= 1 { return jpegData(compressionQuality: 0.85) }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
