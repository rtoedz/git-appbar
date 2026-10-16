#!/usr/bin/swift
// Generates the DMG installer window background (600×400).
// Run from the project root:  swift scripts/generate_dmg_background.swift
// Output: Resources/dmg-background.png
//
// Finder positions icons in a TOP-LEFT coordinate space; AppKit draws in a
// BOTTOM-LEFT space. The icon centres below (app 160,200 · Applications 440,200)
// are expressed in Finder coords and converted with (H - y) when drawing, so the
// arrow lines up with the icons placed by make_dmg.sh.

import AppKit

let W: CGFloat = 600
let H: CGFloat = 400

// Icon centres in Finder (top-left) coords — must match make_dmg.sh positions.
let appCenter = NSPoint(x: 160, y: 200)
let appsCenter = NSPoint(x: 440, y: 200)

let accent = NSColor(calibratedRed: 0.36, green: 0.61, blue: 1.00, alpha: 1)

func flip(_ y: CGFloat) -> CGFloat { H - y }

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

// ── Background gradient (matches the app's dark card theme) ──────────────────
NSGradient(
    starting: NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1),
    ending:   NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// ── Subtle drop-zone platforms behind each icon ─────────────────────────────
func platform(_ center: NSPoint) {
    let r: CGFloat = 80
    let rect = NSRect(x: center.x - r, y: flip(center.y) - r, width: r * 2, height: r * 2)
    NSColor(white: 1, alpha: 0.035).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26).fill()
}
platform(appCenter)
platform(appsCenter)

// ── Applications folder icon ────────────────────────────────────────────────
// The live /Applications symlink renders blank in DMG windows on recent macOS,
// so the real folder icon is painted here and the (invisible) symlink is placed
// on top by make_dmg.sh as the actual drop target.
let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
let iconSize: CGFloat = 128
appsIcon.draw(in: NSRect(x: appsCenter.x - iconSize / 2,
                         y: flip(appsCenter.y) - iconSize / 2,
                         width: iconSize, height: iconSize))

// ── Arrow (app → Applications) ──────────────────────────────────────────────
let midY = flip(200)
let x1 = appCenter.x + 88        // just past the app icon's right edge
let x2 = appsCenter.x - 88       // just before the Applications icon
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: x1, y: midY))
shaft.line(to: NSPoint(x: x2 - 12, y: midY))
shaft.lineWidth = 7
shaft.lineCapStyle = .round
accent.setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: x2, y: midY))
head.line(to: NSPoint(x: x2 - 20, y: midY + 13))
head.line(to: NSPoint(x: x2 - 20, y: midY - 13))
head.close()
accent.setFill()
head.fill()

// ── Text ─────────────────────────────────────────────────────────────────────
func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, finderY: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let textH = str.size().height
    str.draw(in: NSRect(x: 0, y: flip(finderY) - textH / 2, width: W, height: textH))
}

drawText("Install Git AppBar", size: 26, weight: .bold,
         color: .white, finderY: 64)
drawText("Drag the app onto the Applications folder",
         size: 13, weight: .regular,
         color: NSColor(white: 1, alpha: 0.45), finderY: 330)

image.unlockFocus()

// ── Write PNG ────────────────────────────────────────────────────────────────
let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let rep = NSBitmapImageRep(cgImage: cg)
rep.size = NSSize(width: W, height: H)
let png = rep.representation(using: .png, properties: [:])!
let dest = URL(fileURLWithPath: "Resources/dmg-background.png")
try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
try! png.write(to: dest)
print("✅ Written \(dest.path)")
