import AppKit
import HowlerCore
import ImageIO
import UniformTypeIdentifiers

enum ScreenCaptureError: LocalizedError {
    case permissionNeeded
    case unreadable

    var errorDescription: String? {
        switch self {
        case .permissionNeeded:
            return "To capture the screen, allow \(AppInfo.name) in System Settings › Privacy & Security › Screen & System Audio Recording, then try again."
        case .unreadable:
            return "The screen capture couldn't be read."
        }
    }
}

/// Lets the user drag out a region of the screen with the system's own crosshair
/// (`screencapture -i`), the same tool as ⇧⌘4. Esc cancels.
enum ScreenCapture {
    /// Without Screen Recording permission a capture would contain only the wallpaper.
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system's permission prompt (once; later it points to System Settings).
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func captureRegion(completion: @escaping @MainActor (Result<ImageData, Error>?) -> Void) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("howler-capture-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", file.path] // interactive, silent
        process.terminationHandler = { _ in
            defer { try? FileManager.default.removeItem(at: file) }
            // No file means the user pressed Esc.
            let result: Result<ImageData, Error>? = (try? Data(contentsOf: file)).map { data in
                UploadImage.prepare(data).map(Result.success) ?? .failure(ScreenCaptureError.unreadable)
            }
            Task { @MainActor in completion(result) }
        }
        do {
            try process.run()
        } catch {
            Task { @MainActor in completion(.failure(error)) }
        }
    }
}

/// Scales and encodes a picture for a model: at most 1568 px on the long edge (larger
/// images are downscaled by the providers anyway), PNG for sharp text, JPEG if the PNG
/// would be heavy.
enum UploadImage {
    static let maxPixels = 1568
    private static let maxPNGBytes = 3_500_000

    static func prepare(_ data: Data) -> ImageData? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary)
        else { return nil }

        if let png = encode(image, as: .png), png.count <= maxPNGBytes {
            return ImageData(data: png, mediaType: "image/png", width: image.width, height: image.height)
        }
        guard let jpeg = encode(image, as: .jpeg, quality: 0.85) else { return nil }
        return ImageData(data: jpeg, mediaType: "image/jpeg", width: image.width, height: image.height)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
