import Foundation
import SwiftData

@Model
final class PhaseRecord {
    var id: UUID = UUID()
    var phaseKey: String = ""
    var label: String = ""
    var frameImageData: Data = Data()
    var frameTimestamp: Double = 0
    var referenceFrameURLs: [String] = []
    var session: ServeSession?

    init(phaseKey: String, label: String, frameImageData: Data, frameTimestamp: Double, referenceFrameURLs: [String]) {
        self.phaseKey = phaseKey
        self.label = label
        self.frameImageData = frameImageData
        self.frameTimestamp = frameTimestamp
        self.referenceFrameURLs = referenceFrameURLs
    }
}
