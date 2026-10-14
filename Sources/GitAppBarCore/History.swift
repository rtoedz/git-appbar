import Foundation

public struct CommitEntry: Identifiable, Equatable, Sendable {
    public let hash: String
    public let parents: [String]
    public let author: String
    public let email: String
    public let date: Date
    /// Decorations without the `HEAD -> ` prefix, e.g. ["dev", "origin/dev", "tag: v1.2"].
    public let refs: [String]
    /// Branch HEAD points at, when this commit is HEAD.
    public let headBranch: String?
    public let isHead: Bool
    public let subject: String

    public var id: String { hash }
    public var shortHash: String { String(hash.prefix(7)) }
    public var isMerge: Bool { parents.count > 1 }
}

public enum GitLogParser {
    /// Fields separated by US (0x1f), records terminated by RS (0x1e).
    public static let format = "%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%D%x1f%s%x1e"

    public static func parse(_ output: String) -> [CommitEntry] {
        let iso = ISO8601DateFormatter()
        return output.split(separator: "\u{1e}").compactMap { record in
            let line = record.trimmingCharacters(in: .newlines)
            guard !line.isEmpty else { return nil }
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count >= 7, !f[0].isEmpty else { return nil }
            let (refs, head, isHead) = parseRefs(f[5])
            return CommitEntry(
                hash: f[0],
                parents: f[1].split(separator: " ").map(String.init),
                author: f[2],
                email: f[3],
                date: iso.date(from: f[4]) ?? .distantPast,
                refs: refs,
                headBranch: head,
                isHead: isHead,
                subject: f[6...].joined(separator: "\u{1f}")
            )
        }
    }

    static func parseRefs(_ raw: String) -> (refs: [String], head: String?, isHead: Bool) {
        var refs: [String] = []
        var head: String?
        var isHead = false
        for part in raw.components(separatedBy: ", ") where !part.isEmpty {
            if part.hasPrefix("HEAD -> ") {
                let name = String(part.dropFirst("HEAD -> ".count))
                head = name
                isHead = true
                refs.append(name)
            } else if part == "HEAD" {
                isHead = true
            } else if !part.hasSuffix("/HEAD") {
                refs.append(part)
            }
        }
        return (refs, head, isHead)
    }
}

public struct CommitFile: Identifiable, Equatable, Sendable {
    public let path: String
    public let oldPath: String?
    /// M, A, D, R, C, T
    public let status: String
    /// nil for binary files.
    public let additions: Int?
    public let deletions: Int?

    public var id: String { path }
}

public enum CommitFilesParser {
    /// Joins `--name-status -z` and `--numstat -z` output of the same diff.
    public static func parse(nameStatus: String, numstat: String) -> [CommitFile] {
        var stats: [String: (Int?, Int?)] = [:]
        var tokens = numstat.components(separatedBy: "\0")[...]
        while let t = tokens.popFirst() {
            guard !t.isEmpty else { continue }
            let f = t.components(separatedBy: "\t")
            guard f.count >= 3 else { continue }
            let add = Int(f[0]), del = Int(f[1])
            if f[2].isEmpty {
                _ = tokens.popFirst()
                if let new = tokens.popFirst() { stats[new] = (add, del) }
            } else {
                stats[f[2]] = (add, del)
            }
        }

        var files: [CommitFile] = []
        var ns = nameStatus.components(separatedBy: "\0")[...]
        while let status = ns.popFirst() {
            guard let code = status.first else { continue }
            if code == "R" || code == "C" {
                guard let old = ns.popFirst(), let new = ns.popFirst() else { break }
                let s = stats[new]
                files.append(CommitFile(path: new, oldPath: old, status: String(code), additions: s?.0, deletions: s?.1))
            } else {
                guard let path = ns.popFirst() else { break }
                let s = stats[path]
                files.append(CommitFile(path: path, oldPath: nil, status: String(code), additions: s?.0, deletions: s?.1))
            }
        }
        return files
    }
}

public struct Branch: Identifiable, Equatable, Sendable {
    public let name: String
    public let isRemote: Bool
    public let isCurrent: Bool
    public let upstream: String?
    public let date: Date

    public var id: String { (isRemote ? "remote:" : "local:") + name }

    /// `origin/feature/x` → `feature/x`
    public var localName: String {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

public enum BranchParser {
    public static let format = "%(HEAD)%1f%(refname)%1f%(refname:short)%1f%(upstream:short)%1f%(committerdate:unix)"

    public static func parse(_ output: String) -> [Branch] {
        output.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count >= 5 else { return nil }
            let full = f[1]
            if full.hasSuffix("/HEAD") { return nil }
            let isRemote = full.hasPrefix("refs/remotes/")
            guard isRemote || full.hasPrefix("refs/heads/") else { return nil }
            return Branch(
                name: f[2],
                isRemote: isRemote,
                isCurrent: f[0] == "*",
                upstream: f[3].isEmpty ? nil : f[3],
                date: Date(timeIntervalSince1970: TimeInterval(f[4]) ?? 0)
            )
        }
        .sorted { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent }
            return a.date > b.date
        }
    }
}
