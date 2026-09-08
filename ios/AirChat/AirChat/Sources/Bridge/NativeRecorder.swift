//
//  NativeRecorder.swift
//  AirChat
//
//  Voice notes. The Android app lets the WebView call getUserMedia() and
//  MediaRecorder() and grants RESOURCE_AUDIO_CAPTURE from WebChromeClient. On iOS a
//  WKWebView only exposes getUserMedia in a secure context, and an http://192.168.x.x
//  origin is not one — so for the host phone we record natively and hand the bytes to
//  JavaScript. Recorded as AAC-in-MP4 because that is the one container every target
//  decodes (Safari, Chrome, Android, Windows): Android's webm/opus cannot even be
//  played back by iOS browsers.
//

import AVFoundation
import Foundation

final class NativeRecorder: NSObject, AVAudioRecorderDelegate {

    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notPermitted
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return Localization.t("MIC_BUSY", "A recording is already running.")
            case .notPermitted: return Localization.t("MIC_DENIED", "Microphone access was denied.")
            case .failed(let message): return message
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var startedAt: Date?
    private var ownsSession = false

    private(set) var isRecording = false

    var duration: TimeInterval {
        guard let startedAt = startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var averagePower: Float {
        guard let recorder = recorder else { return -160 }
        return recorder.averagePower(forChannel: 0)
    }

    // MARK: - Permission

    /// Deliberately uses AVAudioSession rather than the iOS 17 `AVAudioApplication`
    /// APIs: `requestRecordPermission(_:)` is marked deprecated but still functional,
    /// and the whole recorder already lives on AVAudioSession categories. Swapping one
    /// API for the other would mean touching both call sites anyway.
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static var permissionStatus: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    // MARK: - Recording

    func start() throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        // AVAudioRecorder.record() only returns false when the mic is not granted —
        // it never raises the prompt itself, so the caller must have asked already.
        guard Self.permissionStatus else { throw RecorderError.notPermitted }

        let session = AVAudioSession.sharedInstance()
        do {
            // Hand the keep-alive session over to the mic, then give it back on stop.
            KeepAlive.shared.suspendForRecording()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: [])
            ownsSession = true
        } catch {
            KeepAlive.shared.resumeAfterRecording()
            throw RecorderError.failed(error.localizedDescription)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("airchat-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 56_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: destination, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw RecorderError.failed(Localization.t("MIC_START_FAILED", "The microphone refused to start."))
            }
            self.recorder = recorder
            self.url = destination
            self.startedAt = Date()
            self.isRecording = true
        } catch let error as RecorderError {
            teardownSession()
            throw error
        } catch {
            teardownSession()
            throw RecorderError.failed(error.localizedDescription)
        }
    }

    /// Stops and returns the recorded file as a `data:audio/mp4;base64,…` URL string,
    /// i.e. the same shape the browser MediaRecorder path produces, so app.js can send
    /// it unchanged. Returns nil for taps shorter than 400 ms (same guard as Android).
    func stop() -> String? {
        defer { cleanup() }
        guard isRecording, let recorder = recorder, let url = url else { return nil }
        let seconds = duration
        recorder.stop()
        if seconds < 0.4 { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }
        // ~56 kbit/s ⇒ a 60 s note is ≈400 KB of base64; fine for a LAN message.
        return "data:audio/mp4;base64," + data.base64EncodedString()
    }

    func cancel() {
        recorder?.stop()
        cleanup()
    }

    private func cleanup() {
        isRecording = false
        startedAt = nil
        if let url = url { try? FileManager.default.removeItem(at: url) }
        url = nil
        recorder = nil
        teardownSession()
        KeepAlive.shared.resumeAfterRecording()
    }

    private func teardownSession() {
        guard ownsSession else { return }
        ownsSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error { NSLog("AirChat: recorder error \(error.localizedDescription)") }
    }
}
