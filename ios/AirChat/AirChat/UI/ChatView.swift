import SwiftUI

/// The main conversation screen.
struct ChatView: View {
    @ObservedObject var store: ChatStore
    let onDisconnect: () -> Void

    @State private var showUsers = false
    @State private var showCompass = false
    @State private var compassTarget: RoomUser?
    @State private var fullImage: String?
    @State private var reply: AirChatMessage.ReplyRef?
    @State private var shakeOffset: CGFloat = 0
    @State private var glow = false

    private var filteredMessages: [DisplayMessage] {
        store.messages.filter { $0.chatGroup == store.activeChat }
    }

    private var isPrivate: Bool { store.activeChat != "general" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            if let reply {
                replyBar(reply)
            }
            ComposerBar(
                onSendText: { store.sendText($0, replyTo: reply) ; self.reply = nil },
                onSendImage: { store.sendImage(dataURL: $0, replyTo: reply) ; self.reply = nil },
                onSendAudio: { store.sendAudio(dataURL: $0, replyTo: reply) ; self.reply = nil },
                onBuzz: { store.sendBuzz(to: store.activeChat) }
            )
        }
        .background {
            ZStack {
                Color(hex: "#0A0A0A").ignoresSafeArea()
                RadialGradient(colors: [Color.accentColor.opacity(glow ? 0.16 : 0.06), .clear], center: .topTrailing, startRadius: 20, endRadius: 520)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glow)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(store.activeChat == "general" ? "AirChat" : store.activeChat)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isPrivate {
                    Button { store.activeChat = "general" } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        onDisconnect()
                    } label: {
                        Label(NSLocalizedString("disconnect", comment: "Disconnect"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showUsers = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2")
                        Text("\(1 + store.users.count)")
                    }
                }
            }
        }
        .sheet(isPresented: $showUsers) {
            UsersSheet(store: store, location: store.locationManager, battery: store.batteryMonitor) { user in
                openPrivate(user.name)
            } onLocate: { user in
                compassTarget = user
                showCompass = true
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCompass) {
            if let target = compassTarget {
                CompassSheet(store: store, location: store.locationManager, target: target)
            }
        }
        .sheet(item: Binding(get: { fullImage.map { IdentifiableString(value: $0) } },
                             set: { fullImage = $0?.value })) { item in
            ImageViewer(dataURL: item.value)
        }
        .overlay(alignment: .top) {
            if let banner = store.buzzBanner {
                Text(banner)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .offset(x: shakeOffset)
        .animation(.easeInOut, value: store.buzzBanner)
        .onChange(of: store.shakeTrigger) { _, _ in triggerShake() }
        .onAppear {
            store.locationManager.requestPermissionAndStart()
            glow = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.connected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(store.connected ? NSLocalizedString("online", comment: "")
                                 : NSLocalizedString("connecting", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { idx, msg in
                        MessageRow(
                            message: msg,
                            isMine: msg.isMine,
                            showSender: showSender(at: idx),
                            onReply: { reply = $0 },
                            onOpenImage: { fullImage = $0 },
                            onTapSender: { openPrivate($0) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: filteredMessages.count) { _, _ in
                withAnimation { proxy.scrollTo(filteredMessages.last?.id, anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo(filteredMessages.last?.id, anchor: .bottom)
            }
        }
    }

    private func showSender(at idx: Int) -> Bool {
        let msg = filteredMessages[idx]
        if msg.isMine || msg.type == .system { return false }
        if idx == 0 { return true }
        let prev = filteredMessages[idx - 1]
        return prev.sender != msg.sender || prev.chatGroup != msg.chatGroup || prev.type == .system
    }

    private func replyBar(_ reply: AirChatMessage.ReplyRef) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(NSLocalizedString("reply_to", comment: "")) \(reply.sender)")
                    .font(.caption.weight(.semibold))
                Text(reply.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { self.reply = nil } label: { Image(systemName: "xmark.circle.fill") }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.white.opacity(0.06))
    }

    private func openPrivate(_ name: String) {
        guard !name.isEmpty, name != store.myName else { return }
        store.activeChat = name
        store.unreadCounts[name] = 0
        showUsers = false
    }

    private func triggerShake() {
        let amplitude: CGFloat = 8
        withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = amplitude }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = -amplitude }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = 0 }
        }
    }
}

private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}
