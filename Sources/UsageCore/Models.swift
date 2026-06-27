import Foundation

public enum UsageProvider: String, Codable, Equatable, Sendable {
    case codex
    case claude
}

public enum UsageSource: String, Codable, Equatable, Sendable {
    case codexJSONL = "codex-jsonl"
    case claudeStatusLine = "claude-statusline"
}

public struct LimitWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetsAt: Date?

    public init(usedPercent: Double, remainingPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct ContextUsage: Codable, Equatable, Sendable {
    public var usedPercent: Double?
    public var remainingPercent: Double?
    public var tokens: Int?

    public init(usedPercent: Double?, remainingPercent: Double?, tokens: Int?) {
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.tokens = tokens
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var provider: UsageProvider
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var context: ContextUsage?
    public var updatedAt: Date
    public var source: UsageSource

    public init(
        provider: UsageProvider,
        fiveHour: LimitWindow?,
        sevenDay: LimitWindow?,
        context: ContextUsage?,
        updatedAt: Date,
        source: UsageSource
    ) {
        self.provider = provider
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.context = context
        self.updatedAt = updatedAt
        self.source = source
    }
}
