import Foundation

/// One Spotlight hit, before it becomes a launcher row.
struct FileCandidate {
    let item: SearchItem
    let isDirectory: Bool
    /// Number of path separators, used to prefer shallower files.
    let pathDepth: Int
    /// Position in Spotlight's recency-sorted result set; lower is newer.
    let evidenceOrder: Int
}

/// Ranking for Spotlight file hits.
///
/// `NSMetadataQuery` can only sort by content-change date, which buries a
/// top-level folder under every recently touched file sharing the substring
/// (`~/dock` sat at index 61 of 254 results for "dock"). So the provider scans
/// the whole match set and re-ranks here: how well the *name* matches first,
/// then shallower paths, then Spotlight's recency order.
enum FileResultRanking {
    /// Exact name matches beat prefix matches, which beat mid-name matches.
    ///
    /// `FuzzyMatcher` penalises long candidates, so without the exact/prefix
    /// bonuses a folder called `docker` would outrank a folder called `dock`.
    static func nameScore(_ name: String, term: String) -> Double {
        let base = FuzzyMatcher.score(term, in: name) ?? 0
        let loweredName = name.lowercased()
        let loweredTerm = term.lowercased()
        if loweredName == loweredTerm { return base + 60 }
        if loweredName.hasPrefix(loweredTerm) { return base + 20 }
        return base
    }

    /// The test Spotlight's `kMDItemFSName LIKE[cd] "*term*"` predicate
    /// applies, repeated here for rows that never come from Spotlight.
    static func nameContains(_ name: String, term: String) -> Bool {
        name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Best `limit` candidates for one kind of hit (folders or files).
    static func pool(_ candidates: [FileCandidate], term: String, limit: Int) -> [FileCandidate] {
        guard limit > 0 else { return [] }
        let ranked = candidates.sorted { lhs, rhs in
            let lhsScore = nameScore(lhs.item.title, term: term)
            let rhsScore = nameScore(rhs.item.title, term: term)
            if abs(lhsScore - rhsScore) > 0.001 { return lhsScore > rhsScore }
            if lhs.pathDepth != rhs.pathDepth { return lhs.pathDepth < rhs.pathDepth }
            return lhs.evidenceOrder < rhs.evidenceOrder
        }
        return Array(ranked.prefix(limit))
    }

    /// Folders first, then files — the launcher shows their sections in that
    /// order, so an identically named folder is always listed above the file.
    static func ordered(folders: [FileCandidate], files: [FileCandidate], term: String, limit: Int) -> [SearchItem] {
        (pool(folders, term: term, limit: limit) + pool(files, term: term, limit: limit)).map(\.item)
    }
}
