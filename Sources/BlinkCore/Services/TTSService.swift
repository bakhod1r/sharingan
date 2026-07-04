import Foundation
import AVFoundation

@MainActor
public final class TTSService {
    public static let shared = TTSService()

    private let synth = AVSpeechSynthesizer()

    public init() {}

    public func speak(_ text: String, lang: String = "uz-UZ",
               rate: Float = 0.5, pitch: Float = 1.0) {
        guard synth.isSpeaking == false else { return }
        let utter = AVSpeechUtterance(string: text)
        utter.voice = AVSpeechSynthesisVoice(language: lang)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        let lo = AVSpeechUtteranceMinimumSpeechRate
        let hi = AVSpeechUtteranceMaximumSpeechRate
        utter.rate = lo + (hi - lo) * max(0, min(1, rate))
        utter.pitchMultiplier = pitch
        utter.preUtteranceDelay = 0.1
        utter.postUtteranceDelay = 0.1
        synth.speak(utter)
    }

    public func stop() { synth.stopSpeaking(at: .immediate) }
}