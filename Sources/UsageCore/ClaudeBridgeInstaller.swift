import Foundation

public struct ClaudeBridgeInstallResult: Equatable, Sendable {
    public var changedSettings: Bool
    public var backupPath: String?
    public var bridgePath: String
    public var metadataPath: String
}

public enum ClaudeBridgeInstallError: Error, LocalizedError {
    case missingBridgeSource(String)
    case invalidSettingsJSON(String)
    case unsupportedSettingsRoot(String)

    public var errorDescription: String? {
        switch self {
        case .missingBridgeSource(let path):
            return "Claude bridge source was not found at \(path)"
        case .invalidSettingsJSON(let path):
            return "Claude settings are not valid JSON: \(path)"
        case .unsupportedSettingsRoot(let path):
            return "Claude settings must be a JSON object: \(path)"
        }
    }
}

public struct ClaudeBridgeInstaller: Sendable {
    public var settingsPath: URL
    public var bridgeSourcePath: URL
    public var installRoot: URL
    public var now: @Sendable () -> Date

    public init(
        settingsPath: URL,
        bridgeSourcePath: URL,
        installRoot: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsPath = settingsPath
        self.bridgeSourcePath = bridgeSourcePath
        self.installRoot = installRoot
        self.now = now
    }

    public func install() throws -> ClaudeBridgeInstallResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: bridgeSourcePath.path) else {
            throw ClaudeBridgeInstallError.missingBridgeSource(bridgeSourcePath.path)
        }

        try fileManager.createDirectory(
            at: installRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let bridgeDestination = installRoot.appendingPathComponent("claude-statusline-bridge.mjs")
        if fileManager.fileExists(atPath: bridgeDestination.path) {
            try fileManager.removeItem(at: bridgeDestination)
        }
        try fileManager.copyItem(at: bridgeSourcePath, to: bridgeDestination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgeDestination.path)

        var settings = try readSettings()
        let previousStatusLine = settings["statusLine"] as? [String: Any]
        let previousCommand = previousStatusLine?["command"] as? String
        let bridgeCommand = makeBridgeCommand(bridgePath: bridgeDestination.path, previousCommand: previousCommand)

        var changedSettings = false
        if previousCommand?.contains("claude-statusline-bridge.mjs") != true {
            var nextStatusLine = previousStatusLine ?? [:]
            nextStatusLine["type"] = "command"
            nextStatusLine["command"] = bridgeCommand
            settings["statusLine"] = nextStatusLine
            changedSettings = true
        }

        let metadataURL = installRoot.appendingPathComponent("claude-settings-install.json")
        let backupPath = changedSettings ? try backupSettingsIfPresent() : nil
        if changedSettings {
            try writeSettings(settings)
        }
        try writeMetadata(
            metadataURL: metadataURL,
            bridgePath: bridgeDestination.path,
            settingsPath: settingsPath.path,
            backupPath: backupPath,
            previousStatusLine: previousStatusLine
        )

        return ClaudeBridgeInstallResult(
            changedSettings: changedSettings,
            backupPath: backupPath,
            bridgePath: bridgeDestination.path,
            metadataPath: metadataURL.path
        )
    }

    private func readSettings() throws -> [String: Any] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: settingsPath.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsPath)
        guard !data.isEmpty else {
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw ClaudeBridgeInstallError.invalidSettingsJSON(settingsPath.path)
        }
        guard let dictionary = object as? [String: Any] else {
            throw ClaudeBridgeInstallError.unsupportedSettingsRoot(settingsPath.path)
        }
        return dictionary
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: settingsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try atomicWrite(data: data, to: settingsPath)
    }

    private func backupSettingsIfPresent() throws -> String? {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return nil
        }
        let backupName = "settings.json.backup-usage-monitor-\(backupTimestamp())"
        let backupURL = settingsPath.deletingLastPathComponent().appendingPathComponent(backupName)
        try FileManager.default.copyItem(at: settingsPath, to: backupURL)
        return backupURL.path
    }

    private func writeMetadata(
        metadataURL: URL,
        bridgePath: String,
        settingsPath: String,
        backupPath: String?,
        previousStatusLine: [String: Any]?
    ) throws {
        var metadata: [String: Any] = [
            "installedAt": ISO8601DateFormatter().string(from: now()),
            "bridgePath": bridgePath,
            "settingsPath": settingsPath
        ]
        if let backupPath {
            metadata["backupPath"] = backupPath
        }
        if let previousStatusLine {
            metadata["previousStatusLine"] = previousStatusLine
        } else {
            metadata["previousStatusLine"] = NSNull()
        }
        let data = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try atomicWrite(data: data, to: metadataURL)
    }

    private func atomicWrite(data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: [.atomic])
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func makeBridgeCommand(bridgePath: String, previousCommand: String?) -> String {
        let quotedBridge = shellQuote(bridgePath)
        guard
            let previousCommand,
            !previousCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !previousCommand.contains("claude-statusline-bridge.mjs")
        else {
            return "/usr/bin/env node \(quotedBridge)"
        }

        let encoded = Data(previousCommand.utf8).base64EncodedString()
        return "/usr/bin/env node \(quotedBridge) --existing-base64 \(shellQuote(encoded))"
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: now())
    }
}
