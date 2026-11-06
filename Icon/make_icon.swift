// Renders the solved-board app icon. Run: swift Icon/make_icon.swift (from repo root or anywhere).
import AppKit

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// Same mapping as Palette.tileColor in FifteenPuzzle/BoardView.swift
func tileColor(_ n: Int) -> NSColor {
    switch n {
    case 1...4: return rgb(0xFF6464)
    case 5, 9, 13: return rgb(0xFFF55A)
    case 6, 7, 8: return rgb(0x75FF60)
    case 10, 14: return rgb(0x75FFDC)
    case 11, 12: return rgb(0x8FB1FA)
    default: return rgb(0xC78AF5)
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let side = s * 824 / 1024
    let origin = (s - side) / 2
    let outer = NSRect(x: origin, y: origin, width: side, height: side)
    rgb(0x121212).setFill()
    NSBezierPath(roundedRect: outer, xRadius: side * 0.22, yRadius: side * 0.22).fill()
    let inset = side * 0.04
    let grid = outer.insetBy(dx: inset, dy: inset)
    let cell = grid.width / 4
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: grid, xRadius: side * 0.18, yRadius: side * 0.18).addClip()
    for r in 0..<4 { for c in 0..<4 {
        let n = r * 4 + c + 1
        if n == 16 { continue }
        tileColor(n).setFill()
        NSRect(x: grid.minX + CGFloat(c) * cell, y: grid.maxY - CGFloat(r + 1) * cell - 1, width: cell + 1, height: cell + 1).fill()
    } }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: dir)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
