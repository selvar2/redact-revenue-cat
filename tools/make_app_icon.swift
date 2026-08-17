#!/usr/bin/env swift

// Renders Redact's 1024×1024 App Store icon from the DEC-002 design tokens.
//
// Generated rather than hand-drawn so the icon cannot drift from the app: the same
// violet→amber gradient and the same eye-slash mark that `RootView` shows on launch.
// Apple rejects any build without a 1024×1024 icon during processing — silently, with
// only an email — so this is a build-critical asset, not decoration.
//
//   swift tools/make_app_icon.swift <output.png>

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

guard let ctx = CGContext(
    data: nil, width: side, height: side,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    // No alpha: App Store icons must be fully opaque. A transparent icon is a
    // rejection, and it is easy to ship one by accident.
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create bitmap context") }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// DEC-002 tokens
let violet = rgb(0xA855F7)
let amber  = rgb(0xFF6B3D)
let base   = rgb(0x0A0E1A)

let full = CGRect(x: 0, y: 0, width: side, height: side)

// Deep base first, so any gradient rounding never leaves a light seam at the edge.
ctx.setFillColor(base)
ctx.fill(full)

// The signature 135° gradient, corner to corner — matching `Token.gradient`,
// which SwiftUI draws .topLeading → .bottomTrailing.
if let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [violet, amber] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: side),
        end: CGPoint(x: side, y: 0),
        options: []
    )
}

// The eye-slash mark, drawn as vectors rather than a rasterised SF Symbol so it stays
// crisp at 1024 and needs no font dependency at build time.
let cx = CGFloat(side) / 2
let cy = CGFloat(side) / 2
let eyeWidth: CGFloat = 560
let eyeHeight: CGFloat = 300

ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Almond outline: two mirrored quadratic curves.
let eye = CGMutablePath()
eye.move(to: CGPoint(x: cx - eyeWidth / 2, y: cy))
eye.addQuadCurve(to: CGPoint(x: cx + eyeWidth / 2, y: cy),
                 control: CGPoint(x: cx, y: cy + eyeHeight))
eye.addQuadCurve(to: CGPoint(x: cx - eyeWidth / 2, y: cy),
                 control: CGPoint(x: cx, y: cy - eyeHeight))
ctx.addPath(eye)
ctx.strokePath()

// Pupil.
ctx.addEllipse(in: CGRect(x: cx - 92, y: cy - 92, width: 184, height: 184))
ctx.fillPath()

// The slash — the whole point of the app. Cut a dark gap beneath it so the stroke
// reads clearly where it crosses the white eye.
ctx.setStrokeColor(base)
ctx.setLineWidth(120)
ctx.move(to: CGPoint(x: cx - 250, y: cy - 250))
ctx.addLine(to: CGPoint(x: cx + 250, y: cy + 250))
ctx.strokePath()

ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(56)
ctx.move(to: CGPoint(x: cx - 250, y: cy - 250))
ctx.addLine(to: CGPoint(x: cx + 250, y: cy + 250))
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("could not render image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) — \(side)×\(side), opaque, \(png.count) bytes")
