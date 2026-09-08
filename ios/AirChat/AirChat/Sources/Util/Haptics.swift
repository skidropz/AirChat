//
//  Haptics.swift
//  AirChat
//
//  Android: Vibrator.vibrate(VibrationEffect.createOneShot(500, DEFAULT_AMPLITUDE)).
//  iOS has no vibration API for apps, so the BUZZ is expressed with the haptic
//  engines (CoreHaptics on iPhones with Taptic Engine, falling back to
//  UIFeedbackGenerator, plus the system alert sound so silent-switch-off users still
//  feel/hear something).
//

import AudioToolbox
import CoreHaptics
import UIKit

enum Haptics {

    private static var engine: CHHapticEngine?

    static func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        guard engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.resetHandler = { try? engine.start() }
            try engine.start()
            self.engine = engine
        } catch {
            NSLog("AirChat: haptics unavailable \(error.localizedDescription)")
        }
    }

    /// The BUZZ: a strong, physical double hit — meant to be noticed through a pocket.
    static func buzz() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = engine else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        let sharpness = CHHapticEventParameter(parameterID: .hapticIntensitySharpness, value: 0.9)
        let events = [
            CHHapticEvent(eventType: .hapticContinuous, parameters: [sharpness], relativeTime: 0, duration: 0.18),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [sharpness], relativeTime: 0.30, duration: 0.24)
        ]
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            legacy(.heavy)
        }
        AudioServicesPlaySystemSound(1005)   // the old "new mail" trill, loud-ish, respects mute
    }

    /// Short tick used when a message is sent.
    static func tap() {
        legacy(.light)
    }

    static func success() {
        legacy(.success)
    }

    private enum Legacy { case light, heavy, success }

    private static func legacy(_ kind: Legacy) {
        switch kind {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: 1.0)
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }
}
