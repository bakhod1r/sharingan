import Foundation
@preconcurrency import AVFoundation

/// Thread-safe holder for the frame stream continuation.
///
/// The capture delegate fires on a background queue while the continuation is
/// installed/torn down from the main actor, so access is guarded by a lock.
/// `AsyncStream.Continuation.yield/finish` are themselves thread-safe.
private final class FrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<CVImageBuffer>.Continuation?

    func set(_ c: AsyncStream<CVImageBuffer>.Continuation?) {
        lock.lock(); continuation = c; lock.unlock()
    }
    func yield(_ buffer: CVImageBuffer) {
        lock.lock(); let c = continuation; lock.unlock()
        c?.yield(buffer)
    }
    func finish() {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.finish()
    }
}

@MainActor
public final class CameraService: NSObject, ObservableObject {
    public static let shared = CameraService()

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var permissionStatus: AVAuthorizationStatus

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "blink.camera.session")
    private let sink = FrameSink()
    private var framePipe: AsyncStream<CVImageBuffer>?
    private var configured = false

    public override init() {
        self.permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
    }

    // MARK: - Permission

    public func requestPermission() async -> Bool {
        guard permissionStatus == .notDetermined else {
            return permissionStatus == .authorized
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            self.permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
            self.isAuthorized = granted
        }
        return granted
    }

    // MARK: - Session control

    public func start() {
        guard permissionStatus == .authorized else { return }
        guard !isRunning else { return }
        if !configured { configureSessionIfNeeded(); configured = true }
        let session = self.session
        sessionQueue.async {
            session.startRunning()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = session.isRunning
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        let session = self.session
        sessionQueue.async {
            session.stopRunning()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.sink.finish()
                self.framePipe = nil
            }
        }
    }

    // MARK: - Frame stream

    public func frames() -> AsyncStream<CVImageBuffer> {
        if let pipe = framePipe { return pipe }
        let (pipe, cont) = AsyncStream<CVImageBuffer>.makeStream()
        self.framePipe = pipe
        self.sink.set(cont)
        return pipe
    }

    // MARK: - Configure

    private func configureSessionIfNeeded() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video, position: .front) ??
            AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        session.commitConfiguration()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Fires on `sessionQueue`, not the main actor — must stay nonisolated.
    public nonisolated func captureOutput(_ output: AVCaptureOutput,
                                          didOutput sampleBuffer: CMSampleBuffer,
                                          from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        sink.yield(buffer)
    }
}