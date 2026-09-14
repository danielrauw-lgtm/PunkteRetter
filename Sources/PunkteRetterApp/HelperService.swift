#if os(macOS)
import Foundation
import ServiceManagement

enum HelperService {
    static let plistName = "de.punkteretter.agent.plist"
    static var service: SMAppService { .agent(plistName: plistName) }
    static func register() throws {
        do { try service.register() }
        catch { if service.status != .enabled { throw error } }
    }
    static func unregister() throws {
        do { try service.unregister() }
        catch { if service.status != .notRegistered { throw error } }
    }
}
#endif
