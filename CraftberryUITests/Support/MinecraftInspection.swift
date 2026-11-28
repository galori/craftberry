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

    func waitForRecognizedTextCenter(_ expected: String, timeout: TimeInterval) -> CGPoint? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let image = XCUIScreen.main.screenshot().image.cgImage,
               let center = recognizedTextCenter(expected, in: image) {
                return center
            }
            usleep(150_000)
        } while Date() < deadline
        return nil
    }

    /// Locates a text row only when its title and context label appear near each
    /// other. Imported-world rows can render the mode on a separate line, so a
    /// full concatenated-string match would either miss the row or match a
    /// same-named world in another mode.
    func waitForRecognizedTextRowCenter(title: String, context: String, timeout: TimeInterval) -> CGPoint? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            guard let image = XCUIScreen.main.screenshot().image.cgImage else {
                usleep(150_000)
                continue
            }
            for orientation in orientations {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
                } catch {
                    XCTFail("Minecraft OCR failed: \(error)")
                    return nil
                }
                let candidates = (request.results ?? []).compactMap { observation -> (text: String, boundingBox: CGRect)? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return (text, observation.boundingBox)
                }
                if let box = Self.matchingRowBoundingBox(title: title, context: context, among: candidates) {
                    return CGPoint(x: box.midX, y: 1 - box.midY)
                }
            }
            usleep(150_000)
        } while Date() < deadline
        return nil
    }

    static func matchingRowBoundingBox(
        title: String,
        context: String,
        among candidates: [(text: String, boundingBox: CGRect)]
    ) -> CGRect? {
        let titleCandidates = candidates.filter { $0.text.localizedCaseInsensitiveContains(title) }
        let contextCandidates = candidates.filter { candidate in
            candidate.text
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .contains { $0.localizedCaseInsensitiveCompare(context) == .orderedSame }
        }

        return titleCandidates
            .flatMap { titleCandidate in
                contextCandidates.compactMap { contextCandidate -> (box: CGRect, distance: CGFloat)? in
                    let verticalDistance = abs(titleCandidate.boundingBox.midY - contextCandidate.boundingBox.midY)
                    let horizontalDistance = abs(titleCandidate.boundingBox.midX - contextCandidate.boundingBox.midX)
                    guard verticalDistance <= 0.12, horizontalDistance <= 0.45 else { return nil }
                    return (titleCandidate.boundingBox, verticalDistance + horizontalDistance * 0.1)
                }
            }
            .min { $0.distance < $1.distance }?
            .box
    }

    private func recognizedTextCenter(_ expected: String, in image: CGImage) -> CGPoint? {
        for orientation in orientations {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            } catch {
                XCTFail("Minecraft OCR failed: \(error)")
                return nil
            }
            let candidates = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return (text, observation.boundingBox)
            }
            if let boundingBox = Self.bottommostBoundingBox(matching: expected, among: candidates) {
                return CGPoint(x: boundingBox.midX, y: 1 - boundingBox.midY)
            }
        }
        return nil
    }

    static func bottommostBoundingBox(
        matching expected: String,
        among candidates: [(text: String, boundingBox: CGRect)]
    ) -> CGRect? {
        candidates
            .filter { $0.text.localizedCaseInsensitiveContains(expected) }
            .max { first, second in
                (1 - first.boundingBox.midY) < (1 - second.boundingBox.midY)
            }?
            .boundingBox
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
    /// raw buffer before sampling calibrated interface coordinates. Only the two landscape
    /// orientations are plausible in-game; the portrait views map calibrated regions onto
    /// unrelated transposed patches (live: hotbar red leaking into an empty-cell region),
    /// which would false-pass absence checks.
    private let orientations: [CGImagePropertyOrientation] = [.left, .right]

    func matches(_ expectation: MinecraftPixelExpectation) -> Bool {
        guard let count = count(expectation) else { return false }
        return decide(count: count, for: expectation)
    }

    /// The matched-pixel count for logging what a pixel step actually saw. Nil
    /// when no screenshot could be captured. Live screenshots honor their
    /// own orientation tag (a single deterministic view); only tagless
    /// synthetic images fall back to trying both landscape orientations.
    /// Max-across-rotations must never feed absence checks: a transposed
    /// view of red-hotbar UI reads hundreds of red pixels for an empty
    /// slot and would false-fail every absence (confirmed live).
    func count(_ expectation: MinecraftPixelExpectation) -> Int? {
        let screenshot = XCUIScreen.main.screenshot().image
        guard let image = screenshot.cgImage else { return nil }
        if let orientation = pixelOrientation(for: screenshot.imageOrientation) {
            guard let oriented = orientedImage(image, orientation: orientation) else { return nil }
            let (xRange, yRange) = region(for: expectation)
            return pixelCount(
                in: oriented,
                xRange: xRange,
                yRange: yRange,
                cyan: isCyan(expectation),
                itemContrast: isItemContrast(expectation),
                brown: isBrown(expectation)
            )
        }
        return count(expectation, in: image)
    }

    func count(_ expectation: MinecraftPixelExpectation, in image: CGImage) -> Int {
        let (xRange, yRange) = region(for: expectation)
        let cyan = isCyan(expectation)
        let brown = isBrown(expectation)
        return orientations.compactMap { orientation in
            orientedImage(image, orientation: orientation).map {
                pixelCount(
                    in: $0,
                    xRange: xRange,
                    yRange: yRange,
                    cyan: cyan,
                    itemContrast: isItemContrast(expectation),
                    brown: brown
                )
            }
        }.max() ?? 0
    }

    private func isCyan(_ expectation: MinecraftPixelExpectation) -> Bool {
        if case .cyanCluster = expectation { return true }
        return false
    }

    private func isItemContrast(_ expectation: MinecraftPixelExpectation) -> Bool {
        switch expectation {
        case .itemContrastCluster, .itemContrastAbsent:
            true
        default:
            false
        }
    }

    private func isBrown(_ expectation: MinecraftPixelExpectation) -> Bool {
        switch expectation {
        case .brownCluster, .brownAbsent:
            true
        default:
            false
        }
    }

    func matches(_ expectation: MinecraftPixelExpectation, in image: CGImage) -> Bool {
        decide(count: count(expectation, in: image), for: expectation)
    }

    private func decide(count: Int, for expectation: MinecraftPixelExpectation) -> Bool {
        switch expectation {
        case .redstonePickaxeOutput, .redCluster, .cyanCluster, .itemContrastCluster, .brownCluster:
            return count >= minimumCount(for: expectation)
        case .redAbsent, .itemContrastAbsent, .brownAbsent:
            return count <= maximumCount(for: expectation)
        }
    }

    private func pixelOrientation(for imageOrientation: UIImage.Orientation) -> CGImagePropertyOrientation? {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored: nil
        @unknown default: nil
        }
    }

    private func region(for expectation: MinecraftPixelExpectation) -> (ClosedRange<CGFloat>, ClosedRange<CGFloat>) {
        switch expectation {
        case .redstonePickaxeOutput:
            return (0.67...0.73, 0.65...0.76)
        case .redCluster(let xRange, let yRange, _):
            return (xRange, yRange)
        case .redAbsent(let xRange, let yRange, _):
            return (xRange, yRange)
        case .cyanCluster(let xRange, let yRange, _):
            return (xRange, yRange)
        case .itemContrastCluster(let xRange, let yRange, _):
            return (xRange, yRange)
        case .itemContrastAbsent(let xRange, let yRange, _):
            return (xRange, yRange)
        case .brownCluster(let xRange, let yRange, _):
            return (xRange, yRange)
        case .brownAbsent(let xRange, let yRange, _):
            return (xRange, yRange)
        }
    }

    func minimumCount(for expectation: MinecraftPixelExpectation) -> Int {
        switch expectation {
        case .redstonePickaxeOutput:
            return 20
        case .redCluster(_, _, let minimumCount):
            return minimumCount
        case .cyanCluster(_, _, let minimumCount):
            return minimumCount
        case .itemContrastCluster(_, _, let minimumCount):
            return minimumCount
        case .brownCluster(_, _, let minimumCount):
            return minimumCount
        case .redAbsent, .itemContrastAbsent, .brownAbsent:
            return 0
        }
    }

    func maximumCount(for expectation: MinecraftPixelExpectation) -> Int {
        switch expectation {
        case .redstonePickaxeOutput:
            return Int.max
        case .redCluster:
            return Int.max
        case .cyanCluster:
            return Int.max
        case .itemContrastCluster:
            return Int.max
        case .brownCluster:
            return Int.max
        case .redAbsent(_, _, let maximumCount), .itemContrastAbsent(_, _, let maximumCount), .brownAbsent(_, _, let maximumCount):
            return maximumCount
        }
    }

    private func orientedImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let ciImage = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation.rawValue))
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    private func redPixelCount(in image: CGImage, xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>) -> Int {
        pixelCount(in: image, xRange: xRange, yRange: yRange, cyan: false, itemContrast: false, brown: false)
    }

    private func pixelCount(
        in image: CGImage,
        xRange: ClosedRange<CGFloat>,
        yRange: ClosedRange<CGFloat>,
        cyan: Bool,
        itemContrast: Bool,
        brown: Bool
    ) -> Int {
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
        var matchedPixels = 0
        for y in pixelYRange {
            for x in pixelXRange {
                let offset = ((y * width) + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                if itemContrast {
                    let brightest = max(red, green, blue)
                    let darkest = min(red, green, blue)
                    if brightest > 205 || darkest < 72 { matchedPixels += 1 }
                } else if brown {
                    // Hunger drumstick fill has substantial green; pure-red
                    // health hearts must not be counted as hunger pixels.
                    if red > 110, green * 3 > red, green < red, blue * 2 < red { matchedPixels += 1 }
                } else if cyan {
                    if blue > 140, blue > red * 2, green > red * 2 { matchedPixels += 1 }
                } else if red > 140, red > green * 2, red > blue * 2 {
                    matchedPixels += 1
                }
            }
        }
        return matchedPixels
    }
}
