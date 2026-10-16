#!/usr/bin/swift
// Sets a custom Finder icon on a file (e.g. the .dmg itself, not its volume).
// Usage:  swift scripts/set_file_icon.swift <icon.icns> <target-file>

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: set_file_icon.swift <icon> <target>\n".utf8))
    exit(1)
}

guard let icon = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("could not load icon: \(args[1])\n".utf8))
    exit(1)
}

let ok = NSWorkspace.shared.setIcon(icon, forFile: args[2], options: [])
print(ok ? "✅ icon set on \(args[2])" : "⚠️ failed to set icon")
exit(ok ? 0 : 1)
