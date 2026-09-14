import Foundation

public enum PunkteRetterPaths {
    public static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PunkteRetter", isDirectory: true)
    }
    public static var configURL: URL { supportDirectory().appendingPathComponent("config.json") }
    public static var stateURL: URL { supportDirectory().appendingPathComponent("state.json") }
    public static var logURL: URL { supportDirectory().appendingPathComponent("PunkteRetter.log") }
}
