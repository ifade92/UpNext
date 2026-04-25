//
//  QRCodeView.swift
//  UpNext
//
//  Generates and displays a QR code for any URL string.
//  Uses CoreImage's built-in CIQRCodeGenerator filter — no external libraries needed.
//
//  Usage:
//    QRCodeView(url: "https://square.site/...", size: 200)
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {

    let url: String
    var size: CGFloat = 200
    var foregroundColor: Color = .white
    var backgroundColor: Color = Color.brandInput

    var body: some View {
        if let qrImage = generateQRCode(from: url) {
            Image(uiImage: qrImage)
                .interpolation(.none)          // Sharp pixels — never blur a QR code
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(16)
                .background(Color.white)       // QR codes need a white background to scan reliably
                .cornerRadius(16)
        } else {
            // Fallback if generation fails (shouldn't happen in practice)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.brandInput)
                    .frame(width: size, height: size)
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("QR unavailable")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - QR Generation

    /// Generates a UIImage of the QR code for the given string.
    /// CoreImage handles all the encoding — we just set the input and scale it up.
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        // Encode the URL as UTF-8 data
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")

        // Error correction level: M = ~15% correction, good balance for most use cases
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up from the tiny default size (~33x33) to something scannable
        // UITraitCollection.current.displayScale replaces the deprecated UIScreen.main.scale
        let screenScale = UITraitCollection.current.displayScale
        let scale = size / ciImage.extent.width * screenScale * 2
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.brandNearBlack.ignoresSafeArea()
        VStack(spacing: 20) {
            QRCodeView(url: "https://squareup.com/appointments/book/example", size: 200)
            Text("Scan to book an appointment")
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}
