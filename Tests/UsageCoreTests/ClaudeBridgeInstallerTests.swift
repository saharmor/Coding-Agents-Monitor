import Foundation
import Testing
@testable import UsageCore

@Test func installerBacksUpSettingsAndWrapsExistingStatusLine() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("usage-monitor-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let claudeDir = root.appendingPathComponent(".claude")
    let installRoot = root.appendingPathComponent(".usage-monitor")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)

    let settingsPath = claudeDir.appendingPathComponent("settings.json")
    let bridgeSource = root.appendingPathComponent("bridge.mjs")
    try #"{"statusLine":{"type":"command","command":"echo old"},"model":"opus"}"#
        .data(using: .utf8)!
        .write(to: settingsPath)
    try "console.log('bridge')\n".data(using: .utf8)!.write(to: bridgeSource)

    let installer = ClaudeBridgeInstaller(
        settingsPath: settingsPath,
        bridgeSourcePath: bridgeSource,
        installRoot: installRoot,
        now: { Date(timeIntervalSince1970: 1_782_564_969) }
    )
    let result = try installer.install()

    #expect(result.changedSettings)
    #expect(result.backupPath != nil)
    #expect(FileManager.default.fileExists(atPath: result.bridgePath))
    #expect(FileManager.default.fileExists(atPath: result.metadataPath))

    let data = try Data(contentsOf: settingsPath)
    let settings = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let statusLine = try #require(settings["statusLine"] as? [String: Any])
    let command = try #require(statusLine["command"] as? String)
    #expect(command.contains("claude-statusline-bridge.mjs"))
    #expect(command.contains("--existing-base64"))
    #expect(settings["model"] as? String == "opus")
}

@Test func installerIsIdempotentWhenBridgeAlreadyConfigured() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("usage-monitor-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let claudeDir = root.appendingPathComponent(".claude")
    let installRoot = root.appendingPathComponent(".usage-monitor")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)

    let settingsPath = claudeDir.appendingPathComponent("settings.json")
    let bridgeSource = root.appendingPathComponent("bridge.mjs")
    try #"{"statusLine":{"type":"command","command":"/usr/bin/env node '/tmp/claude-statusline-bridge.mjs'"}}"#
        .data(using: .utf8)!
        .write(to: settingsPath)
    try "console.log('bridge')\n".data(using: .utf8)!.write(to: bridgeSource)

    let installer = ClaudeBridgeInstaller(
        settingsPath: settingsPath,
        bridgeSourcePath: bridgeSource,
        installRoot: installRoot
    )
    let result = try installer.install()

    #expect(!result.changedSettings)
    #expect(result.backupPath == nil)
}
