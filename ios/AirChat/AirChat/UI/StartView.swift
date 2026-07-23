import SwiftUI

/// The initial screen: pick a name, a bubble colour, and whether to HOST or JOIN.
struct StartView: View {
    let onStart: (String, String, AppMode) -> Void

    @State private var name: String = ""
    @State private var selectedColor: String = "blue"
    @State private var selectedMode: AppMode = .host

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#0A0A0A"), Color(hex: "#10182A")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 30)

                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.tint)
                    Text("AirChat")
                        .font(.system(size: 40, weight: .bold))
                    Text("Offline · Peer-to-Peer · E2EE")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    TextField(NSLocalizedString("name_placeholder", comment: ""), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .submitLabel(.done)

                    VStack(spacing: 8) {
                        Text(NSLocalizedString("choose_color", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(AppConstants.colors, id: \.self) { c in
                                Circle()
                                    .fill(c == "white" ? AnyShapeStyle(.white) : AnyShapeStyle(Color(hex: AppConstants.colorHex[c]!)))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(.white, lineWidth: selectedColor == c ? 3 : 0))
                                    .onTapGesture { selectedColor = c }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    modeButton(.host, icon: "wifi.router", title: NSLocalizedString("host_btn", comment: ""),
                               subtitle: NSLocalizedString("host_subtitle", comment: ""))
                    modeButton(.client, icon: "person.crop.circle.badge.questionmark", title: NSLocalizedString("join_btn", comment: ""),
                               subtitle: NSLocalizedString("join_subtitle", comment: ""))
                }
                .padding(.horizontal)

                Spacer()

                Button {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onStart(name.trimmingCharacters(in: .whitespaces), selectedColor, selectedMode)
                } label: {
                    Text(NSLocalizedString("connect_btn", comment: ""))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(name.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.bubbleColor(for: selectedColor, dark: true)))
                        .foregroundColor(name.isEmpty ? .gray : Theme.textColor(for: selectedColor, dark: true))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 24)

                Text("Made with ❤️ by SkiDropz")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modeButton(_ mode: AppMode, icon: String, title: String, subtitle: String) -> some View {
        Button {
            selectedMode = mode
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selectedMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedMode == mode ? .tint : .secondary)
            }
            .padding()
            .background(.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedMode == mode ? Color.accentColor : .clear, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
