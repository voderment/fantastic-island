import Foundation

func jsonObject(for line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    return object
}

func parseTimestamp(_ value: String?) -> Date? {
    guard let value else {
        return nil
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

func parseFlexibleDate(_ value: Any?) -> Date? {
    switch value {
    case let value as Date:
        return value
    case let value as Int:
        return parseEpochTimestamp(value)
    case let value as Double:
        return parseEpochTimestamp(Int(value.rounded()))
    case let value as NSNumber:
        return parseEpochTimestamp(value.intValue)
    case let value as String:
        if let intValue = Int(value) {
            return parseEpochTimestamp(intValue)
        }

        if let fullPrecision = parseTimestamp(value) {
            return fullPrecision
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    default:
        return nil
    }
}

func clipped(_ value: String?, limit: Int = 120) -> String? {
    guard let value else {
        return nil
    }

    let collapsed = value
        .replacingOccurrences(of: "\n", with: " ")
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
    guard !collapsed.isEmpty else {
        return nil
    }

    guard collapsed.count > limit else {
        return collapsed
    }

    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
    return "\(collapsed[..<endIndex])…"
}

func normalizedMonitoringKey(_ key: String) -> String {
    key
        .lowercased()
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: " ", with: "")
}

func firstMatchingValue(in value: Any, keys: Set<String>) -> Any? {
    if let dictionary = value as? [String: Any] {
        for (key, nestedValue) in dictionary {
            if keys.contains(normalizedMonitoringKey(key)) {
                return nestedValue
            }
        }

        for nestedValue in dictionary.values {
            if let match = firstMatchingValue(in: nestedValue, keys: keys) {
                return match
            }
        }

        return nil
    }

    if let array = value as? [Any] {
        for nestedValue in array {
            if let match = firstMatchingValue(in: nestedValue, keys: keys) {
                return match
            }
        }
    }

    return nil
}

func firstStringValue(in value: Any, keys: Set<String>) -> String? {
    guard let nested = firstMatchingValue(in: value, keys: keys) else {
        return nil
    }

    return stringValue(from: nested)
}

func firstIntValue(in value: Any, keys: Set<String>) -> Int? {
    guard let nested = firstMatchingValue(in: value, keys: keys) else {
        return nil
    }

    switch nested {
    case let intValue as Int:
        return intValue
    case let doubleValue as Double:
        return Int(doubleValue.rounded())
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = Int(trimmed) {
            return intValue
        }
        if let doubleValue = Double(trimmed) {
            return Int(doubleValue.rounded())
        }
        return nil
    default:
        return nil
    }
}

func firstBoolValue(in value: Any, keys: Set<String>) -> Bool? {
    guard let nested = firstMatchingValue(in: value, keys: keys) else {
        return nil
    }

    return boolValue(from: nested)
}

func stringValue(from value: Any?) -> String? {
    guard let value else {
        return nil
    }

    switch value {
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let number as NSNumber:
        return number.stringValue
    case let date as Date:
        return ISO8601DateFormatter().string(from: date)
    case let array as [Any]:
        let fragments = array.compactMap { stringValue(from: $0) }
        let joined = fragments.joined(separator: " ")
        return clipped(joined, limit: 160)
    case let dictionary as [String: Any]:
        for key in ["text", "content", "message", "output", "delta", "value", "summary", "assistant_summary", "response"] {
            if let nested = dictionary[key], let string = stringValue(from: nested) {
                return string
            }
        }

        for nested in dictionary.values {
            if let string = stringValue(from: nested) {
                return string
            }
        }

        return nil
    default:
        return clipped(String(describing: value), limit: 160)
    }
}

func boolValue(from value: Any?) -> Bool? {
    guard let value else {
        return nil
    }

    switch value {
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number.boolValue
    case let string as String:
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    default:
        return nil
    }
}

func intValue(from value: Any?) -> Int? {
    guard let value else {
        return nil
    }

    switch value {
    case let intValue as Int:
        return intValue
    case let doubleValue as Double:
        return Int(doubleValue.rounded())
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = Int(trimmed) {
            return intValue
        }
        if let doubleValue = Double(trimmed) {
            return Int(doubleValue.rounded())
        }
        return nil
    default:
        return nil
    }
}

func joinedText(from value: Any?) -> String? {
    guard let value else {
        return nil
    }

    switch value {
    case let string as String:
        return clipped(string, limit: 160)
    case let array as [Any]:
        let fragments = array.compactMap { joinedText(from: $0) }
        let combined = fragments.joined(separator: " ")
        return clipped(combined, limit: 160)
    case let dictionary as [String: Any]:
        for key in ["text", "content", "message", "output", "delta", "value", "summary", "assistant_summary", "response", "prompt"] {
            if let nested = dictionary[key], let text = joinedText(from: nested) {
                return text
            }
        }

        for nested in dictionary.values {
            if let text = joinedText(from: nested) {
                return text
            }
        }

        return nil
    default:
        return clipped(String(describing: value), limit: 160)
    }
}

func joinedTextRaw(from value: Any?) -> String? {
    guard let value else {
        return nil
    }

    switch value {
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let array as [Any]:
        let fragments = array.compactMap { joinedTextRaw(from: $0) }
        let combined = fragments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    case let dictionary as [String: Any]:
        for key in ["text", "content", "message", "output", "delta", "value", "summary", "assistant_summary", "response", "prompt"] {
            if let nested = dictionary[key], let text = joinedTextRaw(from: nested) {
                return text
            }
        }

        for nested in dictionary.values {
            if let text = joinedTextRaw(from: nested) {
                return text
            }
        }

        return nil
    default:
        let rendered = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? nil : rendered
    }
}

private func parseEpochTimestamp(_ rawValue: Int) -> Date? {
    guard rawValue > 0 else {
        return nil
    }

    let seconds = rawValue > 9_999_999_999 ? Double(rawValue) / 1_000.0 : Double(rawValue)
    return Date(timeIntervalSince1970: seconds)
}
