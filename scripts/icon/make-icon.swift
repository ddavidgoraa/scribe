// Draws Scribe's app icon (1024×1024 master) on the macOS icon grid:
// a white sheet in a continuous-corner squircle, two lines of text and an ink-blue caret.
// Usage: swift scripts/icon/make-icon.swift <out.png>
import AppKit
import SwiftUI

let size: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// macOS grid: 824×824 body, 100 pt margins, continuous corners.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: body).cgPath

// Soft drop shadow, as on system icons.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
cg.addPath(squircle)
cg.setFillColor(color(0xFFFFFF))
cg.fillPath()
cg.restoreGState()

// The sheet: white fading to a very light paper grey.
cg.saveGState()
cg.addPath(squircle)
cg.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0xFFFFFF), color(0xEEF0F4)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
cg.restoreGState()

// Text: a heading and two lines, then the caret where writing continues. The group is
// centred optically on the sheet.
func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, _ fill: CGColor) {
    cg.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                      cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.setFillColor(fill)
    cg.fillPath()
}
let ink = color(0x1C1C1E), line = color(0xC3C7D0), accent = color(0x2D5BE3)
let left: CGFloat = 262
bar(left, 576, 500, 64, radius: 32, ink)               // heading
bar(left, 478, 500, 40, radius: 20, line)              // text
bar(left, 388, 290, 40, radius: 20, line)              // last line…
bar(left + 290 + 30, 352, 26, 112, radius: 13, accent) // …and the caret

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote", out.path)
