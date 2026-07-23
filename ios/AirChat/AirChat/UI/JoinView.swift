import SwiftUI

/// Join screen: paste the host URL (http://IP:PORT/#KEY) or enter host + key manually.
struct JoinView: View {
    let onConnect: (String, UInt16, String) -> Void

    @State private var rawInput: String = ""
    @State private var host: String = ""
    @State private var port: String = String(AppConstants.port)
    @State private var key: String = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(NSLocalizedString("paste_url", comment: "")) {
                TextField("http://192.168.1.10:8080/#...", text: $rawInput, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: rawInput) { _, new in parseURL(new) }
            }

            Section(NSLocalizedString("or_manual", comment: "")) {
                LabeledContent(NSLocalizedString("host_field", comment: "")) {
                    TextField("192.168.1.10", text: $host)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent(NSLocalizedString("port_field", comment: "")) {
                    TextField("8080", text: $port)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(NSLocalizedString("key_field", comment: "")) {
                    TextField("ABCD...", text: $key)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle(NSLocalizedString("join_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("connect_btn", comment: "")) { attemptConnect() }
                    .disabled(host.isEmpty || key.isEmpty)
            }
        }
    }

    private func parseURL(_ input: String) {
        guard let url = URL(string: input) else { return }
        host = url.host ?? ""
        if let p = url.port { port = String(p) }
        if let frag = url.fragment { key = frag }
    }

    private func attemptConnect() {
        error = nil
        guard !host.isEmpty, let portValue = UInt16(port), !key.isEmpty else {
            error = NSLocalizedString("join_error", comment: "")
            return
        }
        onConnect(host, portValue, key)
    }
}
