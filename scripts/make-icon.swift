#!/usr/bin/env swift
// Draws the app icon (design "A2 · Ball + MT", SB-1280) from one geometry and writes:
//   App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png   1024×1024, opaque
//   design/icon/layers/{ball,dot,mt}.svg + icon.svg                  Icon Composer layers
// Run from the repo root: `swift scripts/make-icon.swift`.
//
// Geometry is a 100×100 canvas, y down (as in SVG). The "MT" text is outlined from
// design/icon/fonts/ArchivoBlack-Regular.ttf so no font is needed to render the SVGs.

import AppKit
import CoreText
import Foundation

let navy = (r: 0x15, g: 0x2C, b: 0x75)
let amber = (r: 0xF5, g: 0x9E, b: 0x0B)
let hex = { (c: (r: Int, g: Int, b: Int)) in String(format: "#%02X%02X%02X", c.r, c.g, c.b) }
/// In sRGB, the space the hex values are written in (`CGColor(red:…)` is generic RGB and shifts them).
func cg(_ c: (r: Int, g: Int, b: Int)) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat(c.r) / 255, CGFloat(c.g) / 255, CGFloat(c.b) / 255, 1])!
}

// MARK: Shapes (100-unit canvas, y down)

let ballCenter = CGPoint(x: 50, y: 39), ballRadius: CGFloat = 23
let pentagon = [CGPoint(x: 50, y: 31), CGPoint(x: 57.6, y: 36.5), CGPoint(x: 54.7, y: 45.5),
                CGPoint(x: 45.3, y: 45.5), CGPoint(x: 42.4, y: 36.5)]
let spokeEnds = [CGPoint(x: 50, y: 16), CGPoint(x: 71.9, y: 31.9), CGPoint(x: 63.5, y: 57.6),
                 CGPoint(x: 36.5, y: 57.6), CGPoint(x: 28.1, y: 31.9)]
let spokeWidth: CGFloat = 1.8
let dotCenter = CGPoint(x: 74, y: 19), dotRadius: CGFloat = 5.5

/// The ball as one filled shape: the disc minus the pentagon and the five panel seams.
func ballPath() -> CGPath {
    let disc = CGPath(ellipseIn: CGRect(x: ballCenter.x - ballRadius, y: ballCenter.y - ballRadius,
                                        width: ballRadius * 2, height: ballRadius * 2), transform: nil)
    let hole = CGMutablePath()
    hole.addLines(between: pentagon)
    hole.closeSubpath()
    var cut: CGPath = hole
    // Each seam runs from the centre (hidden under the pentagon) to past the rim, so the
    // cut-outs overlap cleanly instead of leaving slivers at the pentagon's corners.
    for end in spokeEnds {
        let past = CGPoint(x: ballCenter.x + (end.x - ballCenter.x) * 1.2, y: ballCenter.y + (end.y - ballCenter.y) * 1.2)
        let seam = CGMutablePath()
        seam.move(to: ballCenter)
        seam.addLine(to: past)
        cut = cut.union(seam.copy(strokingWithWidth: spokeWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 4))
    }
    return disc.subtracting(cut)
}

func dotPath() -> CGPath {
    CGPath(ellipseIn: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius,
                             width: dotRadius * 2, height: dotRadius * 2), transform: nil)
}

/// "MT" outlined: Archivo Black 21, tracking 0.5, centred on x = 50, baseline y = 84.
func textPath() -> CGPath {
    let url = URL(fileURLWithPath: "design/icon/fonts/ArchivoBlack-Regular.ttf")
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let descriptor = descriptors.first else { fatalError("missing font at \(url.path)") }
    let font = CTFontCreateWithFontDescriptor(descriptor, 21, nil)
    let text = Array("MT".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: text.count)
    CTFontGetGlyphsForCharacters(font, text, &glyphs, text.count)
    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
    let tracking: CGFloat = 0.5
    let width = advances.reduce(0) { $0 + $1.width } + tracking * CGFloat(glyphs.count - 1)
    let path = CGMutablePath()
    var x = 50 - width / 2
    for (glyph, advance) in zip(glyphs, advances) {
        // Glyph outlines are y up; flip into the y-down canvas at the baseline.
        var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: 84)
        if let outline = CTFontCreatePathForGlyph(font, glyph, &t) { path.addPath(outline) }
        x += advance.width + tracking
    }
    return path
}

// MARK: SVG

func svgPathData(_ path: CGPath) -> String {
    let f = { (v: CGFloat) in String(format: "%.3f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
    var d = ""
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y))"
        case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y))"
        case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
        case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func svg(_ layers: [(CGPath, String)], background: String? = nil) -> String {
    var body = background.map { "  <rect width=\"100\" height=\"100\" fill=\"\($0)\"/>\n" } ?? ""
    for (path, fill) in layers {
        body += "  <path fill=\"\(fill)\" fill-rule=\"evenodd\" d=\"\(svgPathData(path))\"/>\n"
    }
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"1024\" height=\"1024\">\n\(body)</svg>\n"
}

// MARK: PNG

func png(size: Int, layers: [(CGPath, CGColor)], background: CGColor) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // No alpha channel: App Store icons must be opaque.
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let scale = CGFloat(size) / 100
    // Canvas is y down; CoreGraphics is y up.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    for (path, color) in layers {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath(using: .evenOdd)
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: Write

let ball = ballPath(), dot = dotPath(), mt = textPath()
let fm = FileManager.default
try fm.createDirectory(atPath: "design/icon/layers", withIntermediateDirectories: true)
try svg([(ball, "#FFFFFF")]).write(toFile: "design/icon/layers/ball.svg", atomically: true, encoding: .utf8)
try svg([(dot, hex(amber))]).write(toFile: "design/icon/layers/dot.svg", atomically: true, encoding: .utf8)
try svg([(mt, "#FFFFFF")]).write(toFile: "design/icon/layers/mt.svg", atomically: true, encoding: .utf8)
try svg([(ball, "#FFFFFF"), (dot, hex(amber)), (mt, "#FFFFFF")], background: hex(navy))
    .write(toFile: "design/icon/icon.svg", atomically: true, encoding: .utf8)

let white = cg((r: 0xFF, g: 0xFF, b: 0xFF))
let iconPNG = png(size: 1024, layers: [(ball, white), (dot, cg(amber)), (mt, white)], background: cg(navy))
try iconPNG.write(to: URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
print("wrote AppIcon.png (\(iconPNG.count) bytes), design/icon/icon.svg and 3 layers")
