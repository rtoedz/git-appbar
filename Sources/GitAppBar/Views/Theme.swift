import SwiftUI
import AppKit

enum Theme {
    static let panel = Color(red: 0.090, green: 0.094, blue: 0.110)
    static let surface = Color.white.opacity(0.04)
    static let border = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.07)
    static let text = Color(red: 0.90, green: 0.91, blue: 0.93)
    static let textDim = Color(red: 0.60, green: 0.63, blue: 0.67)
    static let accent = Color(red: 0.36, green: 0.55, blue: 0.94)
    static let modified = Color(red: 0.94, green: 0.76, blue: 0.48)
    static let added = Color(red: 0.61, green: 0.88, blue: 0.72)
    static let behind = Color(red: 0.56, green: 0.72, blue: 1.00)
    static let deleted = Color(red: 1.00, green: 0.60, blue: 0.62)
    static let mono = Font.system(size: 12, design: .monospaced)

    static let lanes: [Color] = [
        Color(red: 0.36, green: 0.61, blue: 1.00),
        Color(red: 0.79, green: 0.66, blue: 1.00),
        Color(red: 0.61, green: 0.88, blue: 0.72),
        Color(red: 0.94, green: 0.64, blue: 0.36),
        Color(red: 1.00, green: 0.56, blue: 0.72),
        Color(red: 0.44, green: 0.83, blue: 0.83),
        Color(red: 0.91, green: 0.83, blue: 0.42),
        Color(red: 1.00, green: 0.48, blue: 0.48)
    ]

    static func lane(_ i: Int) -> Color { lanes[i % lanes.count] }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
