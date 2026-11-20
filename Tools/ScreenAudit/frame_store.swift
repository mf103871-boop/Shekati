import AppKit
import Foundation

// Compose localized App Store artwork from unchanged native screenshots.
// The original PNG is retained side by side with each storefront derivative.
struct StoreCopy: Decodable {
    let screenshotHeadings: [String]
}

enum ArtworkError: Error {
    case arguments, image, headingDoesNotFit, render
}

func render(folder: URL, metadata: URL) throws {
    let copy = try JSONDecoder().decode(StoreCopy.self, from: Data(contentsOf: metadata))
    let names = ["01-home", "02-ledger", "03-review", "04-detail", "05-calendar"]
    guard copy.screenshotHeadings.count == names.count else { throw ArtworkError.arguments }
    let destination = folder.appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for (name, heading) in zip(names, copy.screenshotHeadings) {
        guard let raw = NSImage(contentsOf: folder.appendingPathComponent(name + ".png")),
              let source = raw.cgImage(forProposedRect: nil, context: nil, hints: nil),
              source.width == 1206, source.height == 2622,
              let canvas = CGContext(data: nil, width: source.width, height: source.height,
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ArtworkError.image }
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let scale = width / 1320
        canvas.setFillColor(red: 0.024, green: 0.216, blue: 0.235, alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let header = CGRect(x: 63 * scale, y: height - 265 * scale,
                            width: width - 126 * scale, height: 210 * scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var fitted = false
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
        for size in stride(from: CGFloat(76), through: 38, by: -2) {
            let text = NSAttributedString(string: heading, attributes: [
                .font: NSFont.systemFont(ofSize: size * scale, weight: .semibold),
                .foregroundColor: NSColor.white, .paragraphStyle: paragraph
            ])
            let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
            let required = text.boundingRect(with: NSSize(width: header.width, height: .greatestFiniteMagnitude),
                                             options: options).integral
            if required.height + 12 * scale <= header.height && required.width <= header.width {
                text.draw(with: CGRect(x: header.minX, y: header.midY - required.height / 2,
                                       width: header.width, height: required.height + 4 * scale), options: options)
                fitted = true
                break
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard fitted else { throw ArtworkError.headingDoesNotFit }
        let imageHeight = height - 308 * scale
        let imageWidth = width * imageHeight / height
        canvas.interpolationQuality = .high
        canvas.draw(source, in: CGRect(x: (width - imageWidth) / 2, y: 28 * scale,
                                       width: imageWidth, height: imageHeight))
        guard let frame = canvas.makeImage(),
              let data = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) else { throw ArtworkError.render }
        try data.write(to: destination.appendingPathComponent(name + ".png"), options: .atomic)
    }
}

guard CommandLine.arguments.count == 3 else { throw ArtworkError.arguments }
try render(folder: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
           metadata: URL(fileURLWithPath: CommandLine.arguments[2]))

