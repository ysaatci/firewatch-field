import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares a photo for a report: a reasonably sized JPEG whose only metadata is where it was
/// taken (NFR-8). Camera serial numbers, owner names and the like never leave the device.
enum PhotoProcessor {
    /// Longest side, in pixels.
    static let maximumDimension = 1_600

    /// The processed JPEG, or `nil` if `data` isn't an image.
    static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,  // apply orientation, then drop it
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                ] as CFDictionary)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let gps = original?[kCGImagePropertyGPSDictionary] {
            properties[kCGImagePropertyGPSDictionary] = gps
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Report photos on disk, named by UUID, until they are sent.
enum PhotoStore {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ReportPhotos", isDirectory: true)
    }

    /// Saves `jpeg` and returns its file name.
    static func save(_ jpeg: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    static func load(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }
}
