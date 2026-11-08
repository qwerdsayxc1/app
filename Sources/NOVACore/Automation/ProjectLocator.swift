import Foundation

/// Найденный проект.
public struct ProjectMatch: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case xcodeWorkspace
        case xcodeProject
        case swiftPackage
        case folder
    }

    /// Папка проекта.
    public let folderURL: URL
    /// Что открывать в Xcode: .xcworkspace, .xcodeproj, Package.swift или сама папка.
    public let openTargetURL: URL
    public let kind: Kind
    public let score: Int

    public var displayName: String { folderURL.lastPathComponent }
}

/// Ищет папку проекта по названию в каталогах пользователя (без индексации всего диска).
public struct ProjectLocator: Sendable {
    public let searchRoots: [URL]
    public let maxDepth: Int
    public let maxVisitedDirectories: Int

    private static let skippedNames: Set<String> = [
        "node_modules", ".build", "build", "DerivedData", "Pods", "Library", ".git", "dist", "target", "out", "vendor"
    ]

    public init(searchPaths: [String], homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, maxDepth: Int = 3, maxVisitedDirectories: Int = 4000) {
        self.searchRoots = searchPaths.map { Self.expand($0, home: homeDirectory) }
        self.maxDepth = maxDepth
        self.maxVisitedDirectories = maxVisitedDirectories
    }

    static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Сравнение «NOVA AI» ~ «NOVA-AI» ~ «nova_ai»: без регистра, пробелов, дефисов, подчёркиваний.
    static func compactName(_ text: String) -> String {
        AppAliasResolver.normalize(text).replacingOccurrences(of: " ", with: "")
    }

    static func score(query: String, folderName: String) -> Int {
        let q = compactName(query)
        let f = compactName(folderName)
        guard !q.isEmpty, !f.isEmpty else { return 0 }
        if q == f { return 100 }
        if f.hasPrefix(q) { return 75 }
        if f.contains(q), q.count >= 3 { return 60 }
        if q.contains(f), f.count >= 4 { return 50 }
        return 0
    }

    /// Лучшее совпадение или nil.
    public func find(projectNamed name: String) -> ProjectMatch? {
        allMatches(projectNamed: name).first
    }

    /// Все совпадения, отсортированные по релевантности (при равенстве — более мелкая вложенность и Xcode-проекты выше).
    public func allMatches(projectNamed name: String) -> [ProjectMatch] {
        let fileManager = FileManager.default
        var results: [(match: ProjectMatch, depth: Int)] = []
        var visited = 0
        var queue: [(url: URL, depth: Int)] = searchRoots.map { ($0, 0) }
        var seen = Set<String>()

        while !queue.isEmpty, visited < maxVisitedDirectories {
            let (directory, depth) = queue.removeFirst()
            let key = directory.standardizedFileURL.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            visited += 1

            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let childName = child.lastPathComponent
                // Пакеты-каталоги (.app, .xcodeproj и т.п.) не обходим как проекты.
                if child.pathExtension == "app" || child.pathExtension == "xcodeproj" || child.pathExtension == "xcworkspace" {
                    continue
                }
                if Self.skippedNames.contains(childName) { continue }

                let score = Self.score(query: name, folderName: childName)
                if score > 0 {
                    results.append((makeMatch(folder: child, score: score, fileManager: fileManager), depth))
                }
                if depth + 1 < maxDepth {
                    queue.append((child, depth + 1))
                }
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
            let lhsRank = Self.kindRank(lhs.match.kind)
            let rhsRank = Self.kindRank(rhs.match.kind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            return lhs.match.folderURL.path < rhs.match.folderURL.path
        }.map(\.match)
    }

    private static func kindRank(_ kind: ProjectMatch.Kind) -> Int {
        switch kind {
        case .xcodeWorkspace: return 0
        case .xcodeProject: return 1
        case .swiftPackage: return 2
        case .folder: return 3
        }
    }

    func makeMatch(folder: URL, score: Int, fileManager: FileManager) -> ProjectMatch {
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let workspace = sorted.first(where: { $0.pathExtension == "xcworkspace" }) {
            return ProjectMatch(folderURL: folder, openTargetURL: workspace, kind: .xcodeWorkspace, score: score)
        }
        if let project = sorted.first(where: { $0.pathExtension == "xcodeproj" }) {
            return ProjectMatch(folderURL: folder, openTargetURL: project, kind: .xcodeProject, score: score)
        }
        if let package = sorted.first(where: { $0.lastPathComponent == "Package.swift" }) {
            return ProjectMatch(folderURL: folder, openTargetURL: package, kind: .swiftPackage, score: score)
        }
        return ProjectMatch(folderURL: folder, openTargetURL: folder, kind: .folder, score: score)
    }
}
