import SwiftUI
import AVFoundation
import PhotosUI

/// The bottom input bar: attach photo, type text, record voice, send, buzz.
struct ComposerBar: View {
    let onSendText: (String) -> Void
    let onSendImage: (String) -> Void
    let onSendAudio: (String) -> Void
    let onBuzz: () -> Void

    @State private var text: String = ""
    @State private var photoItem: PhotosPickerItem?
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        VStack(spacing: 0) {
            if recorder.isRecording {
                recordingBar
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: photoItem) { _, item in handlePhoto(item) }

                Button { onBuzz() } label: {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                }

                TextField(NSLocalizedString("type_msg", comment: ""), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.1))
                    .clipShape(Capsule())

                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    micButton
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    private var recordingBar: some View {
        HStack {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                .font(.caption.monospacedDigit())
            Spacer()
            Text(NSLocalizedString("swipe_cancel", comment: ""))
                .font(.caption2).foregroundStyle(.secondary)
            Button(NSLocalizedString("cancel", comment: "")) {
                recorder.cancel()
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.red.opacity(0.12))
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { _ in recorder.cancel() }
        )
    }

    private var micButton: some View {
        Button {
            if recorder.isRecording { recorder.finish { onSendAudio($0) } }
            else { recorder.start() }
        } label: {
            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(recorder.isRecording ? .red : .tint)
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSendText(trimmed)
        text = ""
    }

    private func handlePhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let send = onSendImage
        item.loadTransferable(type: Data.self) { result in
            guard case .success(let data?) = result, let data else { return }
            if let dataURL = ComposerBar.encodeImage(data) {
                DispatchQueue.main.async { send(dataURL) }
            }
        }
    }

    /// Downscale + JPEG-encode to a data URL, mirroring the web client.
    static func encodeImage(_ data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        let maxSize: CGFloat = 800
        var size = img.size
        if size.width > size.height {
            if size.width > maxSize { size.height *= maxSize / size.width; size.width = maxSize }
        } else {
            if size.height > maxSize { size.width *= maxSize / size.height; size.height = maxSize }
        }
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        img.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let jpeg = resized?.jpegData(compressionQuality: 0.7) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}

/// Records a voice note to a temp m4a file and returns a base64 data URL.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    private var startedAt: Date?

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("airchat-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            fileURL = url
            startedAt = Date()
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let s = self?.startedAt else { return }
                    self?.elapsed = Date().timeIntervalSince(s)
                }
            }
        } catch {
            isRecording = false
        }
    }

    func finish(_ completion: @escaping (String) -> Void) {
        guard let r = recorder, isRecording else { return }
        // Discard very short taps (< 0.4s).
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        r.stop()
        cleanup()
        guard duration >= 0.4, let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let dataURL = "data:audio/m4a;base64," + data.base64EncodedString()
        completion(dataURL)
    }

    func cancel() {
        recorder?.stop()
        cleanup()
    }

    private func cleanup() {
        timer?.invalidate(); timer = nil
        isRecording = false
        elapsed = 0
        recorder = nil
    }
}
