//
//  BackgroundKeepAlive.swift
//  AirChat
//
//  iOS freezes a backgrounded app's sockets, so the server would stop serving the moment the
//  screen locks. The well-known workaround is a silent, looping audio session: it keeps the
//  process (and the NWListener) alive while locked. The Server panel tells the user honestly
//  what this toggle costs, because this trick is exactly what would not survive App Store
//  review — which is why AirChat is sideloaded, not distributed.
//

import Foundation
import AVFoundation

final class BackgroundKeepAlive {

    private var player: AVAudioPlayer?
    private(set) var isEnabled = false

    func start() {
        stop()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        guard let player = try? AVAudioPlayer(data: Self.silentWAVData()) else { return }
        player.numberOfLoops = -1
        player.volume = 0.0
        player.prepareToPlay()
        player.play()
        self.player = player
        isEnabled = true
    }

    func stop() {
        player?.stop()
        player = nil
        isEnabled = false
    }

    /// A tiny (1 second) silent 44.1kHz mono 16-bit PCM WAV, looped with volume 0.
    private static func silentWAVData() -> Data {
        func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: Array($0)) }
        }

        let sampleRate: UInt32 = 44100
        let seconds: UInt32 = 1
        let numSamples = sampleRate * seconds
        let byteCount = numSamples * 2

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendLE(36 + byteCount, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLE(UInt32(16), to: &data)          // fmt chunk size
        appendLE(UInt16(1), to: &data)           // PCM
        appendLE(UInt16(1), to: &data)           // mono
        appendLE(sampleRate, to: &data)
        appendLE(sampleRate * 2, to: &data)      // byte rate
        appendLE(UInt16(2), to: &data)           // block align
        appendLE(UInt16(16), to: &data)          // bits per sample
        data.append(contentsOf: Array("data".utf8))
        appendLE(byteCount, to: &data)
        data.append(Data(count: Int(byteCount))) // zeros = silence
        return data
    }
}
