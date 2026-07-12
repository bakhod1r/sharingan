import Foundation
import AVFoundation

@MainActor
public final class BreakAmbienceService: ObservableObject {
    public static let shared = BreakAmbienceService()

    public enum Ambience: String, CaseIterable, Sendable {
        case silent
        case whiteNoise
        case rain
        case forest
        case lofi

        public var label: String {
            switch self {
            case .silent:     return "Silent"
            case .whiteNoise:  return "White noise"
            case .rain:        return "Rain"
            case .forest:      return "Forest"
            case .lofi:        return "Lo-fi pad"
            }
        }

        public var systemImage: String {
            switch self {
            case .silent:     return "speaker.slash.fill"
            case .whiteNoise: return "dot.radiowaves.left.and.right"
            case .rain:        return "cloud.rain.fill"
            case .forest:     return "tree.fill"
            case .lofi:        return "music.note"
            }
        }
    }

    @Published public var selected: Ambience = .rain
    @Published public private(set) var isPlaying: Bool = false

    private var player: AVAudioPlayer?

    public init() {}

    public func start() {
        guard selected != .silent else { stop(); return }
        guard let url = bundledURL(for: selected) else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            stop()
            return
        }
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        player?.play()
        isPlaying = true
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    public func toggle() {
        isPlaying ? stop() : start()
    }

    public func preview(_ ambience: Ambience) {
        selected = ambience
        stop()
        start()
    }

    private func bundledURL(for ambience: Ambience) -> URL? {
        let name = "ambience_\(ambience.rawValue)"
        // Sounds ship with the SharinganCore target; resolve from the signable bundle.
        return Bundle.sharinganCoreResources.url(forResource: name, withExtension: "caf",
                                             subdirectory: "Sounds")
            ?? Bundle.sharinganCoreResources.url(forResource: name, withExtension: "caf")
    }
}