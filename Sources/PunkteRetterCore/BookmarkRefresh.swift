import Foundation

public struct RefreshedBookmarkResolution: Equatable, Sendable {
    public let url: URL
    public let refreshedBookmark: Data?

    public init(url: URL, refreshedBookmark: Data?) {
        self.url = url
        self.refreshedBookmark = refreshedBookmark
    }
}

public enum BookmarkRefresh {
    /// Kapselt die sicherheitsrelevante Entscheidung unabhängig von AppKit:
    /// Nicht veraltete Bookmarks bleiben unverändert. Ein stale Bookmark wird nur
    /// erneuert, wenn seine aufgelöste Ressource zuerst erfolgreich geprüft wurde.
    /// Einen Rückfall auf gespeicherte Klartextpfade gibt es bewusst nicht.
    public static func resolve(
        _ data: Data,
        using resolver: (Data) throws -> (url: URL, stale: Bool),
        validate: (URL) throws -> Void,
        refresh: (URL) throws -> Data
    ) throws -> RefreshedBookmarkResolution {
        let resolved = try resolver(data)
        guard resolved.stale else {
            return RefreshedBookmarkResolution(url: resolved.url, refreshedBookmark: nil)
        }
        try validate(resolved.url)
        return RefreshedBookmarkResolution(url: resolved.url, refreshedBookmark: try refresh(resolved.url))
    }
}
