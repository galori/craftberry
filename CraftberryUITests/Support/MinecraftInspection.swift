import ImageIO
import Vision
import XCTest

struct MinecraftOCRInspector {
    let orientations: [CGImagePropertyOrientation] = [.left, .up]

    func recognizedText() -> String {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else {
            XCTFail("Could not create a CGImage for Minecraft OCR")
            return ""
        }
        return recognizedText(in: image)
    }

    func recognizedText(in image: CGImage) -> String {
        let recognizedLines: [String] = orientations.flatMap { orientation -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            } catch {
                XCTFail("Minecraft OCR failed: \(error)")
                return [String]()
            }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        return recognizedLines.joined(separator: "\n")
    }

    func waitForRecognizedText(_ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if recognizedText().localizedCaseInsensitiveContains(expected) {
                return true
            }
            usleep(500_000)
        } while Date() < deadline
        return false
    }
}

struct MinecraftPixelInspector {
    func matches(_ expectation: MinecraftPixelExpectation) -> Bool {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return false }
        return matches(expectation, in: image)
    }

    func matches(_ expectation: MinecraftPixelExpectation, in image: CGImage) -> Bool {
        switch expectation {
        case .redstonePickaxeOutput:
            return redPixelCount(
                in: image,
                xRange: 0.18...0.31,
                yRange: 0.67...0.75
            ) >= 20
        case .redCluster(let xRange, let yRange, let minimumCount):
            return redPixelCount(in: image, xRange: xRange, yRange: yRange) >= minimumCount
        }
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
