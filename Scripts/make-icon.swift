#!/usr/bin/env swift
//
// Renders the app icon and converts it into Icon.icns.
//
// Run: swift Scripts/make-icon.swift
//
// The design follows the same restraint as the app itself: a warm-charcoal
// squircle, a hairline inner border, and one symbol in the product accent.

import AppKit
import Foundation

let accent = NSColor(srgbRed: 0x4F / 255, green: 0xA3 / 255, blue: 0xF8 / 255, alpha: 1)
let accentLight = NSColor(srgbRed: 0xC9 / 255, green: 0xE4 / 255, blue: 0xFF / 255, alpha: 1)
let topSurface = NSColor(srgbRed: 0x27 / 255, green: 0x27 / 255, blue: 0x2B / 255, alpha: 1)
let bottomSurface = NSColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0D / 255, alpha: 1)

/// Continuous-corner squircle approximating the macOS app icon grid.
func squirclePath(in rect: NSRect, radius ratio: CGFloat = 0.2237) -> NSBezierPath {
    let radius = rect.width * ratio
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.windingRule = .evenOdd
    return path
}

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not allocate \(pixels)px bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    // Draw in a 1024-point design space scaled to the target pixel size.
    let scale = size / 1024
    let transform = AffineTransform(scaleByX: scale, byY: scale)
    (transform as NSAffineTransform).concat()

    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    // macOS icon artwork insets the tile slightly inside the full canvas.
    let tile = canvas.insetBy(dx: 44, dy: 44)
    let body = squirclePath(in: tile)

    // Base gradient.
    body.addClip()
    NSGradient(starting: topSurface, ending: bottomSurface)?.draw(in: tile, angle: -90)

    // Hairline border.
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    (transform as NSAffineTransform).concat()

    let border = squirclePath(in: tile.insetBy(dx: 1, dy: 1))
    border.lineWidth = 2
    NSColor.white.withAlphaComponent(0.10).setStroke()
    border.stroke()

    // Command glyph, masked into an accent gradient.
    let glyph = "⌘"
    let font = NSFont.systemFont(ofSize: 660, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let text = NSAttributedString(string: glyph, attributes: attributes)
    let textSize = text.size()
    let origin = NSPoint(
        x: tile.midX - textSize.width / 2,
        y: tile.midY - textSize.height / 2
    )

    if let gradient = NSGradient(starting: accentLight, ending: accent) {
        NSGraphicsContext.saveGraphicsState()
        let glyphPath = NSBezierPath()
        let line = CTLineCreateWithAttributedString(text)
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs {
                let runFont = unsafeBitCast(
                    CFDictionaryGetValue(
                        CTRunGetAttributes(run),
                        Unmanaged.passUnretained(kCTFontAttributeName).toOpaque()
                    ),
                    to: CTFont.self
                )
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
                CTRunGetPositions(run, CFRangeMake(0, count), &positions)
                for (index, glyphID) in glyphs.enumerated() {
                    if let path = CTFontCreatePathForGlyph(runFont, glyphID, nil) {
                        let position = positions[index]
                        let translated = CGMutablePath()
                        translated.addPath(path, transform: CGAffineTransform(
                            translationX: origin.x + position.x,
                            y: origin.y + position.y
                        ))
                        glyphPath.append(NSBezierPath(cgPath: translated))
                    }
                }
            }
        }
        glyphPath.addClip()
        gradient.draw(in: tile, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG")
    }
    return data
}

// MARK: - Build the .iconset

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Icon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) pairs required by iconutil.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (points, scaleFactor) in variants {
    let pixels = points * scaleFactor
    let name = scaleFactor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let data = renderIcon(pixels: pixels)
    try data.write(to: iconset.appendingPathComponent(name))
    print("rendered \(name) (\(pixels)px)")
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Icon.icns").path]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else {
    print("iconutil failed with status \(convert.terminationStatus)")
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
print("wrote Icon.icns")
