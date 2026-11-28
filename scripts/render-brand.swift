import AppKit
import ImageIO
import UniformTypeIdentifiers

// Documentation artwork only. Screenshots are captured from the real app.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let branding = root.appendingPathComponent("docs/assets/branding")
let screenshots = root.appendingPathComponent("docs/assets/screenshots")
let demos = root.appendingPathComponent("docs/assets/demos")
for directory in [branding, demos] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
let emerald = NSColor(srgbRed: 20 / 255, green: 82 / 255, blue: 69 / 255, alpha: 1)
let cream = NSColor(srgbRed: 245 / 255, green: 240 / 255, blue: 227 / 255, alpha: 1)
let deep = NSColor(srgbRed: 16 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
let mint = NSColor(srgbRed: 100 / 255, green: 206 / 255, blue: 154 / 255, alpha: 1)
let fontStack = "-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif"

func canvas(_ width: Int, _ height: Int, draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat, canvasHeight: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - top - height, width: width, height: height)
}

func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor, canvasHeight: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    NSAttributedString(string: value, attributes: attributes)
        .draw(at: NSPoint(x: x, y: canvasHeight - top - size * 1.2))
}

func mark(_ frame: NSRect) {
    emerald.setFill()
    NSBezierPath(roundedRect: frame, xRadius: frame.width * 0.22, yRadius: frame.height * 0.22).fill()
    let ring = NSBezierPath(ovalIn: frame.insetBy(dx: frame.width * 0.24, dy: frame.height * 0.24))
    ring.lineWidth = frame.width * 0.055
    cream.withAlphaComponent(0.28).setStroke()
    ring.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: frame.midX, y: frame.midY), radius: frame.width * 0.26,
                  startAngle: 210, endAngle: -40, clockwise: true)
    arc.lineWidth = frame.width * 0.055
    arc.lineCapStyle = .round
    cream.setStroke()
    arc.stroke()
}

func markSVG(x: Int, y: Int, size: Int) -> String {
    """
    <g transform="translate(\(x) \(y)) scale(\(Double(size) / 64))">
    <rect width="64" height="64" rx="14" fill="#145245"/>
    <circle cx="32" cy="32" r="16.5" fill="none" stroke="#F5F0E3" stroke-opacity=".28" stroke-width="3.4"/>
    <path d="M18.2 40.6 A16.6 16.6 0 1 1 44.6 21.4" fill="none" stroke="#F5F0E3" stroke-width="3.4" stroke-linecap="round"/>
    </g>
    """
}

func svg(_ width: Int, _ height: Int, title: String, body: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\" role=\"img\" aria-label=\"\(title)\"><title>\(title)</title>\(body)</svg>"
}

func save(_ bitmap: NSBitmapImageRep, name: String) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: branding.appendingPathComponent(name))
}

func writeSVG(_ contents: String, name: String) throws {
    try contents.write(to: branding.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

for dark in [false, true] {
    let suffix = dark ? "dark" : "light"
    let background = dark ? deep : cream
    let foreground = dark ? cream : deep
    let secondary = dark ? cream.withAlphaComponent(0.74) : emerald
    let backgroundHex = dark ? "#10221D" : "#F5F0E3"
    let foregroundHex = dark ? "#F5F0E3" : "#10221D"
    let secondaryHex = dark ? "#B8C4B6" : "#145245"
    let shotURL = screenshots.appendingPathComponent("overview-\(suffix).png")
    guard let shot = NSImage(contentsOf: shotURL) else { fatalError("Capture \(shotURL.path) first") }
    let hero = canvas(1600, 900) { height in
        background.setFill()
        NSRect(x: 0, y: 0, width: 1600, height: 900).fill()
        mark(rect(88, 82, 76, 76, canvasHeight: height))
        text("Codex Quota", x: 188, top: 93, size: 38, weight: .semibold, color: foreground, canvasHeight: height)
        text("Pace the week,", x: 88, top: 245, size: 76, weight: .semibold, color: foreground, canvasHeight: height)
        text("one slice a day.", x: 88, top: 332, size: 76, weight: .semibold, color: foreground, canvasHeight: height)
        text("A native Mac menu-bar app", x: 92, top: 468, size: 28, color: secondary, canvasHeight: height)
        text("for your Codex allowance.", x: 92, top: 508, size: 28, color: secondary, canvasHeight: height)
        text("ONE WEEK. SEVEN DAILY SLICES.", x: 92, top: 634, size: 17, weight: .medium, color: secondary, canvasHeight: height)
        for index in 0..<7 {
            let box = rect(92 + CGFloat(index) * 98, 680, 82, 32, canvasHeight: height)
            let color = index == 3 ? (dark ? mint : emerald) : foreground.withAlphaComponent(index < 3 ? 0.18 : 0.07)
            color.setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        }
        text("macOS 14+   /   SwiftUI   /   Built from source", x: 92, top: 788, size: 18, color: secondary, canvasHeight: height)
        let shotFrame = rect(1020, 64, 470, 752, canvasHeight: height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: shotFrame, xRadius: 10, yRadius: 10).addClip()
        shot.draw(in: shotFrame, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        text("Real app · offline sample data", x: 1020, top: 835, size: 16, color: secondary, canvasHeight: height)
    }
    try save(hero, name: "hero-\(suffix).png")
    if !dark { try save(hero, name: "hero.png") }
    let encoded = try Data(contentsOf: shotURL).base64EncodedString()
    var slices = ""
    for index in 0..<7 {
        let fill = index == 3 ? (dark ? "#64CE9A" : "#145245") : foregroundHex
        let opacity = index == 3 ? "1" : (index < 3 ? ".18" : ".07")
        slices += "<rect x=\"\(92 + index * 98)\" y=\"680\" width=\"82\" height=\"32\" rx=\"8\" fill=\"\(fill)\" opacity=\"\(opacity)\"/>"
    }
    let body = """
    <rect width="1600" height="900" fill="\(backgroundHex)"/>
    \(markSVG(x: 88, y: 82, size: 76))
    <g font-family="\(fontStack)" fill="\(foregroundHex)">
    <text x="188" y="134" font-size="38" font-weight="600">Codex Quota</text>
    <text x="88" y="320" font-size="76" font-weight="600">Pace the week,</text>
    <text x="88" y="407" font-size="76" font-weight="600">one slice a day.</text>
    <g fill="\(secondaryHex)"><text x="92" y="500" font-size="28">A native Mac menu-bar app</text>
    <text x="92" y="540" font-size="28">for your Codex allowance.</text>
    <text x="92" y="655" font-size="17">ONE WEEK. SEVEN DAILY SLICES.</text>
    <text x="92" y="811" font-size="18">macOS 14+ / SwiftUI / Built from source</text>
    <text x="1020" y="855" font-size="16">Real app · offline sample data</text></g></g>
    \(slices)<defs><clipPath id="panel"><rect x="1020" y="64" width="470" height="752" rx="10"/></clipPath></defs>
    <image x="1020" y="64" width="470" height="752" clip-path="url(#panel)" xlink:href="data:image/png;base64,\(encoded)"/>
    """
    try writeSVG(svg(1600, 900, title: "Codex Quota — pace the week, one slice a day", body: body), name: "hero-\(suffix).svg")
    let wordmark = canvas(960, 160) { height in
        background.setFill()
        NSRect(x: 0, y: 0, width: 960, height: 160).fill()
        mark(rect(16, 16, 128, 128, canvasHeight: height))
        text("Codex Quota", x: 180, top: 41, size: 62, weight: .semibold, color: foreground, canvasHeight: height)
    }
    try save(wordmark, name: "wordmark-\(suffix).png")
    try writeSVG(svg(420, 64, title: "Codex Quota", body: "\(markSVG(x: 0, y: 0, size: 64))<text x=\"80\" y=\"43\" fill=\"\(foregroundHex)\" font-family=\"\(fontStack)\" font-size=\"30\" font-weight=\"600\">Codex Quota</text>"), name: "wordmark-\(suffix).svg")
}
let icon = canvas(512, 512) { height in mark(rect(24, 24, 464, 464, canvasHeight: height)) }
try save(icon, name: "mark.png")
let social = canvas(1280, 640) { height in
    deep.setFill()
    NSRect(x: 0, y: 0, width: 1280, height: 640).fill()
    mark(rect(986, 68, 190, 190, canvasHeight: height))
    text("Codex Quota", x: 76, top: 78, size: 62, weight: .semibold, color: cream, canvasHeight: height)
    text("Pace the week,", x: 76, top: 232, size: 58, weight: .semibold, color: cream, canvasHeight: height)
    text("one slice a day.", x: 76, top: 300, size: 58, weight: .semibold, color: cream, canvasHeight: height)
    text("Your Codex allowance, in the Mac menu bar.", x: 80, top: 408, size: 24, color: cream.withAlphaComponent(0.74), canvasHeight: height)
    for index in 0..<7 {
        let color = index == 3 ? mint : cream.withAlphaComponent(index < 3 ? 0.2 : 0.08)
        color.setFill()
        NSBezierPath(roundedRect: rect(80 + CGFloat(index) * 156, 520, 132, 40, canvasHeight: height), xRadius: 10, yRadius: 10).fill()
    }
}
try save(social, name: "social-preview.png")
var socialSlices = ""
for index in 0..<7 {
    socialSlices += "<rect x=\"\(80 + index * 156)\" y=\"520\" width=\"132\" height=\"40\" rx=\"10\" fill=\"\(index == 3 ? "#64CE9A" : "#F5F0E3")\" opacity=\"\(index == 3 ? "1" : ".15")\"/>"
}
try writeSVG(svg(1280, 640, title: "Codex Quota social preview", body: """
<rect width="1280" height="640" fill="#10221D"/>\(markSVG(x: 986, y: 68, size: 190))
<g fill="#F5F0E3" font-family="\(fontStack)"><text x="76" y="145" font-size="62" font-weight="600">Codex Quota</text>
<text x="76" y="294" font-size="58" font-weight="600">Pace the week,</text><text x="76" y="362" font-size="58" font-weight="600">one slice a day.</text>
<text x="80" y="438" font-size="24" opacity=".74">Your Codex allowance, in the Mac menu bar.</text></g>\(socialSlices)
"""), name: "social-preview.svg")

for (name, label, width) in [("platform", "macOS 14+", 104), ("swift", "Swift 6", 84), ("source", "Build from source", 152)] {
    let badge = svg(width, 28, title: label, body: "<rect width=\"\(width)\" height=\"28\" rx=\"7\" fill=\"#145245\"/><text x=\"\(width / 2)\" y=\"19\" fill=\"#F5F0E3\" font-family=\"\(fontStack)\" font-size=\"12\" text-anchor=\"middle\">\(label)</text>")
    try writeSVG(badge, name: "badge-\(name).svg")
}

let frames = ["overview-dark", "usage-dark", "statistics-dark", "limits-dark", "activity-dark", "settings-dark", "overview-dark"]
let gifURL = demos.appendingPathComponent("product-tour.gif")
guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    fatalError("Could not create the demo GIF")
}
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for name in frames {
    guard let frame = NSImage(contentsOf: screenshots.appendingPathComponent("\(name).png")) else { fatalError("Capture \(name) first") }
    let bitmap = canvas(400, 640) { height in
        NSColor(white: 0.105, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 400, height: 640).fill()
        frame.draw(in: rect(0, 0, 400, 640, canvasHeight: height), from: .zero, operation: .sourceOver, fraction: 1)
    }
    CGImageDestinationAddImage(gif, bitmap.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 2.2]] as CFDictionary)
}
guard CGImageDestinationFinalize(gif) else { fatalError("Could not finish the demo GIF") }
print("Rendered hero, wordmarks, icon, badges, social preview and a 15-second real-capture tour.")
