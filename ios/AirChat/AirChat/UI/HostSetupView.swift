import SwiftUI
import UIKit

/// Host landing screen: shows the LAN address, short code, QR code and mesh
/// status so others can join through their browser. "Enter chat" opens the
/// native conversation.
struct HostSetupView: View {
    @ObservedObject var store: ChatStore
    let onEnterChat: () -> Void

    @State private var showShareSheet = false
    @State private var showLargeQR = false

    private var joinURL: String {
        "http://\(store.localIp):\(store.port)/#\(store.roomKey)"
    }
    private var shortURL: String {
        "http://\(store.localIp):\(store.port)/\(store.shortCode)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.router.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text(NSLocalizedString("host_ready", comment: ""))
                        .font(.title2.bold())
                }
                .padding(.top, 20)

                infoCard {
                    VStack(spacing: 10) {
                        Text(NSLocalizedString("laptop_code", comment: ""))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(store.shortCode)
                            .font(.system(size: 40, weight: .heavy, design: .monospaced))
                            .tracking(4)
                        Text(String(format: NSLocalizedString("type_in_browser", comment: ""), shortURL))
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }

                infoCard {
                    VStack(spacing: 12) {
                        QRCodeView(text: joinURL, scale: 8)
                            .frame(width: 200, height: 200)
                            .background(.white)
                            .cornerRadius(12)
                        Text(NSLocalizedString("scan_qr_hint", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                infoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: NSLocalizedString("address_label", comment: ""), value: "\(store.localIp):\(store.port)")
                        Divider()
                        row(label: NSLocalizedString("mesh_label", comment: ""),
                            value: store.meshPeers.isEmpty
                                ? NSLocalizedString("mesh_searching", comment: "")
                                : "\(store.meshPeers.count) \(NSLocalizedString("mesh_connected", comment: ""))")
                        if !store.meshPeers.isEmpty {
                            Divider()
                            Text(store.meshPeers.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = joinURL
                    } label: {
                        Label(NSLocalizedString("copy_link", comment: ""), systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity).padding()
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button(action: onEnterChat) {
                        Text(NSLocalizedString("enter_chat", comment: ""))
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Text(NSLocalizedString("ios_host_caveat", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal)
        }
        .background(Color(hex: "#0A0A0A").ignoresSafeArea())
        .navigationTitle("AirChat")
        .navigationBarTitleDisplayMode(.inline)
        .alert(NSLocalizedString("qr_title", comment: ""), isPresented: $showLargeQR) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(joinURL)
        }
    }

    private func infoCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding()
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }
}
