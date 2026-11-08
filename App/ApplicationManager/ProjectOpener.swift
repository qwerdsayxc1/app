import AppKit
import NOVACore

/// Открывает найденный проект в выбранном редакторе.
@MainActor
final class ProjectOpener: ProjectOpening {
    func open(_ project: ProjectMatch, in editor: EditorChoice) async throws {
        switch editor {
        case .finder:
            NSWorkspace.shared.activateFileViewerSelecting([project.folderURL])
        case .xcode:
            guard let xcode = WorkspaceLauncher.applicationURL(bundleIdentifiers: ["com.apple.dt.Xcode"]) else {
                throw AutomationError.editorNotInstalled("Xcode")
            }
            // .xcworkspace / .xcodeproj / Package.swift / папка — Xcode умеет открыть каждый вариант.
            try await WorkspaceLauncher.open([project.openTargetURL], withApplicationAt: xcode)
        case .intellij:
            guard let idea = WorkspaceLauncher.applicationURL(bundleIdentifiers: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]) else {
                throw AutomationError.editorNotInstalled("IntelliJ IDEA")
            }
            try await WorkspaceLauncher.open([project.folderURL], withApplicationAt: idea)
        case .vscode:
            guard let code = WorkspaceLauncher.applicationURL(bundleIdentifiers: ["com.microsoft.VSCode"]) else {
                throw AutomationError.editorNotInstalled("Visual Studio Code")
            }
            try await WorkspaceLauncher.open([project.folderURL], withApplicationAt: code)
        }
    }
}
