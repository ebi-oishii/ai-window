import AppKit
import CoreGraphics

/// Snap the main display to PNG bytes. Used to feed visual context to the
/// multimodal LLM call. Requires Screen Recording permission — macOS will
/// prompt on first call.
enum ScreenCapture {
    static func captureMainDisplay() -> Data? {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // Downscale aggressively so the prompt doesn't balloon — a 1px-perfect
        // capture of a retina display is ~5MB base64 which crushes rate limits.
        return bitmap.representation(using: .png, properties: [
            .compressionFactor: NSNumber(value: 0.7),
        ])
    }

    static func captureMainDisplayBase64() -> String? {
        captureMainDisplay()?.base64EncodedString()
    }
}
