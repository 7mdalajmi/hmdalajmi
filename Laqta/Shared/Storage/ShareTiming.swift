//
//  ShareTiming.swift
//  Laqta — Shared
//
//  What the Share Extension actually costs, measured on the device.
//
//  Opening a share is the one moment where a guess is worthless: the only number
//  that counts is the one a real phone with a real library produces. Debug builds
//  stamp three moments — the sheet on screen, the library open, the folders
//  counted — and show them at the bottom of the sheet.
//
//  Release builds compile this away to nothing.
//

import Foundation

enum ShareTiming {
    #if DEBUG
    private static var startedAt: CFAbsoluteTime = 0
    private(set) static var marks: [(label: String, ms: Int)] = []
    #endif

    /// The first line of `viewDidLoad`, before anything else happens.
    static func begin() {
        #if DEBUG
        startedAt = CFAbsoluteTimeGetCurrent()
        marks = []
        #endif
    }

    static func mark(_ label: String) {
        #if DEBUG
        guard startedAt > 0 else { return }
        let ms = Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded())
        marks.append((label, ms))
        DebugLog.write("share · \(label) \(ms)ms")
        #endif
    }

    /// "sheet 38ms · library 176ms · folders 291ms"
    static var summary: String {
        #if DEBUG
        return marks.map { "\($0.label) \($0.ms)ms" }.joined(separator: "  ·  ")
        #else
        return ""
        #endif
    }
}
