import CraftberryCore
import Foundation

/// Generates a single self-contained HTML page previewing every icon
/// `PixelArtTextureRenderer` can produce: the vanilla material catalog and every
/// generated item kind in every color. Run via `scripts/preview-icons.sh`.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let outputPath = CommandLine.arguments.count >= 2
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/icon-preview.html"

func card(label: String, data: Data) -> String {
    let base64 = data.base64EncodedString()
    return """
        <figure>
          <img src="data:image/png;base64,\(base64)" alt="\(label)">
          <figcaption>\(label)</figcaption>
        </figure>
        """
}

func titleCased(_ rawValue: String) -> String {
    var result = ""
    for character in rawValue {
        if character.isUppercase, !result.isEmpty {
            result.append(" ")
        }
        result.append(character)
    }
    return result.prefix(1).uppercased() + result.dropFirst()
}

var sections: [String] = []

// Vanilla materials: the hand-authored art swapped in for recipe ingredients.
var materialCards: [String] = []
for identifier in PixelArtTextureRenderer.supportedVanillaMaterialIdentifiers {
    guard let data = PixelArtTextureRenderer.renderVanillaMaterial(identifier: identifier, pixelScale: 4) else {
        fail("no artwork for \(identifier)")
    }
    let label = identifier.split(separator: ":").last.map(String.init) ?? identifier
    materialCards.append(card(label: titleCased(label.replacingOccurrences(of: "_", with: " ")), data: data))
}
sections.append("""
    <section>
      <h2>Vanilla Materials <span class="count">\(materialCards.count)</span></h2>
      <div class="grid">\(materialCards.joined())</div>
    </section>
    """)

// Generated item art: every kind (sword, ingot, tools, weapons) in every palette color.
for kind in VisualResourceKind.allCases {
    var colorCards: [String] = []
    for color in PixelArtColor.allCases {
        let resource = VisualResource(id: ContentID("preview"), kind: kind, color: color)
        let data = PixelArtTextureRenderer.render(resource, pixelScale: 4)
        colorCards.append(card(label: titleCased(color.rawValue), data: data))
    }
    let kindLabel = titleCased(kind.rawValue.replacingOccurrences(of: "PixelArt", with: ""))
    sections.append("""
        <section>
          <h2>\(kindLabel) <span class="count">\(colorCards.count)</span></h2>
          <div class="grid">\(colorCards.joined())</div>
        </section>
        """)
}

let html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>Craftberry Icon Preview</title>
    <style>
      :root { color-scheme: dark; }
      body { margin: 0; padding: 32px; background: #14161c; color: #e8e8ec; font: 15px -apple-system, sans-serif; }
      h1 { font-size: 22px; margin: 0 0 24px; }
      h2 { font-size: 15px; font-weight: 600; color: #a9adb8; text-transform: uppercase; letter-spacing: 0.04em; margin: 36px 0 12px; }
      .count { color: #6b6f7a; font-weight: 400; text-transform: none; letter-spacing: normal; }
      .grid { display: flex; flex-wrap: wrap; gap: 10px; }
      figure { margin: 0; width: 96px; padding: 10px; background: #1d2027; border-radius: 10px; text-align: center; }
      figure img { width: 64px; height: 64px; image-rendering: pixelated; }
      figcaption { margin-top: 6px; font-size: 11px; color: #c3c6cf; word-break: break-word; }
    </style>
    </head>
    <body>
    <h1>Craftberry Icon Preview</h1>
    \(sections.joined())
    </body>
    </html>
    """

do {
    try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Wrote \(outputPath)")
} catch {
    fail("failed to write \(outputPath): \(error)")
}
