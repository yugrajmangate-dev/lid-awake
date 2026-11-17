import Cocoa
// Usage: icon <out.iconset dir>
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88)
    let bg = NSBezierPath(roundedRect: r, xRadius: s*0.2, yRadius: s*0.2)
    NSGradient(colors: [NSColor(red: 1, green: 0.65, blue: 0.2, alpha: 1), NSColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 1)])!.draw(in: bg, angle: -90)
    if let sym = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s*0.5, weight: .semibold)) {
        let t = sym.tinted(.white)
        let z = t.size
        t.draw(in: NSRect(x: (s-z.width)/2, y: (s-z.height)/2, width: z.width, height: z.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
extension NSImage { func tinted(_ c: NSColor) -> NSImage {
    let i = self.copy() as! NSImage; i.lockFocus(); c.set()
    NSRect(origin: .zero, size: i.size).fill(using: .sourceAtop); i.unlockFocus(); return i } }
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base*2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
