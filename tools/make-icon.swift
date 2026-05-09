#!/usr/bin/env swift
//
// Renderiza a logo do PraticEnglish em PNG 1024x1024.
// Uso: swift tools/make-icon.swift <output.png>
//
// O design é simples para permanecer legível em 16px (barra de menu) e
// em 1024px (App Store). Gradiente verde→azul + "EN" em branco.
//

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: make-icon.swift <output.png>\n".utf8))
    exit(64)
}

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("Falha ao criar CGContext\n".utf8))
    exit(1)
}

// Recorta numa rounded square no estilo macOS Big Sur+ (~22.5% de raio).
let cornerRadius: CGFloat = size * 0.225
let bgPath = CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
ctx.addPath(bgPath)
ctx.clip()

// Gradiente verde (topo) → azul (base), evocando pt-BR → en sem ser literal.
let bgColors = [
    CGColor(red: 0.07, green: 0.71, blue: 0.49, alpha: 1.0),
    CGColor(red: 0.05, green: 0.36, blue: 0.78, alpha: 1.0)
] as CFArray
let bgGradient = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Brilho sutil no topo para dar profundidade.
let highlightColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
] as CFArray
let hg = CGGradient(colorsSpace: cs, colors: highlightColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    hg,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: size * 0.55),
    options: []
)

// Texto "EN" centralizado.
let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx

let textAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 560, weight: .black),
    .foregroundColor: NSColor.white,
    .kern: -25
]
let text = NSAttributedString(string: "EN", attributes: textAttrs)
let textSize = text.size()
let textRect = CGRect(
    x: (size - textSize.width) / 2,
    y: (size - textSize.height) / 2 - size * 0.04,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect)

// Pequeno traço sob "EN" sugerindo "tradução acontecendo".
let underline = NSBezierPath()
let underlineY: CGFloat = textRect.minY - 30
let underlineWidth: CGFloat = textSize.width * 0.55
underline.move(to: NSPoint(x: (size - underlineWidth) / 2, y: underlineY))
underline.line(to: NSPoint(x: (size + underlineWidth) / 2, y: underlineY))
underline.lineWidth = 28
underline.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.85).setStroke()
underline.stroke()

NSGraphicsContext.restoreGraphicsState()

// Exporta PNG.
guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write(Data("Falha ao gerar imagem\n".utf8))
    exit(2)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: size, height: size)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Falha ao codificar PNG\n".utf8))
    exit(3)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: outURL)
print("✓ \(outURL.path) (\(Int(size))×\(Int(size)))")
