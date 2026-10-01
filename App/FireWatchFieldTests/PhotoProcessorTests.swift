import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import FireWatchField

/// Photos keep only their GPS position (NFR-8).
struct PhotoProcessorTests {
    /// A 3000 × 2000 JPEG carrying EXIF and TIFF details plus a GPS position.
    func jpegWithMetadata() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 3_000, height: 2_000, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0.4, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 2_000))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifBodySerialNumber: "SN-12345"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Crew member"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 36.83, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 31.47, kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func properties(of jpeg: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func keepsGPSAndDropsEverythingElse() throws {
        let processed = try #require(PhotoProcessor.prepare(try jpegWithMetadata()))
        let metadata = try properties(of: processed)
        let gps = try #require(metadata[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        #expect(gps[kCGImagePropertyGPSLatitude] as? Double == 36.83)
        let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifBodySerialNumber] == nil)
        let tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFArtist] == nil)
    }

    @Test func shrinksLargePhotos() throws {
        let processed = try #require(PhotoProcessor.prepare(try jpegWithMetadata()))
        let metadata = try properties(of: processed)
        #expect(metadata[kCGImagePropertyPixelWidth] as? Int == PhotoProcessor.maximumDimension)
    }

    @Test func rejectsNonImages() {
        #expect(PhotoProcessor.prepare(Data("not an image".utf8)) == nil)
    }
}
