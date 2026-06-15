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
            let imageData = frame.thumbnail?.jpegData(compressionQuality: 0.85) ?? Data()
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
