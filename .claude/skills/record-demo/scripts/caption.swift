// Render a browser-style URL caption bar as a PNG, to stack above page-only
// recordings so reviewers can see which environment/URL is on screen.
//
// Usage: swift caption.swift <url> <width-pt> <scale> <out.png>
//   e.g. swift caption.swift "https://app.example.com/projects/42?tab=settings" 1200 2 bar.png
//
// Host is bold and always visible; the path+query is dimmed and truncated in the
// middle when it doesn't fit, so both the route and the tail stay readable.
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let width = Double(args[2]), let scale = Double(args[3]) else {
  FileHandle.standardError.write("usage: caption.swift <url> <width-pt> <scale> <out.png>\n".data(using: .utf8)!)
  exit(2)
}
let raw = args[1]
let comps = URLComponents(string: raw)
let isSecure = comps?.scheme == "https"
var host = comps?.host ?? raw
if let port = comps?.port { host += ":\(port)" }
var rest = (comps?.percentEncodedPath ?? "")
if let q = comps?.percentEncodedQuery, !q.isEmpty { rest += "?" + q }
if rest == "/" { rest = "" }

let barH = 44.0, pillH = 28.0, padX = 12.0
let bg = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
let pill = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1)
let fg = NSColor(white: 0.96, alpha: 1)
let dim = NSColor(white: 0.62, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(barH * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: barH)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

bg.setFill(); NSRect(x: 0, y: 0, width: width, height: barH).fill()
let pillRect = NSRect(x: padX, y: (barH - pillH) / 2, width: width - padX * 2, height: pillH)
pill.setFill(); NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2, yRadius: pillH / 2).fill()

var x = pillRect.minX + 14
let midY = pillRect.midY
if let lock = NSImage(systemSymbolName: isSecure ? "lock.fill" : "globe", accessibilityDescription: nil)?
  .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [dim]))) {
  let s = lock.size
  lock.draw(in: NSRect(x: x, y: midY - s.height / 2, width: s.width, height: s.height))
  x += s.width + 8
}

let hostAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: fg]
let hostStr = NSAttributedString(string: host, attributes: hostAttrs)
let hostSize = hostStr.size()
let right = pillRect.maxX - 14
hostStr.draw(at: NSPoint(x: x, y: midY - hostSize.height / 2))
x += hostSize.width

if !rest.isEmpty, right - x > 24 {
  let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle
  let restAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: dim, .paragraphStyle: para]
  let restStr = NSAttributedString(string: rest, attributes: restAttrs)
  let h = restStr.size().height
  restStr.draw(in: NSRect(x: x, y: midY - h / 2, width: right - x, height: h))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[4]))
