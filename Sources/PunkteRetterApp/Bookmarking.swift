#if os(macOS)
import Foundation
import PunkteRetterCore

enum Bookmarking {
    static func make(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    static func resolve(_ data: Data) throws -> (URL, Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }


    static func resolveRefreshingIfNeeded(_ data: Data) throws -> (url: URL, refreshedBookmark: Data?) {
        let result = try BookmarkRefresh.resolve(
            data,
            using: { bookmark in
                let (url, stale) = try resolve(bookmark)
                return (url: url, stale: stale)
            },
            validate: { url in
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                _ = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            },
            refresh: { try make(for: $0) }
        )
        return (result.url, result.refreshedBookmark)
    }
}
#endif
