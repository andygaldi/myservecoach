import AVFoundation

protocol SpokenFeedbackServicing: Sendable {
    func speak(_ text: String)
}

final class SpokenFeedbackService: SpokenFeedbackServicing {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.speak(AVSpeechUtterance(string: text))
    }
}
