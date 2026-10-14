import AppKit
import SwiftUI

/// `GAB_RENDER=/path/out.png` renders the panel to a PNG and quits — no
/// screen-recording permission needed. Blur is not rendered (it samples the
/// desktop), so the solid background is used.
@MainActor
enum DebugRender {
    static func runIfRequested(preferences: Preferences, store: RepoStore) -> Bool {
        guard let path = ProcessInfo.processInfo.environment["GAB_RENDER"] else { return false }
        if let roots = ProcessInfo.processInfo.environment["GAB_ROOTS"] {
            preferences.rootFolders = roots.split(separator: ":").map(String.init)
        }
        Task { @MainActor in
            store.rescan(roots: preferences.rootFolderURLs, depth: preferences.scanDepth)
            try? await Task.sleep(for: .seconds(4))
            if let wanted = ProcessInfo.processInfo.environment["GAB_RENDER_REPO"],
               let repo = store.repos.first(where: { $0.name == wanted }) {
                store.selectedID = repo.id
                try? await Task.sleep(for: .seconds(2))
            }
            if let first = store.history.dropFirst().first {
                store.toggleCommit(first.hash)
                try? await Task.sleep(for: .seconds(1.5))
            }

            let view = PanelRootView()
                .environment(preferences)
                .environment(store)
                .environment(\.debugRender, true)
                .frame(width: 1600, height: 860)
                .background(Color(red: 0.23, green: 0.31, blue: 0.42))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("rendered \(path)")
            } else {
                print("render failed")
            }
            NSApp.terminate(nil)
        }
        return true
    }
}

/// ScrollView that ImageRenderer can draw: ScrollView content is not rendered
/// offscreen, so in debug-render mode the content is laid out in a clipped stack.
struct PanelScroll<Content: View>: View {
    @Environment(\.debugRender) private var debugRender
    @ViewBuilder let content: Content

    var body: some View {
        if debugRender {
            VStack(spacing: 0) { content; Spacer(minLength: 0) }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity)
                .clipped()
        } else {
            ScrollView { content }
        }
    }
}

private struct DebugRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var debugRender: Bool {
        get { self[DebugRenderKey.self] }
        set { self[DebugRenderKey.self] = newValue }
    }
}
