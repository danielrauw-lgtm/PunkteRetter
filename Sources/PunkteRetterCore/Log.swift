import Foundation

public actor SafeLog {
    public static let shared = SafeLog()
    private let maxBytes: UInt64 = 512 * 1024
    public func write(_ message: String) {
        let url = PunkteRetterPaths.logURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let attrs = try? fm.attributesOfItem(atPath: url.path), let size = attrs[.size] as? UInt64, size > maxBytes {
                let rotated = url.deletingLastPathComponent().appendingPathComponent("PunkteRetter.previous.log")
                try? fm.removeItem(at: rotated)
                try? fm.moveItem(at: url, to: rotated)
            }
            let f = ISO8601DateFormatter()
            let line = "[\(f.string(from: Date()))] \(message)\n"
            let data = Data(line.utf8)
            if !fm.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            else {
                let h = try FileHandle(forWritingTo: url); defer { try? h.close() }
                try h.seekToEnd(); try h.write(contentsOf: data)
            }
        } catch { }
    }
}
