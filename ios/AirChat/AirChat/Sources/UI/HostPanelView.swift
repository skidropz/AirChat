//
//  HostPanelView.swift
//  AirChat
//
//  The control-centre sheet that has no Android equivalent: on Android the hosting
//  story is a couple of lines in a TextView because tethering + background services
//  are assumed. On iOS every one of those is a decision the user has to make, so the
//  panel exposes them: hotspot state, local-network permission, port, background
//  keep-alive, mesh peers, discovered rooms, room rotation, and the sideload guide.
//

import SwiftUI
import UIKit

struct HostPanelView: View {

    @ObservedObject var model: RuntimeModel
    @Environment(\.dismiss) private var dismiss

    @State private var revealKey = false
    @State private var showQR = false
    @State private var showShare = false
    @State private var banner: String?

    var body: some View {
        NavigationView {
            Form {
                statusSection
                joinSection
                networkSection
                backgroundSection
                meshSection
                nearbyRoomsSection
                roomSection
                installSection
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showQR) { QRSheet(address: model.browserAddress) }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: ["Join my offline AirChat room — no internet needed:\n\(model.browserAddress)"])
            }
            .overlay(alignment: .top) {
                if let banner = banner {
                    Text(banner)
                        .font(.footnote.weight(.semibold))
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            Toggle("Hosting this room", isOn: Binding(
                get: { model.isHosting },
                set: { AppRuntime.shared.isHostingEnabled = $0 }
            ))

            infoRow("Status", model.statusLine)
            infoRow("Uptime", model.uptime)
            infoRow("Clients", "\(model.clientCount)")

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("The HTTP + WebSocket listener is what turns this iPhone into the server. Everything else — browsers, laptops, Android phones — connects to it.")
        }
    }

    private var joinSection: some View {
        Section {
            Button {
                copy(model.browserAddress, "Link copied")
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("http://\(model.hostIP):\(model.port)")
                            .font(.system(.body, design: .monospaced))
                        Text("code \(model.shortCode) · key travels in #fragment only")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "doc.on.doc")
                }
            }
            .foregroundStyle(.primary)

            Button {
                showQR = true
            } label: {
                Label("Show QR code", systemImage: "qrcode")
            }

            Button {
                showShare = true
            } label: {
                Label("Share invite", systemImage: "square.and.arrow.up")
            }

            HStack {
                Text("Short code")
                Spacer()
                Text(model.shortCode)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.tint)
            }
        } header: {
            Text("How friends join")
        } footer: {
            Text("On a laptop or phone browser, type the address (or the code alone if the host part is already there). Scanning the QR opens Safari on phones; the key is delivered by the redirect, never stored.")
        }
    }

    private var networkSection: some View {
        Section {
            Label {
                Text(model.hotspotUp ? "Personal Hotspot is on" : "Personal Hotspot is off")
            } icon: {
                Image(systemName: model.hotspotUp ? "personalhotspot" : "personalhotspot")
                    .foregroundStyle(model.hotspotUp ? Color.green : Color.orange)
            }

            if !model.hotspotUp {
                Button {
                    AppRuntime.shared.openHotspotSettings()
                } label: {
                    Label("Open Settings › Personal Hotspot", systemImage: "arrow.up.forward.app")
                }
            }

            ForEach(model.interfaces, id: \.self) { address in
                HStack {
                    Text(address.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(address.ip) · \(kindLabel(address.kind))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: Binding(get: { Int(model.port) },
                                   set: { AppRuntime.shared.port = UInt16(max(1, $0)) }),
                    in: 1...65535, step: 1) {
                HStack {
                    Text("Port")
                    Spacer()
                    Text("\(model.port)").monospacedDigit()
                }
            }
        } header: {
            Text("Network")
        } footer: {
            Text(model.onlyCellular
                 ? "Only a cellular address is available — nobody can reach this phone. Turn on Personal Hotspot, or join the same Wi-Fi as your friends."
                 : "iOS never lets an app switch the hotspot on by itself, so that one tap has to happen in Settings. Port 80 usually fails on non-jailbroken iOS; 8080 matches the Android app. Everyone must be on the network this phone is serving.")
        }
    }

    private var backgroundSection: some View {
        Section {
            Toggle("Keep serving when locked", isOn: Binding(
                get: { model.keepAliveEnabled },
                set: { AppRuntime.shared.keepAliveEnabled = $0 }
            ))

            Toggle("Keep screen awake", isOn: Binding(
                get: { model.screenAwakeEnabled },
                set: { AppRuntime.shared.screenAwakeEnabled = $0 }
            ))
        } header: {
            Text("Background")
        } footer: {
            Text("iOS suspends a backgrounded app within seconds, which would kill the server and freeze everyone's chat. While this is on, AirChat holds a silent audio session so the sockets stay open with the screen off. Low Power Mode can still interfere; force-quitting always does.")
        }
    }

    private var meshSection: some View {
        Section {
            Toggle("Mesh networking", isOn: Binding(
                get: { model.meshEnabled },
                set: { AppRuntime.shared.isMeshEnabled = $0 }
            ))

            if model.meshPeers.isEmpty {
                Text("No peers connected")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(model.meshPeers, id: \.id) { peer in
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                        Text(peer.displayName)
                        Spacer()
                        Button("Disconnect") {
                            AppRuntime.shared.disconnectMeshPeer(peer)
                        }
                        .font(.caption)
                    }
                }
            }

            ForEach(model.discoveredPeers, id: \.id) { peer in
                HStack {
                    Image(systemName: "person.2.badge.plus")
                    Text(peer.displayName)
                    Spacer()
                    Button("Connect") {
                        AppRuntime.shared.connectMeshPeer(peer)
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text("Mesh (MultipeerConnectivity)")
        } footer: {
            Text("iPhone-to-iPhone relaying over Bluetooth LE + peer Wi-Fi, encrypted with the same AES-256-GCM key as Android's Nearby Connections. A message from phone A can hop through B to reach C, extending the range.")
        }
    }

    private var nearbyRoomsSection: some View {
        Section {
            if model.nearbyRooms.isEmpty {
                Text("Looking for AirChat servers nearby…")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(model.nearbyRooms, id: \.id) { room in
                    Button {
                        join(room)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name)
                                Text(room.addressLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("Rooms around you")
        } footer: {
            Text("Discovered over Bonjour (_airchat-http._tcp). Joining one turns this phone into a client of that host's server instead — no code typing needed.")
        }
    }

    private var roomSection: some View {
        Section {
            Button {
                revealKey.toggle()
            } label: {
                HStack {
                    Text("Room key")
                    Spacer()
                    Text(revealKey ? model.roomKey : String(repeating: "•", count: 12))
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(revealKey ? 2 : 1)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Button {
                copy(model.roomKey, "Room key copied")
            } label: {
                Label("Copy key", systemImage: "key")
            }

            Button(role: .destructive) {
                AppRuntime.shared.rotateRoom()
                banner = "New room created. Everyone must rejoin."
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { banner = nil }
            } label: {
                Label("Start a new room", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Room")
        } footer: {
            Text("One key per room. Anyone with the key reads the traffic — which is why it only travels inside the link's #fragment, a part of the URL that is never sent to the server.")
        }
    }

    private var installSection: some View {
        Section {
            Button {
                copy(model.guideAddress, "Guide link copied")
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Install guide for friends")
                        Text(model.guideAddress)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "doc.on.doc")
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Distribution")
        } footer: {
            Text("iPhones cannot install a hosted .ipa the way Android installs a hosted .apk, because every build must be signed with the *receiver's own* Apple ID. This page explains the free-Apple-ID route (SideStore / AltStore / Sideloadly) in three steps.")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Helpers

    private func kindLabel(_ kind: InterfaceKind) -> String {
        switch kind {
        case .hotspot: return "hotspot"
        case .wifi: return "Wi-Fi"
        case .cellular: return "cellular"
        case .other: return "other"
        }
    }

    private func copy(_ string: String, _ feedback: String) {
        UIPasteboard.general.string = string
        Haptics.success()
        banner = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { banner = nil }
    }

    private func join(_ room: DiscoveredRoom) {
        guard let url = room.joinURL else { return }
        AppRuntime.shared.joinRoom(url: url)
        dismiss()
    }
}

// MARK: - QR sheet

struct QRSheet: View {
    let address: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Scan to join")
                .font(.title2.bold())
            if let image = QRCode.image(from: address, moduleSize: 10) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 320)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                ContentUnavailableCompat(message: "QR unavailable")
            }
            Text(address)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

/// ContentUnavailableView is iOS 17+; this keeps the deployment target at 15.
private struct ContentUnavailableCompat: View {
    let message: String
    var body: some View {
        Text(message).font(.footnote).foregroundStyle(.secondary)
    }
}

// MARK: - Share

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
