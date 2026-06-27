import Foundation
import UsageCore

final class CodexUsageCollector: @unchecked Sendable {
    private let root: URL
    private let queue = DispatchQueue(label: "usage-monitor.codex")
    private let onSnapshot: (UsageSnapshot) -> Void
    private var offsets: [URL: UInt64] = [:]
    private var watcher: FSEventWatcher?
    private var scanScheduled = false

    init(root: URL, onSnapshot: @escaping (UsageSnapshot) -> Void) {
        self.root = root
        self.onSnapshot = onSnapshot
    }

    func start() {
        queue.async {
            self.scanInitial()
            if FileManager.default.fileExists(atPath: self.root.path) {
                self.watcher = FSEventWatcher(paths: [self.root.path]) { [weak self] in
                    self?.scheduleIncrementalScan()
                }
                self.watcher?.start()
            }
        }
    }

    private func scanInitial() {
        let files = codexFiles().prefix(30)
        var latest: UsageSnapshot?
        for file in files {
            if let snapshot = latestTokenCount(in: file) {
                if latest == nil || snapshot.updatedAt > latest!.updatedAt {
                    latest = snapshot
                }
            }
            offsets[file] = fileSize(file)
        }
        if let latest {
            DispatchQueue.main.async {
                self.onSnapshot(latest)
            }
        }
    }

    private func scheduleIncrementalScan() {
        queue.async {
            guard !self.scanScheduled else {
                return
            }
            self.scanScheduled = true
            self.queue.asyncAfter(deadline: .now() + 0.2) {
                let files = Array(self.codexFiles().prefix(30))
                self.scanScheduled = false
                self.scanIncremental(files: files)
            }
        }
    }

    private func scanIncremental(files: [URL]) {
        for file in files {
            let size = fileSize(file)
            let offset = offsets[file] ?? 0
            defer { offsets[file] = size }

            if offset == 0 || size < offset {
                if let snapshot = latestTokenCount(in: file) {
                    DispatchQueue.main.async {
                        self.onSnapshot(snapshot)
                    }
                }
                continue
            }

            guard size > offset, let data = readFile(file, from: offset) else {
                continue
            }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let snapshot = CodexTokenCountParser.parseLine(String(line)) {
                    DispatchQueue.main.async {
                        self.onSnapshot(snapshot)
                    }
                }
            }
        }
    }

    private func codexFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.modified > $1.modified }.map(\.url)
    }

    private func latestTokenCount(in file: URL) -> UsageSnapshot? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return nil
        }
        var latest: UsageSnapshot?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.contains("\"token_count\"") {
            if let snapshot = CodexTokenCountParser.parseLine(String(line)) {
                latest = snapshot
            }
        }
        return latest
    }

    private func fileSize(_ file: URL) -> UInt64 {
        ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init)) ?? 0
    }

    private func readFile(_ file: URL, from offset: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }
}

final class ClaudeUsageCollector: @unchecked Sendable {
    private let file: URL
    private let onSnapshot: (UsageSnapshot) -> Void
    private var watcher: FSEventWatcher?

    init(file: URL, onSnapshot: @escaping (UsageSnapshot) -> Void) {
        self.file = file
        self.onSnapshot = onSnapshot
    }

    func start() {
        read()
        let directory = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        watcher = FSEventWatcher(paths: [directory.path]) { [weak self] in
            self?.read()
        }
        watcher?.start()
    }

    private func read() {
        guard
            let data = try? Data(contentsOf: file),
            let snapshot = ClaudeStatusLineParser.parseData(data)
        else {
            return
        }
        DispatchQueue.main.async {
            self.onSnapshot(snapshot)
        }
    }
}
