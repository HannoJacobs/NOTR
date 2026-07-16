import Darwin
import Foundation
import os

/// File + Console logger for NOTR.
/// Session logs live under ~/Library/Application Support/NOTR/Logs/,
/// with `latest.log` symlinked for install-release verification.
enum Log {
    private static let subsystem = "com.hannojacobs.NOTR"
    private static let osLog = os.Logger(subsystem: subsystem, category: "app")
    private static let queue = DispatchQueue(label: "com.hannojacobs.NOTR.log", qos: .utility)
    static let launchSessionID = String(UUID().uuidString.prefix(8)).lowercased()

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let logURL: URL? = prepareLogFile()

    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    static var buildVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? appVersion
    }

    static var logFilePath: String {
        logURL?.path ?? "unavailable"
    }

    static var runtimeSummary: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? (CommandLine.arguments.first ?? "unknown")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let osBuild = sysctlString("kern.osversion") ?? "unknown"
        let hwModel = sysctlString("hw.model") ?? "unknown"

        return [
            "version=\(appVersion)",
            "build=\(buildVersion)",
            "bundleID=\(bundleID)",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "os=\(osVersion)",
            "osBuild=\(osBuild)",
            "hwModel=\(hwModel)",
            "bundlePath=\(bundlePath)",
            "executablePath=\(executablePath)",
            "diagnosticsFile=\(logFilePath)"
        ].joined(separator: " ")
    }

    static func info(_ message: @autoclosure () -> String, _ context: String = "") {
        write(level: "INFO", message(), context)
    }

    static func error(_ message: @autoclosure () -> String, _ context: String = "") {
        write(level: "ERROR", message(), context)
    }

    private static func write(level: String, _ message: String, _ context: String) {
        let sanitized = message.replacingOccurrences(of: "\n", with: " | ")
        let ctx = context.isEmpty ? "" : " [\(context)]"
        let line = "\(formatter.string(from: Date())) \(level)\(ctx) launchSession=\(launchSessionID) \(sanitized)"

        switch level {
        case "ERROR": osLog.error("\(line, privacy: .public)")
        default: osLog.info("\(line, privacy: .public)")
        }

        guard let logURL else { return }
        queue.async {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func prepareLogFile() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let logsDir = appSupport
            .appendingPathComponent("NOTR", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)

        do {
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let filename = "notr-\(launchTimestamp())-\(launchSessionID).log"
        let url = logsDir.appendingPathComponent(filename)
        fileManager.createFile(atPath: url.path, contents: Data())

        let latestURL = logsDir.appendingPathComponent("latest.log")
        try? fileManager.removeItem(at: latestURL)
        try? fileManager.createSymbolicLink(at: latestURL, withDestinationURL: url)

        pruneOldLogs(in: logsDir, keeping: 40)
        return url
    }

    private static func pruneOldLogs(in logsDir: URL, keeping limit: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sessionLogs = urls
            .filter { $0.pathExtension == "log" && $0.lastPathComponent != "latest.log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard sessionLogs.count > limit else { return }
        for url in sessionLogs.prefix(sessionLogs.count - limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func launchTimestamp() -> String {
        let components = Calendar.current.dateComponents(in: .current, from: Date())
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
