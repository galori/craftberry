import AppKit
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: swift scripts/ocr.swift <image-path> [expected-substring]")
}

let imagePath = arguments[1]
let expectedSubstring = arguments.count >= 3 ? arguments[2] : nil

guard let image = NSImage(contentsOfFile: imagePath),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("error: could not load image at \(imagePath)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    fail("error: OCR request failed: \(error)")
}

let observations = request.results ?? []
let lines = observations.compactMap { $0.topCandidates(1).first?.string }

for line in lines {
    print(line)
}

if let expected = expectedSubstring {
    let found = lines.contains { $0.localizedCaseInsensitiveContains(expected) }
    if found {
        FileHandle.standardError.write(Data("MATCH: found \"\(expected)\"\n".utf8))
        exit(0)
    } else {
        FileHandle.standardError.write(Data("NO MATCH: \"\(expected)\" not found in recognized text\n".utf8))
        exit(1)
    }
}
