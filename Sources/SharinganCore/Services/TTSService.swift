import Foundation
import AVFoundation

@MainActor
public final class TTSService {
    public static let shared = TTSService()

    private let synth = AVSpeechSynthesizer()

    public init() {}

    public func speak(_ text: String, lang: String = "en-US",
               rate: Float = 0.5, pitch: Float = 1.0) {
        // Interrupt any in-progress speech instead of dropping the new line, so
        // the voice always matches the CURRENT eye-exercise step — otherwise a
        // still-speaking cue would swallow the next one and the audio would drift
        // out of sync with the eyes.
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
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