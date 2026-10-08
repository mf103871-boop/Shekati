// Reads original PNG pixels without rescaling or changing the screenshot.
// The screen-layout workflow forces light mode before running these fixtures.
import Foundation
import CoreGraphics
import ImageIO

struct PixelReport: Encodable {
    let path: String
    let imageOrientation: Int
    let blackEdgeFractions: [String: Double]
}

enum CaptureError: Error {
    case cannotReadImage(String)
    case cannotDecodePixels(String)
}

func inspect(_ path: String) throws -> PixelReport {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CaptureError.cannotReadImage(path)
    }
    let width = image.width
    let height = image.height
    let rowBytes = width * 4
    var pixels = [UInt8](repeating: 0, count: rowBytes * height)
    try pixels.withUnsafeMutableBytes { buffer in
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format) else {
            throw CaptureError.cannotDecodePixels(path)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
    func isBlack(x: Int, y: Int) -> Bool {
        let offset = y * rowBytes + x * 4
        return pixels[offset] <= 8 && pixels[offset + 1] <= 8 && pixels[offset + 2] <= 8
    }
    func blackColumn(_ x: Int) -> Bool {
        for y in stride(from: 0, to: height, by: max(1, height / 400)) {
            if !isBlack(x: x, y: y) { return false }
        }
        return true
    }
    func blackRow(_ y: Int) -> Bool {
        for x in stride(from: 0, to: width, by: max(1, width / 400)) {
            if !isBlack(x: x, y: y) { return false }
        }
        return true
    }
    // Only consecutive all-black lines at an edge count; keyboard keys, text, or
    // normal dark regions inside the interface cannot trigger this corruption check.
    func edgeRun(_ dimension: Int, reverse: Bool, blackLine: (Int) -> Bool) -> Int {
        var run = 0
        for index in 0..<dimension {
            if !blackLine(reverse ? dimension - index - 1 : index) { break }
            run += 1
        }
        return run
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    return PixelReport(path: path, imageOrientation: orientation, blackEdgeFractions: [
        "left": Double(edgeRun(width, reverse: false, blackLine: blackColumn)) / Double(width),
        "right": Double(edgeRun(width, reverse: true, blackLine: blackColumn)) / Double(width),
        "bottom": Double(edgeRun(height, reverse: false, blackLine: blackRow)) / Double(height),
        "top": Double(edgeRun(height, reverse: true, blackLine: blackRow)) / Double(height),
    ])
}

let reports = try CommandLine.arguments.dropFirst().map(inspect)
let encoded = try JSONEncoder().encode(reports)
print(String(decoding: encoded, as: UTF8.self))
