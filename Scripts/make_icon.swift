#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws a treemap-style app icon and emits the .iconset PNGs.

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

struct Block {
    let rect: CGRect      // normalised 0...1
    let color: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

let blocks: [Block] = [
    Block(rect: CGRect(x: 0.00, y: 0.00, width: 0.52, height: 0.58), color: rgb(0x4E9BE8)),
    Block(rect: CGRect(x: 0.52, y: 0.00, width: 0.48, height: 0.33), color: rgb(0xE8524E)),
    Block(rect: CGRect(x: 0.52, y: 0.33, width: 0.26, height: 0.25), color: rgb(0xF0B429)),
    Block(rect: CGRect(x: 0.78, y: 0.33, width: 0.22, height: 0.25), color: rgb(0xA05FE8)),
    Block(rect: CGRect(x: 0.00, y: 0.58, width: 0.30, height: 0.42), color: rgb(0x5FC463)),
    Block(rect: CGRect(x: 0.30, y: 0.58, width: 0.28, height: 0.22), color: rgb(0x2FC2C0)),
    Block(rect: CGRect(x: 0.30, y: 0.80, width: 0.28, height: 0.20), color: rgb(0xE8873A)),
    Block(rect: CGRect(x: 0.58, y: 0.58, width: 0.42, height: 0.42), color: rgb(0xE87CB8))
]

func render(size: Int) -> CGImage? {
    let dimension = CGFloat(size)
    guard let context = CGContext(data: nil,
                                  width: size,
                                  height: size,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let inset = dimension * 0.055
    let canvas = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let radius = canvas.width * 0.2237

    let rounded = CGPath(roundedRect: canvas, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.addPath(rounded)
    context.clip()

    context.setFillColor(rgb(0x1C1C1E))
    context.fill(canvas)

    let padding = canvas.width * 0.075
    let inner = canvas.insetBy(dx: padding, dy: padding)
    let gap = max(dimension * 0.008, 0.5)

    for block in blocks {
        let rect = CGRect(x: inner.minX + block.rect.minX * inner.width + gap / 2,
                          y: inner.minY + block.rect.minY * inner.height + gap / 2,
                          width: block.rect.width * inner.width - gap,
                          height: block.rect.height * inner.height - gap)
        guard rect.width > 0, rect.height > 0 else { continue }

        // Cushion-ish vertical gradient for depth.
        let components = block.color.components ?? [0.5, 0.5, 0.5, 1]
        let bright = CGColor(srgbRed: min(1, components[0] * 1.22),
                             green: min(1, components[1] * 1.22),
                             blue: min(1, components[2] * 1.22),
                             alpha: 1)
        let dark = CGColor(srgbRed: components[0] * 0.62,
                           green: components[1] * 0.62,
                           blue: components[2] * 0.62,
                           alpha: 1)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [bright, block.color, dark] as CFArray,
                                        locations: [0, 0.45, 1]) else { continue }
        context.saveGState()
        let corner = min(rect.width, rect.height) * 0.14
        context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.clip()
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY),
                                   options: [])
        context.restoreGState()
    }

    context.restoreGState()

    // Subtle outer rim.
    context.addPath(rounded)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
    context.setLineWidth(max(1, dimension * 0.008))
    context.strokePath()

    return context.makeImage()
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (size, name) in sizes {
    guard let image = render(size: size) else { continue }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

print("Wrote iconset to \(outputDirectory)")
