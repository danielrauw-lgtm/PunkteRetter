import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public actor AtomicJSONStore<T: Codable & Sendable> {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load(default defaultValue: T) throws -> T {
        try withFileLock(exclusive: false) {
            try loadUnlocked(default: defaultValue)
        }
    }

    public func save(_ value: T) throws {
        try withFileLock(exclusive: true) {
            try saveUnlocked(value)
        }
    }

    public func update(default defaultValue: T, _ transform: @Sendable (inout T) throws -> Void) throws -> T {
        try withFileLock(exclusive: true) {
            var value = try loadUnlocked(default: defaultValue)
            try transform(&value)
            try saveUnlocked(value)
            return value
        }
    }

    private func loadUnlocked(default defaultValue: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaultValue }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func saveUnlocked(_ value: T) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temp) }
        try data.write(to: temp, options: [.atomic])
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: url)
        }
    }

    private func withFileLock<R>(exclusive: Bool, _ operation: () throws -> R) throws -> R {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Die Datendatei konnte nicht gesperrt werden."])
        }
        defer { _ = flock(descriptor, LOCK_UN); _ = close(descriptor) }
        let mode = exclusive ? LOCK_EX : LOCK_SH
        guard flock(descriptor, mode) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Die Datendatei konnte nicht sicher gesperrt werden."])
        }
        return try operation()
    }
}
