#!/usr/bin/env swift
//
// Draws the CouchRemote app icon and writes the asset catalogs for both apps.
//
//     swift scripts/make-icons.swift
//
// iOS gets one full-bleed 1024 px image (the system applies the rounded mask).
// macOS gets the ten standard sizes, each drawn at its own pixel size inside the
// macOS icon shape (an 824 px rounded square with a soft shadow on a 1024 px canvas).
//
// To restyle the icon, edit `drawArtwork` and re-run.

import AppKit

// MARK: Artwork (coordinates are on a 1024 x 1024 canvas, origin bottom-left)

func drawArtwork(in ctx: CGContext, bounds: CGRect) {
    let cs = CGColorSpaceCreateDeviceRGB()

    // Background: deep charcoal, slightly lighter at the top.
    let background = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.125, green: 0.130, blue: 0.150, alpha: 1),
            CGColor(red: 0.030, green: 0.032, blue: 0.040, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        background,
        start: CGPoint(x: bounds.midX, y: bounds.maxY),
        end: CGPoint(x: bounds.midX, y: bounds.minY),
        options: []
    )

    // A faint cool glow behind the plate.
    let glow = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.30, green: 0.55, blue: 0.50, alpha: 0.22),
            CGColor(red: 0.30, green: 0.55, blue: 0.50, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: bounds.midX, y: bounds.midY - 20), startRadius: 0,
        endCenter: CGPoint(x: bounds.midX, y: bounds.midY - 20), endRadius: 520,
        options: []
    )

    // The "trackpad": a rounded plate.
    let plate = CGRect(x: 152, y: 252, width: 720, height: 520)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 130, cornerHeight: 130, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(platePath)
    ctx.setFillColor(CGColor(red: 0.17, green: 0.18, blue: 0.205, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Plate top-light edge.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let sheen = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(gray: 1, alpha: 0.10),
            CGColor(gray: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.midY), options: [])
    ctx.restoreGState()
    ctx.addPath(platePath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(5)
    ctx.strokePath()

    // The pointer. Shape in a 100-unit box (y down), tip at the origin.
    let arrow: [(CGFloat, CGFloat)] = [(0, 0), (0, 78), (21, 59), (35, 92), (50, 85), (36, 53), (64, 53)]
    let scale: CGFloat = 3.9
    let tip = CGPoint(x: 352, y: 668) // top-left of the arrow, inside the plate
    let arrowPath = CGMutablePath()
    for (i, p) in arrow.enumerated() {
        let point = CGPoint(x: tip.x + p.0 * scale, y: tip.y - p.1 * scale)
        if i == 0 { arrowPath.move(to: point) } else { arrowPath.addLine(to: point) }
    }
    arrowPath.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: CGColor(gray: 0, alpha: 0.6))
    ctx.addPath(arrowPath)
    ctx.setFillColor(CGColor(gray: 0.98, alpha: 1))
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(gray: 0.98, alpha: 1))
    ctx.setLineWidth(9)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()

    // "Connected" dot.
    let dot = CGPoint(x: 722, y: 370)
    let dotGlow = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.55),
            CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(dotGlow, startCenter: dot, startRadius: 0, endCenter: dot, endRadius: 80, options: [])
    ctx.setFillColor(CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: dot.x - 26, y: dot.y - 26, width: 52, height: 52))
}

// MARK: Rendering

/// `size` is the pixel size of the square output. `macShape` draws the macOS icon body
/// (824/1024 of the canvas, continuous-ish rounded corners, soft shadow) instead of full bleed.
func render(size: Int, macShape: Bool) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let unit = CGFloat(size) / 1024
    ctx.scaleBy(x: unit, y: unit)
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    if macShape {
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // Draw the artwork scaled into the body so the composition keeps its margins.
        ctx.translateBy(x: body.minX, y: body.minY)
        ctx.scaleBy(x: body.width / 1024, y: body.height / 1024)
        drawArtwork(in: ctx, bounds: canvas)
        ctx.restoreGState()

        // Hairline edge so the icon holds its shape on dark backgrounds.
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        ctx.setLineWidth(2)
        ctx.strokePath()
    } else {
        drawArtwork(in: ctx, bounds: canvas)
    }

    NSGraphicsContext.current = nil
    return macShape ? rep.representation(using: .png, properties: [:])! : opaquePNG(rep.cgImage!)
}

/// The App Store rejects an iOS icon with an alpha channel, so the full-bleed icon is re-encoded without one.
func opaquePNG(_ image: CGImage) -> Data {
    let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

// MARK: Output

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)

func write(_ data: Data, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try write(data, to: url)
}

let catalogInfo: [String: Any] = ["info": ["author": "xcode", "version": 1]]

// iOS: one 1024 px image.
let iosSet = root.appendingPathComponent("RemoteiPhone/Assets.xcassets/AppIcon.appiconset")
try writeJSON(catalogInfo, to: root.appendingPathComponent("RemoteiPhone/Assets.xcassets/Contents.json"))
try write(render(size: 1024, macShape: false), to: iosSet.appendingPathComponent("icon-1024.png"))
try writeJSON([
    "images": [["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": ["author": "xcode", "version": 1],
], to: iosSet.appendingPathComponent("Contents.json"))

// macOS: 16, 32, 128, 256, 512 at 1x and 2x.
let macSet = root.appendingPathComponent("RemoteMac/Assets.xcassets/AppIcon.appiconset")
try writeJSON(catalogInfo, to: root.appendingPathComponent("RemoteMac/Assets.xcassets/Contents.json"))
var macImages: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try write(render(size: points * scale, macShape: true), to: macSet.appendingPathComponent(name))
        macImages.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
try writeJSON(["images": macImages, "info": ["author": "xcode", "version": 1]], to: macSet.appendingPathComponent("Contents.json"))

print("Wrote icons to RemoteiPhone/Assets.xcassets and RemoteMac/Assets.xcassets")
