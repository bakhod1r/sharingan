import Foundation
import AppKit

/// Selector surface of the private CBBlueLightClient (CoreBrightness.framework).
/// The class is resolved at runtime; this protocol only exists so Swift can
/// message the instance with a typed ABI (the unsafeBitCast trick below).
@objc private protocol CBBlueLightClientProtocol {
    @discardableResult func setEnabled(_ enabled: Bool) -> Bool
    @discardableResult func setStrength(_ strength: Float, commit: Bool) -> Bool
    @discardableResult func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
    /// `- (BOOL)getBlueLightStatus:(Status *)status` — Status is a private
    /// struct; we only peek at byte 1 (`enabled`). Passed as a raw pointer so
    /// a future layout change can't corrupt our memory (we over-allocate).
    @discardableResult func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
}

/// NightShiftService — break vaqtida ekranni Night Shift bilan "isitadi"
/// (ko'zni dam oldirish uchun iliq ranglar), break tugagach asl holatga
/// qaytaradi.
///
/// macOS'da Night Shift uchun public API yo'q; private CoreBrightness
/// framework'idagi CBBlueLightClient runtime orqali yuklanadi. Fail-soft:
/// class topilmasa (kelajak macOS'da olib tashlansa) hamma amal no-op.
@MainActor
public final class NightShiftService {
    public static let shared = NightShiftService()

    /// False when CBBlueLightClient can't be loaded — every op no-ops then.
    public private(set) var isAvailable: Bool = false

    private var client: CBBlueLightClientProtocol?

    // Remembered pre-break state. `priorEnabled == nil` means the enabled
    // state couldn't be read — then we treat the warmth as "we turned it on"
    // and disable on restore.
    private var active: Bool = false
    private var priorStrength: Float?
    private var priorEnabled: Bool?

    public init() {
        // Resolve the private framework lazily and fail soft on any miss.
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
               RTLD_LAZY)
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            return
        }
        let instance = cls.init()
        // CBBlueLightClient does not declare the protocol; the existential is
        // just the object pointer, so the bitcast is safe as long as every
        // call is guarded by responds(to:).
        client = unsafeBitCast(instance, to: CBBlueLightClientProtocol.self)
        isAvailable = responds("setEnabled:") && responds("setStrength:commit:")

        // Night Shift is system-global state: if the app dies mid-break the
        // screen would stay warm. Restore on terminate as a fail-safe
        // (mirrors BrightnessService's gamma restore).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                NightShiftService.shared.endBreakWarmth()
            }
        }
    }

    // MARK: - Break lifecycle

    /// Remembers the current Night Shift state, then enables warmth at
    /// `strength` (0…1). Double-begin keeps the first remembered state.
    public func beginBreakWarmth(strength: Float) {
        guard isAvailable, let client else { return }
        guard !active else { return }   // don't clobber the remembered original
        active = true

        // Remember what the user had before the break.
        priorStrength = readStrength()
        priorEnabled = readEnabled()

        let target = max(0.0, min(1.0, strength))
        if responds("setEnabled:") { client.setEnabled(true) }
        if responds("setStrength:commit:") { client.setStrength(target, commit: true) }
    }

    /// Restores the remembered state: strength always, and Night Shift is
    /// switched back off unless it was already on before the break.
    /// Idempotent — end without begin (or a second end) is a no-op.
    public func endBreakWarmth() {
        guard active else { return }
        active = false
        defer { priorStrength = nil; priorEnabled = nil }
        guard isAvailable, let client else { return }

        if let old = priorStrength, responds("setStrength:commit:") {
            client.setStrength(old, commit: true)
        }
        // priorEnabled == true → the user already ran Night Shift, leave it on.
        // false or unreadable (nil) → we turned it on, so turn it back off.
        if priorEnabled != true, responds("setEnabled:") {
            client.setEnabled(false)
        }
    }

    // MARK: - State readback (best effort)

    private func readStrength() -> Float? {
        guard let client, responds("getStrength:") else { return nil }
        var value: Float = 0
        guard client.getStrength(&value) else { return nil }
        return value
    }

    private func readEnabled() -> Bool? {
        guard let client, responds("getBlueLightStatus:") else { return nil }
        // Private Status struct: byte 0 = active, byte 1 = enabled. Allocate
        // far more than any known layout (~40 bytes) so growth stays safe.
        let size = 128
        let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buf.deallocate() }
        buf.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        guard client.getBlueLightStatus(buf) else { return nil }
        return buf.load(fromByteOffset: 1, as: UInt8.self) != 0
    }

    private func responds(_ selector: String) -> Bool {
        (client as AnyObject?)?.responds(to: NSSelectorFromString(selector)) ?? false
    }
}
