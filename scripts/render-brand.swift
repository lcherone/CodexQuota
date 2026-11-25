import AppKit

let ink = NSColor(calibratedRed: 0.078, green: 0.322, blue: 0.271, alpha: 1)
let cream = NSColor(calibratedRed: 0.961, green: 0.941, blue: 0.890, alpha: 1)
let inkDeep = NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.14, alpha: 1)

func drawMark(in rect: NSRect) {
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    ink.setFill()
    plate.fill()
    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.width * 0.22))
    ring.lineWidth = rect.width * 0.055
    cream.withAlphaComponent(0.28).setStroke()
    ring.stroke()
    let arc = NSBezierPath()
    arc.appendArc(
        withCenter: NSPoint(x: rect.midX, y: rect.midY),
        radius: rect.width * 0.26,
        startAngle: 210,
        endAngle: -40,
        clockwise: true
    )
    arc.lineWidth = rect.width * 0.055
    arc.lineCapStyle = .round
    cream.setStroke()
    arc.stroke()
}

func paragraph(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: color
    ])
}

func png(_ image: NSImage) -> Data {
    let tiff = image.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

func canvas(width: CGFloat, height: CGFloat, _ draw: (NSRect) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    image.unlockFocus()
    return image
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let panel = NSImage(contentsOf: root.appendingPathComponent("docs/assets/screenshots/panel-light.png"))!

let hero = canvas(width: 1600, height: 680) { rect in
    cream.setFill()
    rect.fill()
    drawMark(in: NSRect(x: 88, y: 430, width: 92, height: 92))
    paragraph("Codex Quota", font: .systemFont(ofSize: 64, weight: .semibold), color: inkDeep)
        .draw(at: NSPoint(x: 88, y: 330))
    paragraph("Pace the week, one slice a day.", font: .systemFont(ofSize: 28, weight: .regular), color: ink)
        .draw(at: NSPoint(x: 90, y: 276))
    let fitted = NSRect(x: 860, y: 36, width: 660, height: 608)
    panel.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1)
}

let social = canvas(width: 1280, height: 640) { rect in
    inkDeep.setFill()
    rect.fill()
    drawMark(in: NSRect(x: 860, y: 170, width: 300, height: 300))
    paragraph("Codex Quota", font: .systemFont(ofSize: 72, weight: .semibold), color: cream)
        .draw(at: NSPoint(x: 88, y: 340))
    paragraph("Pace the week,\none slice a day.", font: .systemFont(ofSize: 36, weight: .regular), color: cream.withAlphaComponent(0.82))
        .draw(at: NSPoint(x: 92, y: 220))
}

let icon = canvas(width: 512, height: 512) { rect in
    drawMark(in: rect.insetBy(dx: 24, dy: 24))
}

try png(hero).write(to: root.appendingPathComponent("docs/assets/branding/hero.png"))
try png(social).write(to: root.appendingPathComponent("docs/assets/branding/social-preview.png"))
try png(icon).write(to: root.appendingPathComponent("docs/assets/branding/mark.png"))
print("wrote branding pngs")
