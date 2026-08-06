import XCTest

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
                minecraft.keys[identifier].tap()
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
        let toSymbolsOrNumbers = Event.coordinate(0.1435, 0.8117)
        let toLetters = Event.coordinate(0.131, 0.9004)
        let symbolsPageCoordinates: [Character: Event] = [
            "^": .coordinate(0.6225, 0.630),
            "~": .coordinate(0.376, 0.7165)
        ]

        var events: [Event] = []
        func switchTo(_ page: KeyboardPage) {
            guard page != currentPage else { return }
            switch (currentPage, page) {
            case (.letters, .numbers):
                events.append(.key("numbers"))
            case (.letters, .symbols):
                events.append(.key("numbers"))
                events.append(.wait(500_000))
                events.append(toSymbolsOrNumbers)
            case (.numbers, .letters), (.symbols, .letters):
                events.append(toLetters)
            case (.numbers, .symbols), (.symbols, .numbers):
                events.append(toSymbolsOrNumbers)
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
