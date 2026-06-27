import Foundation

public enum CodexTokenCountParser {
    public static func parseLine(_ line: String) -> UsageSnapshot? {
        guard line.contains("\"token_count\"") else {
            return nil
        }
        guard
            let data = line.data(using: .utf8),
            let root = UsageJSON.object(from: data),
            root.string("type") == "event_msg",
            let payload = root.dictionary("payload"),
            payload.string("type") == "token_count"
        else {
            return nil
        }

        let rateLimits = payload.dictionary("rate_limits")
        let primary = rateLimits?.dictionary("primary")
        let secondary = rateLimits?.dictionary("secondary")
        let fiveHour = UsageJSON.limitWindow(
            usedPercent: primary?.double("used_percent"),
            resetsAt: primary?.double("resets_at")
        )
        let sevenDay = UsageJSON.limitWindow(
            usedPercent: secondary?.double("used_percent"),
            resetsAt: secondary?.double("resets_at")
        )

        let info = payload.dictionary("info")
        let totalUsage = info?.dictionary("total_token_usage")
        let tokens = totalUsage?.int("total_tokens")
        let contextWindow = info?.double("model_context_window")
        let context = contextUsage(tokens: tokens, contextWindow: contextWindow)

        return UsageSnapshot(
            provider: .codex,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            context: context,
            updatedAt: UsageJSON.parseISODate(root.string("timestamp")) ?? Date(),
            source: .codexJSONL
        )
    }

    private static func contextUsage(tokens: Int?, contextWindow: Double?) -> ContextUsage? {
        guard tokens != nil || contextWindow != nil else {
            return nil
        }
        guard let tokens, let contextWindow, contextWindow > 0 else {
            return ContextUsage(usedPercent: nil, remainingPercent: nil, tokens: tokens)
        }
        let used = UsageJSON.clampPercent((Double(tokens) / contextWindow) * 100)
        return ContextUsage(
            usedPercent: used,
            remainingPercent: UsageJSON.clampPercent(100 - used),
            tokens: tokens
        )
    }
}

public enum ClaudeStatusLineParser {
    public static func parseData(_ data: Data) -> UsageSnapshot? {
        guard let root = UsageJSON.object(from: data) else {
            return nil
        }

        if root.string("provider") == UsageProvider.claude.rawValue {
            return parseNormalized(root)
        }
        if root.dictionary("five_hour") != nil || root.dictionary("seven_day") != nil {
            return parseOAuthUsage(root)
        }

        return parseStatusLineInput(root)
    }

    private static func parseNormalized(_ root: [String: Any]) -> UsageSnapshot? {
        let fiveHour = normalizedWindow(root.dictionary("fiveHour"))
        let sevenDay = normalizedWindow(root.dictionary("sevenDay"))
        let context = normalizedContext(root.dictionary("context"))

        return UsageSnapshot(
            provider: .claude,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            context: context,
            updatedAt: UsageJSON.parseISODate(root.string("updatedAt")) ?? Date(),
            source: .claudeStatusLine
        )
    }

    private static func parseOAuthUsage(_ root: [String: Any]) -> UsageSnapshot? {
        let fiveHour = oauthWindow(root.dictionary("five_hour"))
        let sevenDay = oauthWindow(root.dictionary("seven_day"))

        guard fiveHour != nil || sevenDay != nil else {
            return nil
        }

        return UsageSnapshot(
            provider: .claude,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            context: nil,
            updatedAt: Date(),
            source: .claudeStatusLine
        )
    }

    private static func parseStatusLineInput(_ root: [String: Any]) -> UsageSnapshot? {
        let rateLimits = root.dictionary("rate_limits")
        let fiveHourRaw = rateLimits?.dictionary("five_hour")
        let sevenDayRaw = rateLimits?.dictionary("seven_day")
        let fiveHour = UsageJSON.limitWindow(
            usedPercent: fiveHourRaw?.double("used_percentage"),
            resetsAt: fiveHourRaw?.double("resets_at")
        )
        let sevenDay = UsageJSON.limitWindow(
            usedPercent: sevenDayRaw?.double("used_percentage"),
            resetsAt: sevenDayRaw?.double("resets_at")
        )

        let contextRaw = root.dictionary("context_window")
        let inputTokens = contextRaw?.int("total_input_tokens") ?? 0
        let outputTokens = contextRaw?.int("total_output_tokens") ?? 0
        let tokenTotal = inputTokens + outputTokens
        let context = ContextUsage(
            usedPercent: contextRaw?.double("used_percentage"),
            remainingPercent: contextRaw?.double("remaining_percentage"),
            tokens: tokenTotal > 0 ? tokenTotal : nil
        )

        guard fiveHour != nil || sevenDay != nil || context.tokens != nil else {
            return nil
        }

        return UsageSnapshot(
            provider: .claude,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            context: context,
            updatedAt: Date(),
            source: .claudeStatusLine
        )
    }

    private static func normalizedWindow(_ raw: [String: Any]?) -> LimitWindow? {
        guard let raw else {
            return nil
        }
        let used = raw.double("usedPercent")
        let remaining = raw.double("remainingPercent")
        let reset = raw.double("resetsAt")
        if let used {
            return LimitWindow(
                usedPercent: UsageJSON.clampPercent(used),
                remainingPercent: UsageJSON.clampPercent(remaining ?? (100 - used)),
                resetsAt: UsageJSON.dateFromUnixSeconds(reset)
            )
        }
        if let remaining {
            return LimitWindow(
                usedPercent: UsageJSON.clampPercent(100 - remaining),
                remainingPercent: UsageJSON.clampPercent(remaining),
                resetsAt: UsageJSON.dateFromUnixSeconds(reset)
            )
        }
        return nil
    }

    private static func oauthWindow(_ raw: [String: Any]?) -> LimitWindow? {
        guard
            let raw,
            let usedPercent = raw.double("utilization") ?? raw.double("used_percentage") ?? raw.double("used_percent")
        else {
            return nil
        }
        let used = UsageJSON.clampPercent(usedPercent)
        return LimitWindow(
            usedPercent: used,
            remainingPercent: UsageJSON.clampPercent(100 - used),
            resetsAt: raw.string("resets_at").flatMap(UsageJSON.parseISODate)
                ?? UsageJSON.dateFromUnixSeconds(raw.double("resets_at"))
        )
    }

    private static func normalizedContext(_ raw: [String: Any]?) -> ContextUsage? {
        guard let raw else {
            return nil
        }
        return ContextUsage(
            usedPercent: raw.double("usedPercent"),
            remainingPercent: raw.double("remainingPercent"),
            tokens: raw.int("tokens")
        )
    }
}
