import CoreGraphics
import Foundation
import ImageIO

/// Image utilities on ImageIO/CoreGraphics only — this module never imports AppKit.
public enum Thumbnailer {
    /// Downscaled PNG for panel display. Returns nil for undecodable data.
    public static func pngThumbnail(from imageData: Data, maxPixel: Int = 480) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        return pngData(from: cgImage)
    }

    /// Normalizes arbitrary decodable image data (e.g. pasteboard TIFF) to PNG.
    public static func pngData(normalizing imageData: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return pngData(from: cgImage)
    }

    /// Pixel dimensions without decoding the full image.
    public static func pixelSize(of imageData: Data) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height)
    }

    static func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, "public.png" as CFString, 1, nil
            )
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
