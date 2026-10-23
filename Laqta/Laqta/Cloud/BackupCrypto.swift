//
//  BackupCrypto.swift
//  Laqta
//
//  A locked folder stays locked inside a backup.
//
//  Face ID on a folder only ever guarded the screen. The backup wrote the same photos
//  out as ordinary files — into iCloud Drive, and into a `.laqtabackup` the user may
//  well put in Files, mail to themselves or copy to a Mac — where anyone who could
//  open the file could see them. Now the media and thumbnails of a locked folder, and
//  of every folder under it, are sealed with AES-GCM before they leave the app, under
//  a key that lives in the Keychain and travels only through the user's own iCloud
//  Keychain. The manifest is not sealed: it holds names and dates, and a restore has
//  to be able to read it to tell the user what is in the backup and what it can't open.
//
//  Sealed in chunks rather than whole, because a backup contains videos and the
//  extension is not the only place with a memory limit. Each chunk's seal also
//  authenticates the file's name, the chunk's position and the file's length, so
//  chunks cannot be swapped between files or reordered inside one.
//

import CryptoKit
import Foundation
import Security

/// The key that seals a locked folder's files inside a backup.
nonisolated enum BackupKey {
    private static let service = "Hmdalajmi.Laqta.backup"
    private static let account = "locked-media-v1"

    /// The key, or nil when this device has none and isn't allowed to make one.
    ///
    /// It is marked synchronizable, so the user's other devices get it through their
    /// iCloud Keychain and can restore what this one sealed; and accessible after the
    /// first unlock, so a scheduled backup can still run with the phone in a pocket.
    static func key(creating: Bool) throws -> SymmetricKey? {
        if let existing = try read() { return existing }
        guard creating else { return nil }
        let made = SymmetricKey(size: .bits256)
        let bytes = made.withUnsafeBytes { Data($0) }
        var attributes = baseQuery
        attributes[kSecValueData as String] = bytes
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Another device's key arrived through iCloud Keychain in the meantime.
            guard let existing = try read() else { throw BackupError.keyUnavailable }
            return existing
        }
        guard status == errSecSuccess else {
            DebugLog.write("backup: couldn't store the key (\(status))")
            throw BackupError.keyUnavailable
        }
        return made
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
    }

    private static func read() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { throw BackupError.keyUnavailable }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            DebugLog.write("backup: couldn't read the key (\(status))")
            throw BackupError.keyUnavailable
        }
    }

    /// Only for tests: forgets the key on this device.
    static func forget() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// One file, sealed.
nonisolated enum BackupCrypto {
    /// What a sealed copy is called, inside the archive and in the iCloud pool. The
    /// name differs from the plain one so a sealed file can never be read, or
    /// replaced, as if it were plain.
    static let suffix = ".lqenc"
    static let magic = Array("LQEN".utf8)
    static let version: UInt16 = 1
    /// Plaintext per chunk. A 2 GB video is sealed in 2,000 of these, never at once.
    static let chunkSize = 1 << 20
    static let headerSize = 18

    static func sealedName(_ name: String) -> String { name + suffix }

    static func seal(
        _ source: URL,
        to destination: URL,
        name: String,
        key: SymmetricKey,
        isCancelled: () -> Bool = { false }
    ) throws {
        let manager = FileManager.default
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let size = try input.seekToEnd()
        try input.seek(toOffset: 0)
        try? manager.removeItem(at: destination)
        guard manager.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var header = Data(magic)
        header.append(contentsOf: bytes(of: version))
        header.append(contentsOf: bytes(of: UInt32(chunkSize)))
        header.append(contentsOf: bytes(of: size))
        try output.write(contentsOf: header)
        var index: UInt32 = 0
        var remaining = size
        while remaining > 0 {
            if isCancelled() { throw BackupError.cancelled }
            let count = Int(min(UInt64(chunkSize), remaining))
            guard let chunk = try input.read(upToCount: count), !chunk.isEmpty else {
                throw BackupError.damaged
            }
            let sealed = try AES.GCM.seal(
                chunk,
                using: key,
                authenticating: authenticatedData(name: name, index: index, size: size)
            )
            guard let combined = sealed.combined, combined.count <= UInt32.max else {
                throw BackupError.damaged
            }
            try output.write(contentsOf: Data(bytes(of: UInt32(combined.count))))
            try output.write(contentsOf: combined)
            remaining -= UInt64(chunk.count)
            index += 1
        }
        try output.synchronize()
    }

    /// Opens a sealed file. A key that doesn't fit, or a chunk that was tampered with,
    /// throws rather than writing something half-right.
    static func open(
        _ source: URL,
        to destination: URL,
        name: String,
        key: SymmetricKey,
        isCancelled: () -> Bool = { false }
    ) throws {
        let manager = FileManager.default
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let end = try input.seekToEnd()
        try input.seek(toOffset: 0)
        guard let header = try input.read(upToCount: headerSize), header.count == headerSize,
              Array(header.prefix(4)) == magic else {
            throw BackupError.damaged
        }
        let fileVersion = integer(UInt16.self, header, at: 4)
        guard fileVersion > 0, fileVersion <= version else { throw BackupError.newerFormat }
        let sealedChunk = Int(integer(UInt32.self, header, at: 6))
        guard sealedChunk > 0, sealedChunk <= 8 << 20 else { throw BackupError.damaged }
        let declared = integer(UInt64.self, header, at: 10)
        try? manager.removeItem(at: destination)
        guard manager.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        var written: UInt64 = 0
        var index: UInt32 = 0
        do {
            while try input.offset() < end {
                if isCancelled() { throw BackupError.cancelled }
                guard let lengthData = try input.read(upToCount: 4), lengthData.count == 4 else {
                    throw BackupError.damaged
                }
                let length = Int(integer(UInt32.self, lengthData, at: 0))
                // A sealed chunk is a nonce, the bytes, and a tag: never longer than a
                // chunk plus those, and never shorter than them.
                guard length > 28, length <= sealedChunk + 28,
                      let sealedData = try input.read(upToCount: length), sealedData.count == length else {
                    throw BackupError.damaged
                }
                let box = try AES.GCM.SealedBox(combined: sealedData)
                let chunk = try AES.GCM.open(
                    box,
                    using: key,
                    authenticating: authenticatedData(name: name, index: index, size: declared)
                )
                try output.write(contentsOf: chunk)
                written += UInt64(chunk.count)
                index += 1
            }
            guard written == declared else { throw BackupError.damaged }
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    /// Ties a chunk to its file, its place in it, and the file's length.
    private static func authenticatedData(name: String, index: UInt32, size: UInt64) -> Data {
        var data = Data(name.utf8)
        data.append(contentsOf: bytes(of: index))
        data.append(contentsOf: bytes(of: size))
        return data
    }

    private static func bytes<T: FixedWidthInteger>(of value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private static func integer<T: FixedWidthInteger>(_ type: T.Type, _ data: Data, at offset: Int) -> T {
        var value: T = 0
        let start = data.startIndex + offset
        for position in 0..<(T.bitWidth / 8) {
            value |= T(data[start + position]) << (8 * position)
        }
        return value
    }
}
