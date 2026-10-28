// Builds Resources/AppIcon.icns from Resources/mark-source.png (light mark on a dark background).
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let source = NSImage(contentsOf: resources.appendingPathComponent("mark-source.png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Turns the source artwork into an alpha mask cropped tightly around the mark.
func extractMask(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    var gray = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Map background (dark) to 0 and the mark (light) to 255, keeping anti-aliased edges.
    let low = 60.0, high = 220.0
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let v = (Double(gray[y * w + x]) - low) / (high - low)
            let a = UInt8(max(0, min(1, v)) * 255)
            gray[y * w + x] = a
            if a > 128 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        }
    }
    let full = ctx.makeImage()!
    // Square crop centered on the mark with a small margin.
    let side = max(maxX - minX, maxY - minY) + 8
    let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
    return full.cropping(to: CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side))!
}

let mask = extractMask(source)

func renderIcon(size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body centered in 1024, continuous-ish corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0.35))
    ctx.addPath(tile); ctx.setFillColor(color(0x1C1B1F)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0x2A292E), color(0x121114)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183.5, cornerHeight: 183.5, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.08)); ctx.setLineWidth(3); ctx.strokePath()

    let markSide: CGFloat = 540
    let markRect = CGRect(x: 512 - markSide / 2, y: 512 - markSide / 2, width: markSide, height: markSide)
    ctx.saveGState()
    ctx.clip(to: markRect, mask: mask)
    ctx.setFillColor(color(0xF2F2F4)); ctx.fill(markRect)
    ctx.restoreGState()
    return ctx.makeImage()!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: renderIcon(size: base * scale))
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let preview = NSBitmapImageRep(cgImage: renderIcon(size: 1024))
try! preview.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
