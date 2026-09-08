//
//  KeepAlive.swift
//  AirChat
//
//  THE most important iOS-specific adjustment in this port.
//
//  Android keeps a foreground service alive trivially. iOS suspends an app a few
//  seconds after it leaves the foreground, which would kill the HTTP/WebSocket
//  listener and freeze every connected friend. There is no "background server"
//  background mode in iOS.
//
//  The workaround — and the one used by every self-hosted-server app on iOS — is to
//  hold an active audio session with a silent, infinitely looping player. The OS
//  treats the app as "playing audio", keeps it running, and the sockets stay open.
//  It also needs `UIBackgroundModes: [audio]` in Info.plist so playback continues
//  while the screen is locked.
//
//  Notes / limits, all of which the UI surfaces honestly:
//   * Low-power mode can still throttle background work.
//   * If the user force-quits the app, nothing runs (true of every app).
//   * This trick is against App Store rules for "background audio" misuse; we are
//     distributing via sideload/TestFlight-adjacent channels where review does not
//     apply, so we can use it. A TestFlight build with it is fine too — TestFlight
//     builds are not subject to review, only the final App Store submission is.
//

import AVFoundation
import Foundation
import UIKit

final class KeepAlive {

    static let shared = KeepAlive()

    private var player: AVAudioPlayer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private(set) var isActive = false

    struct KeepAliveError: Error { let message: String }

    /// Silent 0.5 s 8 kHz mono WAV, generated at runtime so the app bundle stays clean.
    private func makeSilentWAV() -> Data {
        let sampleRate = 8000
        let samples = 4000                       // 0.5 s
        let bytesPerSample = 2
        let dataSize = samples * bytesPerSample
        var d = Data()
        func ascii(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        // iOS is little-endian; append low bytes first, no swapping helpers needed.
        func u32(_ v: Int) {
            let x = UInt32(truncatingIfNeeded: v)
            d.append(UInt8(truncatingIfNeeded: x))
            d.append(UInt8(truncatingIfNeeded: x >> 8))
            d.append(UInt8(truncatingIfNeeded: x >> 16))
            d.append(UInt8(truncatingIfNeeded: x >> 24))
        }
        func u16(_ v: Int) {
            let x = UInt16(truncatingIfNeeded: v)
            d.append(UInt8(truncatingIfNeeded: x))
            d.append(UInt8(truncatingIfNeeded: x >> 8))
        }

        ascii("RIFF"); u32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * bytesPerSample)
        u16(bytesPerSample); u16(bytesPerSample * 8)
        ascii("data"); u32(dataSize)
        d.append(Data(count: dataSize))
        return d
    }

    /// Start pretending to play audio so iOS keeps the process (and its sockets) alive.
    @discardableResult
    func enable() -> Bool {
        if isActive { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            NSLog("AirChat: could not activate audio session — \(error.localizedDescription)")
            return false
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("airchat-silent.wav")
        do {
            try makeSilentWAV().write(to: url, options: .atomic)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            self.player = player
            isActive = true
            NSLog("AirChat: keep-alive audio session active")
            return true
        } catch {
            NSLog("AirChat: keep-alive player failed — \(error.localizedDescription)")
            return false
        }
    }

    func disable() {
        guard isActive else { return }
        player?.stop()
        player = nil
        isActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            NSLog("AirChat: deactivating audio session: \(error.localizedDescription)")
        }
    }

    /// Hand the (single, shared) audio session over to the microphone, then take it back.
    func suspendForRecording() {
        player?.pause()
    }

    func resumeAfterRecording() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        player?.play()
    }

    // MARK: - Short background grace period (belt & braces on top of the audio trick)

    func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AirChatServer") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
