//
//  CheckInPosterGenerator.swift
//  UpNext
//
//  Builds a print-ready, US-Letter PDF poster containing the shop's check-in
//  QR code. Shop owners can print this and tape it up at their front desk,
//  on mirrors, or in the waiting area so customers can self-check-in.
//
//  Visual style (matches Fademasters reference):
//    • Thick green border around the whole page
//    • Light gray interior
//    • Big stacked "SCAN TO SIGN IN" headline in heavy brand type
//    • Large white QR card centered below
//    • Subtle "Powered by UpNext" footer
//
//  Usage:
//    if let url = CheckInPosterGenerator.makePDF(shopName: "Fademasters",
//                                                checkInURL: "...") {
//        // Share via UIActivityViewController or AirPrint
//    }
//

import UIKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Share Sheet Wrapper

/// A thin SwiftUI wrapper over UIActivityViewController so we can present
/// the native iOS share / print / save-to-Files UI for any file URL.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum CheckInPosterGenerator {

    // MARK: - Brand

    // UpNext accent green — mirrors `Color.accent` (#2ECC71). Hard-coded here
    // because PDF rendering happens outside any SwiftUI environment.
    private static let brandGreen = UIColor(red: 0x2E/255.0, green: 0xCC/255.0, blue: 0x71/255.0, alpha: 1)
    private static let brandGreenDark = UIColor(red: 0x1B/255.0, green: 0xA3/255.0, blue: 0x55/255.0, alpha: 1)

    // MARK: - Public

    /// Generates a US-Letter (8.5" × 11") PDF poster and writes it to a
    /// temporary file. Returns the file URL on success, or nil on failure.
    static func makePDF(shopName: String, checkInURL: String) -> URL? {

        // 72 pts per inch — US Letter = 8.5 × 11 inches
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Safe filename: strip anything that isn't letters/numbers.
        let safeShop = shopName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fileName = "UpNext-SignIn-\(safeShop.isEmpty ? "Poster" : safeShop).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                drawPoster(in: pageRect, shopName: shopName, checkInURL: checkInURL)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Drawing

    /// Renders every visual element of the poster into the current PDF context.
    private static func drawPoster(in page: CGRect, shopName: String, checkInURL: String) {

        // ── Green border frame ──────────────────────────────────────────────
        // A thick green rectangle around the edge gives the poster a
        // strong, recognizable brand silhouette from across the shop.
        brandGreen.setFill()
        UIRectFill(page)

        // ── Light gray interior ─────────────────────────────────────────────
        let borderThickness: CGFloat = 28
        let interior = page.insetBy(dx: borderThickness, dy: borderThickness)
        UIColor(white: 0.91, alpha: 1).setFill()
        UIRectFill(interior)

        // ── Headline: stacked "SCAN TO" / "SIGN IN" ─────────────────────────
        // Gagalin — condensed, chunky display font.
        // Gracefully falls back to Outfit-Bold (already bundled) and then
        // to the system black weight if the custom font isn't installed.
        let headlineFont = UIFont(name: "Gagalin-Regular", size: 100)
            ?? UIFont(name: "Gagalin", size: 100)
            ?? UIFont(name: "Outfit-Bold", size: 100)
            ?? UIFont.systemFont(ofSize: 100, weight: .black)
        let headlineAttrs: [NSAttributedString.Key: Any] = [
            .font: headlineFont,
            .foregroundColor: UIColor(white: 0.18, alpha: 1),
            .kern: 2.0
        ]

        let line1 = "SCAN TO"
        let line2 = "SIGN IN"
        let line1Size = (line1 as NSString).size(withAttributes: headlineAttrs)
        let line2Size = (line2 as NSString).size(withAttributes: headlineAttrs)

        // Position the first line near the top of the interior, stack the
        // second line directly below with a tight line-height.
        let topPadding: CGFloat = 50
        let line1Rect = CGRect(
            x: (page.width - line1Size.width) / 2,
            y: interior.minY + topPadding,
            width: line1Size.width,
            height: line1Size.height
        )
        (line1 as NSString).draw(in: line1Rect, withAttributes: headlineAttrs)

        let line2Rect = CGRect(
            x: (page.width - line2Size.width) / 2,
            y: line1Rect.maxY + 4,
            width: line2Size.width,
            height: line2Size.height
        )
        (line2 as NSString).draw(in: line2Rect, withAttributes: headlineAttrs)

        // ── Optional shop name — small label above the QR ───────────────────
        let trimmedShop = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        var qrTopY = line2Rect.maxY + 28
        if !trimmedShop.isEmpty {
            let nameFont = UIFont(name: "Outfit-Bold", size: 18)
                ?? UIFont.systemFont(ofSize: 18, weight: .semibold)
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: brandGreenDark,
                .kern: 2.5
            ]
            let nameStr = trimmedShop.uppercased() as NSString
            let nameSize = nameStr.size(withAttributes: nameAttrs)
            nameStr.draw(
                in: CGRect(
                    x: (page.width - nameSize.width) / 2,
                    y: qrTopY,
                    width: nameSize.width,
                    height: nameSize.height
                ),
                withAttributes: nameAttrs
            )
            qrTopY += nameSize.height + 14
        }

        // ── QR card ─────────────────────────────────────────────────────────
        // Plain white square — matches the reference's crisp, rectangular
        // QR panel. Sized to leave generous breathing room above the
        // footer so the "Powered by UpNext" mark never blends into the
        // QR's pixel pattern.
        let qrCardSize: CGFloat = 270
        let qrCardRect = CGRect(
            x: (page.width - qrCardSize) / 2,
            y: qrTopY,
            width: qrCardSize,
            height: qrCardSize
        )
        UIColor.white.setFill()
        UIRectFill(qrCardRect)

        // Generate the QR image at high resolution so it prints crisp.
        if let qrImage = makeQRImage(from: checkInURL, size: qrCardSize - 28) {
            let qrRect = CGRect(
                x: qrCardRect.midX - qrImage.size.width / 2,
                y: qrCardRect.midY - qrImage.size.height / 2,
                width: qrImage.size.width,
                height: qrImage.size.height
            )
            qrImage.draw(in: qrRect)
        }

        // ── Footer: "Powered by UpNext" + brand mark ────────────────────────
        drawBrandFooter(in: page, interior: interior)
    }

    /// Draws the compact "▪ Powered by UpNext" mark + wordmark at the bottom
    /// center of the interior. Uses the brand green accent.
    private static func drawBrandFooter(in page: CGRect, interior: CGRect) {

        let footerY: CGFloat = interior.maxY - 28
        let markSize: CGFloat = 14
        let gap: CGFloat = 3
        let barHeight: CGFloat = markSize * 0.27
        let dotSize: CGFloat = markSize * 0.35
        let wideBar: CGFloat = markSize
        let shortBar: CGFloat = markSize * 0.58
        let radius: CGFloat = barHeight * 0.35

        let accent = brandGreen
        let accentSoft = accent.withAlphaComponent(0.6)

        // Build the "Powered by UpNext" text first so we can center the
        // whole mark + label group horizontally as one unit.
        let poweredAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Outfit-Regular", size: 11)
                ?? UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor(white: 0.45, alpha: 1)
        ]
        let upAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Outfit-Bold", size: 11)
                ?? UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor(white: 0.18, alpha: 1)
        ]
        let nextAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Outfit-Bold", size: 11)
                ?? UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: accent
        ]

        let powered = NSAttributedString(string: "Powered by  ", attributes: poweredAttrs)
        let up = NSAttributedString(string: "Up", attributes: upAttrs)
        let next = NSAttributedString(string: "Next", attributes: nextAttrs)
        let label = NSMutableAttributedString()
        label.append(powered)
        label.append(up)
        label.append(next)
        let labelSize = label.size()

        let markToLabelPad: CGFloat = 8
        let totalWidth = markSize + markToLabelPad + labelSize.width
        let startX = (page.width - totalWidth) / 2

        // Draw the stacked dot + two bars (same proportions as UpNextMark).
        let markTopY = footerY - (dotSize + gap + barHeight + gap + barHeight) / 2 + 2
        accentSoft.setFill()
        UIBezierPath(ovalIn: CGRect(x: startX, y: markTopY, width: dotSize, height: dotSize)).fill()
        accent.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: startX, y: markTopY + dotSize + gap, width: wideBar, height: barHeight),
            cornerRadius: radius
        ).fill()
        accentSoft.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: startX, y: markTopY + dotSize + gap + barHeight + gap, width: shortBar, height: barHeight),
            cornerRadius: radius
        ).fill()

        // Label centered vertically against the mark block.
        let labelX = startX + markSize + markToLabelPad
        let labelY = footerY - labelSize.height / 2
        label.draw(at: CGPoint(x: labelX, y: labelY))
    }

    // MARK: - QR Helper

    /// Generates a high-error-correction QR UIImage sized for print.
    /// Error correction "H" = ~30% recovery — safe if the poster gets a
    /// coffee stain or gets partially covered.
    private static func makeQRImage(from string: String, size: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let output = filter.outputImage else { return nil }

        // Scale up from the tiny native output so each QR "pixel" prints
        // as a sharp black square — no anti-aliasing blur.
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
