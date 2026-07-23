import Foundation
import SwiftUI
import CoreImage.CIFilterBuiltins

/// Generates a QR code image for a string (uses the built-in CoreImage filter).
enum QRGenerator {
    static func image(from string: String, scale: CGFloat = 10) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Displays a QR code as a SwiftUI view.
struct QRCodeView: View {
    let text: String
    var scale: CGFloat = 10

    var body: some View {
        if let image = QRGenerator.image(from: text, scale: scale) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.gray.opacity(0.3)
        }
    }
}

/// Full-screen image viewer.
struct ImageViewer: View {
    let dataURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let uiImage = ImageViewer.decode(dataURL) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding()
            }
        }
    }

    static func decode(_ dataURL: String) -> UIImage? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}
