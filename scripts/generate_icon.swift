#!/usr/bin/swift
// Generates Resources/AppIcon.icns: a dark rounded tile with a small commit
// graph (two lanes, a branch and a merge) in the app's lane colours.
// Run from the project root:  swift scripts/generate_icon.swift

import AppKit

let size: CGFloat = 1024
let blue = NSColor(calibratedRed: 0.36, green: 0.61, blue: 1.00, alpha: 1)
let purple = NSColor(calibratedRed: 0.79, green: 0.66, blue: 1.00, alpha: 1)
let green = NSColor(calibratedRed: 0.61, green: 0.88, blue: 0.72, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Tile, inset like Apple's icon grid (824 pt body in a 1024 canvas).
let inset: CGFloat = 100
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSGradient(
    starting: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.20, alpha: 1),
    ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
)!.draw(in: tilePath, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()
NSColor(white: 1, alpha: 0.08).setStroke()
tilePath.lineWidth = 4
tilePath.stroke()

// Graph geometry (AppKit: y grows upwards).
let leftX: CGFloat = 400
let rightX: CGFloat = 630
let top: CGFloat = 780
let bottom: CGFloat = 245
let branchY: CGFloat = 350   // where the right lane leaves the main lane
let mergeY: CGFloat = 675    // where it comes back

func stroke(_ path: NSBezierPath, _ color: NSColor) {
    path.lineWidth = 46
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

// Feature lane: branches off, runs alongside, merges back.
let feature = NSBezierPath()
feature.move(to: NSPoint(x: leftX, y: branchY - 40))
feature.curve(to: NSPoint(x: rightX, y: branchY + 90),
              controlPoint1: NSPoint(x: leftX, y: branchY + 40),
              controlPoint2: NSPoint(x: rightX, y: branchY + 10))
feature.line(to: NSPoint(x: rightX, y: mergeY - 90))
feature.curve(to: NSPoint(x: leftX, y: mergeY + 40),
              controlPoint1: NSPoint(x: rightX, y: mergeY - 10),
              controlPoint2: NSPoint(x: leftX, y: mergeY - 40))
stroke(feature, purple)

// Main lane on top, so the feature lane appears to branch out of it.
let main = NSBezierPath()
main.move(to: NSPoint(x: leftX, y: bottom))
main.line(to: NSPoint(x: leftX, y: top))
stroke(main, blue)

// Commit dots.
func dot(_ x: CGFloat, _ y: CGFloat, _ color: NSColor, radius: CGFloat = 52, ring: Bool = false) {
    let rect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
    if ring {
        NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let r = NSBezierPath(ovalIn: rect.insetBy(dx: 12, dy: 12))
        r.lineWidth = 26
        color.setStroke()
        r.stroke()
    } else {
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}
dot(leftX, bottom, blue)
dot(rightX, (branchY + mergeY) / 2, purple)
dot(leftX, (branchY + mergeY) / 2 - 20, blue, radius: 44)
dot(leftX, top, green, radius: 64, ring: true)   // HEAD

image.unlockFocus()

// Write every size iconutil expects, then build the .icns.
let fm = FileManager.default
let iconset = URL(fileURLWithPath: ".build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!

func write(_ px: Int, _ name: String) {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
for base in [16, 32, 128, 256, 512] {
    write(base, "icon_\(base)x\(base).png")
    write(base * 2, "icon_\(base)x\(base)@2x.png")
}

try! fm.createDirectory(at: URL(fileURLWithPath: "Resources"), withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
try! fm.copyItem(at: iconset.appendingPathComponent("icon_512x512@2x.png"), to: URL(fileURLWithPath: "docs/icon.png"))
print(task.terminationStatus == 0 ? "✅ Resources/AppIcon.icns, docs/icon.png" : "❌ iconutil failed")
