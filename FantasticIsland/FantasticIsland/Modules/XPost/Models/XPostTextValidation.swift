import Foundation

struct XPostTextValidation: Equatable {
    let trimmedText: String
    let weightedLength: Int
    let containsURL: Bool

    var isEmpty: Bool { trimmedText.isEmpty }
    var isOverLimit: Bool { weightedLength > XPostTextValidator.maxWeightedLength }
    var isValid: Bool { !isEmpty && !isOverLimit && !containsURL }
}

enum XPostTextValidator {
    static let maxWeightedLength = 280

    static func validate(_ text: String) -> XPostTextValidation {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return XPostTextValidation(
            trimmedText: trimmedText,
            weightedLength: weightedLength(for: trimmedText),
            containsURL: containsURL(in: trimmedText)
        )
    }

    static func weightedLength(for text: String) -> Int {
        text.reduce(0) { total, character in
            total + (character.unicodeScalars.allSatisfy(\.isASCII) ? 1 : 2)
        }
    }

    static func containsURL(in text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           detector.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }

        return text.range(
            of: #"(?i)(?:^|\s)(?:https?://|www\.)\S+"#,
            options: .regularExpression
        ) != nil
    }
}
