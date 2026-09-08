//
//  Localization.swift
//  AirChat
//
//  AirChat is bilingual (RO + EN). The web layer keeps its table in app.js; the
//  native chrome uses this. English is the inline fallback so a missing key can never
//  render an empty label, and Romanian overrides it when the device language is ro.
//  Deliberately not .strings/lproj files: one less thing for a hand-generated
//  pbxproj (and a free provisioning build) to get wrong.
//

import Foundation

enum Localization {

    static var language: String {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ro") ? "ro" : "en"
    }

    static func t(_ key: String, _ english: String) -> String {
        guard language == "ro", let value = romanian[key] else { return english }
        return value
    }

    static func f(_ key: String, _ english: String, _ args: [CVarArg]) -> String {
        String(format: t(key, english), arguments: args)
    }

    private static let romanian: [String: String] = [
        // AppRuntime status
        "SERVER_STOPPED": "Server oprit",
        "NET_HOTSPOT": "Hotspot personal",
        "NET_LAN": "Wi-Fi / LAN",
        "SERVER_LIVE": "Activ pe %@:%d · %@ · %d clienți",

        // Mesh peer prompt (mirrors the Android AlertDialog)
        "MESH_FOUND_TITLE": "AirChat detectat",
        "MESH_FOUND_BODY": "Găsit node mesh „%@”. Vrei să te conectezi și să transmiți mesajele mai departe?",
        "CONNECT": "Conectare",
        "IGNORE": "Nu acum",

        // Photo picker sheet
        "PICK_PHOTO": "Alege o fotografie",
        "TAKE_PHOTO": "Fă o poză",
        "CANCEL": "Anulare",

        // Microphone
        "MIC_BUSY": "Se înregistrează deja ceva.",
        "MIC_DENIED": "Accesul la microfon a fost refuzat.",
        "MIC_START_FAILED": "Microfonul nu a pornit."
    ]
}
