import Foundation

extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func double(_ key: String) -> Double? {
        switch self[key] {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    func int(_ key: String) -> Int? {
        switch self[key] {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}

enum UsageJSON {
    static func object(from data: Data) -> [String: Any]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    static func parseISODate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    static func dateFromUnixSeconds(_ value: Double?) -> Date? {
        guard let value, value > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: value)
    }

    static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    static func limitWindow(usedPercent: Double?, resetsAt: Double?) -> LimitWindow? {
        guard let usedPercent else {
            return nil
        }
        let used = clampPercent(usedPercent)
        return LimitWindow(
            usedPercent: used,
            remainingPercent: clampPercent(100 - used),
            resetsAt: dateFromUnixSeconds(resetsAt)
        )
    }
}
