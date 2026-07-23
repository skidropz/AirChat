import Foundation

/// Delegate notified about messages coming from a remote AirChat host.
protocol WebSocketClientDelegate: AnyObject {
    func webSocketClient(_ client: WebSocketClient, didReceive text: String)
    func webSocketClientDidConnect(_ client: WebSocketClient)
    func webSocketClientDidDisconnect(_ client: WebSocketClient)
}

/// Connects to a remote AirChat host over WebSocket (for "Join" mode).
///
/// Uses the built-in `URLSessionWebSocketTask`, no external dependencies.
final class WebSocketClient: NSObject {
    weak var delegate: WebSocketClientDelegate?

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?

    /// `url` should look like `ws://192.168.1.10:8080/` (the host page).
    init(url: URL) {
        self.url = url
        super.init()
    }

    func connect() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive()
        startPing()
    }

    func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    func disconnect() {
        pingTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.delegate?.webSocketClient(self, didReceive: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.delegate?.webSocketClient(self, didReceive: text)
                    }
                @unknown default:
                    break
                }
                self.receive()
            case .failure:
                self.delegate?.webSocketClientDidDisconnect(self)
            }
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.task?.sendPing { _ in }
        }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol _: String?) {
        delegate?.webSocketClientDidConnect(self)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        delegate?.webSocketClientDidDisconnect(self)
    }
}
