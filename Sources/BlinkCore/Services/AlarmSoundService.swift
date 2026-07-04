import Foundation
import AVFoundation

@MainActor
public final class AlarmSoundService {
    public static let shared = AlarmSoundService()

    public enum Sound: String, CaseIterable, Sendable {
        case glass
        case chime
        case softBell
        case silent

        public var label: String {
            switch self {
            case .glass:    return "Glass"
            case .chime:    return "Chime"
            case .softBell: return "Soft bell"
            case .silent:   return "Ovozsiz"
            }
        }
    }

    public var selected: Sound = .glass
    private var player: AVAudioPlayer?

    public init() {}

    public func playSelected() {
        guard selected != .silent else { return }
        play(selected)
    }

    public func play(_ sound: Sound) {
        guard sound != .silent else { return }
        guard let url = bundledURL(for: sound) else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Could not decode — skip silently.
        }
    }

    public func stop() {
        player?.stop()
        player = nil
    }

    private func bundledURL(for sound: Sound) -> URL? {
        let name = "alarm_\(sound.rawValue)"
        if let url = Bundle.main.url(forResource: name, withExtension: "caf") {
            return url
        }
        return Bundle(for: AlarmSoundService.self)
            .url(forResource: name, withExtension: "caf")
    }
}