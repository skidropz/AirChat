import SwiftUI

/// Active users list: tap to open a private chat, 🧭 to locate.
struct UsersSheet: View {
    @ObservedObject var store: ChatStore
    @ObservedObject var location: LocationManager
    @ObservedObject var battery: BatteryMonitor
    let onOpenPrivate: (RoomUser) -> Void
    let onLocate: (RoomUser) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("active_users", comment: "")) {
                    row(RoomUser(name: store.myName + " " + NSLocalizedString("me_suffix", comment: ""),
                                  color: store.myColor, battery: battery.level,
                                  lat: location.coordinate?.latitude,
                                  lon: location.coordinate?.longitude,
                                  lastSeen: Date()), isMe: true)
                    ForEach(Array(store.users.values.sorted { $0.name < $1.name })) { user in
                        row(user, isMe: false)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("active_users", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) { }
                }
            }
        }
    }

    private func row(_ user: RoomUser, isMe: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.bubbleColor(for: user.color, dark: true))
                    .frame(width: 40, height: 40)
                Text(String(user.name.prefix(1)).uppercased())
                    .foregroundColor(Theme.textColor(for: user.color, dark: true))
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(user.name).font(.subheadline.weight(.semibold))
                    if !isMe, let u = store.unreadCounts[user.name], u > 0 {
                        Text("\(u)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                            .foregroundColor(.white)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.green)
                    Text(NSLocalizedString("status_online", comment: "")).font(.caption).foregroundStyle(.secondary)
                    if let b = user.battery {
                        Label("\(b)%", systemImage: batteryIcon(b))
                            .font(.caption2)
                            .foregroundStyle(b > 20 ? Color.secondary : Color.red)
                    }
                }
            }
            Spacer()
            if !isMe {
                Button { onOpenPrivate(user) } label: {
                    Image(systemName: "bubble.left").foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                Button { onLocate(user) } label: {
                    Image(systemName: "location.north.line").foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isMe { onOpenPrivate(user) }
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 80...: return "battery.100"
        case 60...: return "battery.75"
        case 40...: return "battery.50"
        case 20...: return "battery.25"
        default: return "battery.0"
        }
    }
}
