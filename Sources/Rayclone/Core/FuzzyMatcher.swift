import Foundation

/// Fuzzy subsequence matcher with tiered bonuses, modelled on the ranking
/// behaviour Raycast uses for root search: word-boundary matches beat
/// consecutive runs which beat scattered matches, and shorter candidates win.
struct FuzzyResult {
    var score: Double
    var matchedIndices: Set<Int>
}

enum FuzzyMatcher {
    /// Score a `query` against `candidate`. Returns `nil` when the query is not a
    /// subsequence of the candidate.
    static func match(_ query: String, in candidate: String) -> FuzzyResult? {
        guard !query.isEmpty else { return FuzzyResult(score: 0, matchedIndices: []) }

        let queryChars = Array(query.lowercased())
        let candChars = Array(candidate)
        let candLower = Array(candidate.lowercased())

        guard candChars.count >= queryChars.count else { return nil }

        // Fast path: contiguous (case-insensitive) substring.
        if let range = candidate.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            let lower = candidate.lowercased()
            let start = lower.distance(from: lower.startIndex, to: lower.range(of: query.lowercased())?.lowerBound ?? lower.startIndex)
            let indices = Set((start..<(start + queryChars.count)))
            var score = 100.0
            if start == 0 {
                score += 40 // prefix match is very strong
            } else if isWordBoundary(candChars, at: start) {
                score += 20
            }
            score -= Double(candidate.count) * 0.05
            _ = range
            return FuzzyResult(score: score, matchedIndices: indices)
        }

        var matched = Set<Int>()
        var score = 0.0
        var candIndex = 0

        for (qi, qc) in queryChars.enumerated() {
            var found = false
            while candIndex < candLower.count {
                if candLower[candIndex] == qc {
                    matched.insert(candIndex)
                    score += 10
                    if qi == 0 && candIndex == 0 {
                        score += 40
                    } else if isWordBoundary(candChars, at: candIndex) {
                        score += 20
                    }
                    // consecutive run bonus
                    if matched.contains(candIndex - 1) {
                        score += 15
                    }
                    candIndex += 1
                    found = true
                    break
                }
                candIndex += 1
            }
            if !found { return nil }
        }

        // Gap penalty: fewer skipped characters ranks higher.
        let span = (matched.max() ?? 0) - (matched.min() ?? 0) + 1
        score -= Double(span - matched.count) * 1.5
        score -= Double(candidate.count) * 0.05
        return FuzzyResult(score: score, matchedIndices: matched)
    }

    static func score(_ query: String, in candidate: String) -> Double? {
        match(query, in: candidate)?.score
    }

    private static func isWordBoundary(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = chars[index - 1]
        let cur = chars[index]
        if prev == " " || prev == "-" || prev == "_" || prev == "." || prev == "/" || prev == ":" { return true }
        if prev.isLowercase && cur.isUppercase { return true }
        return false
    }
}

/// Splits a raw query into the search term and an optional trailing argument
/// (Raycast's `command arg` convention).
struct ParsedQuery {
    var term: String
    var argument: String?

    static func parse(_ raw: String) -> ParsedQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else {
            return ParsedQuery(term: trimmed, argument: nil)
        }
        let term = String(trimmed[trimmed.startIndex..<spaceIndex])
        let rest = String(trimmed[trimmed.index(after: spaceIndex)...])
        return ParsedQuery(term: term, argument: rest.isEmpty ? nil : rest)
    }
}
