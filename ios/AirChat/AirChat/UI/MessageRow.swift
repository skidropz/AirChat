import SwiftUI
import AVFoundation

/// Renders a single chat message (text / image / audio / system).
struct MessageRow: View {
    let message: DisplayMessage
    let isMine: Bool
    let showSender: Bool
    let onReply: (AirChatMessage.ReplyRef) -> Void
    let onOpenImage: (String) -> Void
    let onTapSender: (String) -> Void

    @StateObject private var player = AudioPlayerHolder()
    @State private var appeared = false

    var body: some View {
        if message.type == .system {
            Text(message.text ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        } else {
            HStack {
                if isMine { Spacer(minLength: 40) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                    if showSender {
                        Button(message.sender) { onTapSender(message.sender) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.bubbleColor(for: message.color, dark: true))
                    }
                    bubble
                    if !message.seenBy.isEmpty {
                        Text(NSLocalizedString("seen_by", comment: "") + message.seenBy.joined(separator: ", "))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                if !isMine { Spacer(minLength: 40) }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.82, anchor: isMine ? .bottomTrailing : .bottomLeading)
            .offset(x: appeared ? 0 : (isMine ? 34 : -34), y: appeared ? 0 : 10)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: appeared)
            .onAppear {
                guard !appeared else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    appeared = true
                }
            }
            .contextMenu {
                Button {
                    let ref = AirChatMessage.ReplyRef(
                        id: message.id,
                        sender: message.sender,
                        text: replyPreviewText
                    )
                    onReply(ref)
                } label: {
                    Label(NSLocalizedString("reply", comment: ""), systemImage: "arrowshape.turn.up.left")
                }
            }
        }
    }

    private var replyPreviewText: String {
        switch message.type {
        case .image: return NSLocalizedString("reply_img", comment: "")
        case .audio: return NSLocalizedString("reply_audio", comment: "")
        default: return message.text ?? ""
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let emojiOnly = message.type == .chat && isEmojiOnly(message.text)
        VStack(alignment: .leading, spacing: 6) {
            if let reply = message.reply {
                replyPreview(reply)
            }
            switch message.type {
            case .chat:
                Text(message.text ?? "")
                    .textSelection(.enabled)
                    .font(emojiOnly ? .system(size: 44) : .body)
            case .image:
                if let data = message.imageData {
                    Group {
                        if let ui = ImageViewer.decode(data) {
                            Image(uiImage: ui).resizable().scaledToFill()
                        }
                    }
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipped()
                    .cornerRadius(emojiOnly ? 0 : 14)
                    .onTapGesture { onOpenImage(data) }
                }
            case .audio:
                audioPlayer(data: message.audioData ?? "")
            case .buzz, .system:
                EmptyView()
            }
        }
        .padding(emojiOnly ? 2 : 10)
        .background(emojiOnly ? Color.clear : Theme.bubbleColor(for: message.color, dark: true))
        .foregroundColor(emojiOnly ? .primary : Theme.textColor(for: message.color, dark: true))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func replyPreview(_ reply: AirChatMessage.ReplyRef) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reply.sender).font(.caption.weight(.bold))
            Text(reply.text).font(.caption).lineLimit(1)
        }
        .padding(6)
        .background(.black.opacity(0.2))
        .cornerRadius(8)
        .frame(maxWidth: 200, alignment: .leading)
    }

    private func audioPlayer(data: String) -> some View {
        HStack(spacing: 10) {
            Button {
                player.toggle(dataURL: data)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
            }
            if let dur = player.duration {
                Text(String(format: "%.0fs", dur))
                    .font(.caption)
            } else {
                Text("🎤")
            }
            Image(systemName: "waveform")
                .opacity(0.6)
        }
    }
}

/// Small AVAudioPlayer wrapper for voice messages.
@MainActor
final class AudioPlayerHolder: ObservableObject {
    @Published var isPlaying = false
    @Published var duration: TimeInterval?
    private var player: AVAudioPlayer?

    func toggle(dataURL: String) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let p = try? AVAudioPlayer(data: data) else { return }
        player = p
        duration = p.duration
        p.play()
        isPlaying = true
        // poll completion
        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.1) { [weak self] in
            self?.isPlaying = false
        }
    }
}
