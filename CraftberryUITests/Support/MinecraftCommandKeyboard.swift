import XCTest

extension XCUIApplication {
    /// Resolves a software-keyboard key by identifier, then by label, then by known aliases.
    ///
    /// `keys[name]` matches accessibility *identifiers* only, and the keys we depend on do not
    /// expose stable identifiers across iOS versions: confirmed live on iOS 26 that the
    /// numeric-plane switch reports identifier `more` (label `numbers`, drawn as "123"), so
    /// `keys["numbers"]` silently matched nothing, left the keyboard on letters, and the following
    /// digit taps landed on whatever letter key happened to share that identifier until one had no
    /// match at all. Falling back through label and alias keeps a single calibration working on
    /// both test devices.
    func keyboardKey(_ name: String) -> XCUIElement {
        // The plane-switch keys report identifier "more" (letters <-> numbers) and "shift" (#+=)
        // regardless of which plane is showing, so only their labels distinguish them.
        let aliases = [
            "numbers": ["more", "123"],
            "letters": ["more", "ABC"],
            "symbols": ["shift", "#+="],
            "space": [" "]
        ]
        let byIdentifier = keys[name]
        var candidates = [byIdentifier, keys.matching(NSPredicate(format: "label == %@", name)).firstMatch]
        candidates += (aliases[name] ?? []).map { keys[$0] }
        return candidates.first { $0.exists } ?? byIdentifier
    }
}

struct MinecraftCommandKeyboard {
    enum Event: Equatable {
        case key(String)
        case coordinate(CGFloat, CGFloat)
        case wait(useconds_t)
    }

    func type(_ text: String, in minecraft: XCUIApplication) {
        for event in events(for: text) {
            switch event {
            case .key(let identifier):
                minecraft.keyboardKey(identifier).tap()
            case .coordinate(let x, let y):
                minecraft.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            case .wait(let microseconds):
                usleep(microseconds)
            }
        }
    }

    func events(for text: String) -> [Event] {
        enum KeyboardPage { case letters, numbers, symbols }
        var currentPage = KeyboardPage.letters
        // Plane switches go through key elements, not coordinates. The plane-switch key sits in the
        // same physical spot on every plane but its size and the keyboard's overall height vary by
        // device, and a fixed coordinate was confirmed live on iPhone 13 Pro to miss the ABC key and
        // dismiss the keyboard outright. Its identifier stays "more" across planes while only its
        // label changes ("numbers" / "letters" / "symbols"), which `keyboardKey` resolves.
        let toNumbers = Event.key("numbers")
        let toLetters = Event.key("letters")
        // The #+= key is the one plane switch with no usable accessibility identity: confirmed live
        // that the numbers plane exposes only 'more'/'letters', 'delete' and 'space' by identifier,
        // and every other key by label alone, with no entry for #+= in the hierarchy at all. It
        // occupies the shift key's slot, measured here from a device screenshot.
        let toSymbols = Event.coordinate(0.1435, 0.8117)
        let symbolsPageCoordinates: [Character: Event] = [
            "^": .coordinate(0.6225, 0.630),
            "~": .coordinate(0.376, 0.7165)
        ]

        var events: [Event] = []
        func switchTo(_ page: KeyboardPage) {
            guard page != currentPage else { return }
            switch (currentPage, page) {
            case (.letters, .numbers):
                events.append(toNumbers)
            case (.letters, .symbols):
                events.append(toNumbers)
                events.append(.wait(500_000))
                events.append(toSymbols)
            case (.numbers, .letters), (.symbols, .letters):
                events.append(toLetters)
            case (.numbers, .symbols):
                events.append(toSymbols)
            case (.symbols, .numbers):
                events.append(toNumbers)
            default:
                break
            }
            currentPage = page
            events.append(.wait(300_000))
        }

        for character in text {
            if character == " " {
                events.append(.key("space"))
                currentPage = .letters
            } else if let symbolCoordinate = symbolsPageCoordinates[character] {
                switchTo(.symbols)
                events.append(symbolCoordinate)
                currentPage = .letters
                events.append(.wait(300_000))
            } else if character == "_" {
                switchTo(.symbols)
                events.append(.key("_"))
            } else if character.isLetter {
                switchTo(.letters)
                events.append(.key(String(character)))
            } else {
                switchTo(.numbers)
                events.append(.key(String(character)))
            }
        }
        return events
    }
}
