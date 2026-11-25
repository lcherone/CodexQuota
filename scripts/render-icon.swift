import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: side, height: side)
let ink = NSColor(calibratedRed: 0.08, green: 0.32, blue: 0.27, alpha: 1)
let cream = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.89, alpha: 1)
let plate = NSBezierPath(roundedRect: rect.insetBy(dx: side * 0.06, dy: side * 0.06), xRadius: side * 0.22, yRadius: side * 0.22)
ink.setFill()
plate.fill()
let ring = NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.24, dy: side * 0.24))
ring.lineWidth = side * 0.055
cream.withAlphaComponent(0.28).setStroke()
ring.stroke()
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: side * 0.26, startAngle: 210, endAngle: -40, clockwise: true)
arc.lineWidth = side * 0.055
arc.lineCapStyle = .round
cream.setStroke()
arc.stroke()
image.unlockFocus()

guard CommandLine.arguments.count > 1,
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not render the icon.\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
