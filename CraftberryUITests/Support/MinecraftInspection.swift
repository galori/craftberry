import CoreImage
import ImageIO
import Vision
import XCTest

struct MinecraftOCRInspector {
    /// Both landscape orientations, then both portrait ones.
    ///
    /// Minecraft renders landscape inside the device's portrait screen buffer, and which of the two
    /// landscape orientations it settles in varies between runs: confirmed live on two otherwise
    /// identical runs, where the second captured every in-world frame rotated 180° from the first
    /// and so every OCR assertion missed text that was plainly on screen. Taps are unaffected
    /// because XCUITest normalizes those to the interface orientation — only the raw screenshot
    /// buffer flips — which is what makes the failure so confusing: the run drives the UI correctly
    /// and then fails to read the result.
    let orientations: [CGImagePropertyOrientation] = [.left, .right, .up, .down]

    func recognizedText() -> String {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else {
            XCTFail("Could not create a CGImage for Minecraft OCR")
            return ""
        }
        return recognizedText(in: image)
    }

    func recognizedText(in image: CGImage) -> String {
        orientations.flatMap { recognizedLines(in: image, orientation: $0) }.joined(separator: "\n")
    }

    func waitForRecognizedText(_ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let image = XCUIScreen.main.screenshot().image.cgImage, contains(expected, in: image) {
                return true
            }
            usleep(150_000)
        } while Date() < deadline
        return false
    }

    /// Stops at the first orientation that matches rather than recognizing all four every time.
    /// Some of the text this waits on is transient — an item-name tooltip fades after about a
    /// second — so a full four-orientation pass per poll would risk spending the tooltip's whole
    /// lifetime inside a single poll of Vision.
    private func contains(_ expected: String, in image: CGImage) -> Bool {
        orientations.contains { orientation in
            recognizedLines(in: image, orientation: orientation)
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(expected)
        }
    }

    private func recognizedLines(in image: CGImage, orientation: CGImagePropertyOrientation) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        } catch {
            XCTFail("Minecraft OCR failed: \(error)")
            return []
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

struct MinecraftPixelInspector {
    /// Minecraft renders landscape inside the device's portrait screenshot buffer. Normalize the
    /// raw buffer before sampling calibrated interface coordinates, just as the OCR inspector does.
    private let orientations: [CGImagePropertyOrientation] = [.left, .right, .up, .down]

    func matches(_ expectation: MinecraftPixelExpectation) -> Bool {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return false }
        return matches(expectation, in: image)
    }

    func matches(_ expectation: MinecraftPixelExpectation, in image: CGImage) -> Bool {
        switch expectation {
        case .redstonePickaxeOutput:
            return orientations.contains { orientation in
                guard let orientedImage = orientedImage(image, orientation: orientation) else { return false }
                return redPixelCount(
                    in: orientedImage,
                    xRange: 0.67...0.73,
                    yRange: 0.65...0.76
                ) >= 20
            }
        case .redCluster(let xRange, let yRange, let minimumCount):
            return redPixelCount(in: image, xRange: xRange, yRange: yRange) >= minimumCount
        }
    }

    private func orientedImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let ciImage = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation.rawValue))
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    private func redPixelCount(in image: CGImage, xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>) -> Int {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return 0 }

        let pixelXRange = Int(CGFloat(width) * xRange.lowerBound)..<Int(CGFloat(width) * xRange.upperBound)
        let pixelYRange = Int(CGFloat(height) * yRange.lowerBound)..<Int(CGFloat(height) * yRange.upperBound)
        var redPixels = 0
        for y in pixelYRange {
            for x in pixelXRange {
                let offset = ((y * width) + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                if red > 140, red > green * 2, red > blue * 2 { redPixels += 1 }
            }
        }
        return redPixels
    }
}
