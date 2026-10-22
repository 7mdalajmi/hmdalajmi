//
//  DebugLog.swift
//  Laqta — Shared
//
//  Small diagnostics log (Debug builds only) inside the App Group.
//

import Foundation

nonisolated enum DebugLog {
    static var fileURL: URL { AppGroup.rootURL.appending(path: "Diagnostics.log") }

    static func write(_ message: @autoclosure () -> String) {
        #if DEBUG
        let process = AppGroup.isRunningInExtension ? "ext" : "app"
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        let line = "[\(stamp)] [\(process)] \(message())\n"
        print(line, terminator: "")
        guard let data = line.data(using: .utf8) else { return }
        let url = fileURL
        // Keep the log small.
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 256_000 {
            try? Data().write(to: url, options: .atomic)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    static func tail(lines: Int = 60) -> String {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }

    static func clear() {
        try? Data().write(to: fileURL, options: .atomic)
    }
}
