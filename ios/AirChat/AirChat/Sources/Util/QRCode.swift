//
//  QRCode.swift
//  AirChat
//
//  Replaces MainActivity.generateQrCode() (ZXing) with CoreImage. Same idea:
//  encode the join URL, draw it big enough to be scanned across a room.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCode {

    static func image(from text: String, moduleSize: CGFloat = 8) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"      // the room key makes for a long payload
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleSize, y: moduleSize))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        // No interpolation: the modules must stay pixel-sharp to be scannable.
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}
