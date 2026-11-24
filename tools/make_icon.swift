// Gera Resources/AppIcon.icns: teclado creme com a telinha acesa e brilho RGB por baixo.
import AppKit

func render(_ size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: rgb, components: [r, g, b, a])! }
    func grad(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: locs)! }

    // Fundo: quadrado arredondado grafite (grade de ícones do macOS: 824 px com margem de 100)
    let bg = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0, 0, 0, 0.45))
    ctx.addPath(bg); ctx.setFillColor(c(0.13, 0.13, 0.16)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    ctx.drawLinearGradient(grad([c(0.20, 0.20, 0.25), c(0.08, 0.08, 0.11)], [0, 1]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    // Brilho RGB por baixo do teclado
    let colors = [c(1, 0.2, 0.4), c(1, 0.6, 0.1), c(0.2, 0.9, 0.5), c(0.1, 0.6, 1), c(0.6, 0.3, 1)]
    for (i, col) in colors.enumerated() {
        let x = 230 + CGFloat(i) * 140
        ctx.drawRadialGradient(grad([col.copy(alpha: 0.75)!, col.copy(alpha: 0)!], [0, 1]),
                               startCenter: CGPoint(x: x, y: 300), startRadius: 0,
                               endCenter: CGPoint(x: x, y: 300), endRadius: 190, options: [])
    }
    ctx.restoreGState()

    // Corpo do teclado (creme), levemente em perspectiva
    let body = CGRect(x: 170, y: 300, width: 684, height: 400)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: c(0, 0, 0, 0.5))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 54, cornerHeight: 54, transform: nil))
    ctx.setFillColor(c(0.90, 0.87, 0.80)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 54, cornerHeight: 54, transform: nil)); ctx.clip()
    ctx.drawLinearGradient(grad([c(0.96, 0.94, 0.89), c(0.82, 0.79, 0.72)], [0, 1]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    // Teclas
    func key(_ r: CGRect) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 4, color: c(0, 0, 0, 0.25))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.setFillColor(c(0.95, 0.93, 0.88)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 9, dy: 9).offsetBy(dx: 0, dy: 4), cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.setFillColor(c(1, 0.99, 0.96)); ctx.fillPath()
    }
    let k: CGFloat = 76, gap: CGFloat = 10
    // linha de cima (F) à esquerda da telinha
    for i in 0..<4 { key(CGRect(x: 200 + CGFloat(i) * (k + gap), y: 590, width: k, height: k)) }
    // demais linhas: duas completas, uma com a seta para cima e a de baixo com espaço e setas
    for i in 0..<7 { key(CGRect(x: 200 + CGFloat(i) * (k + gap), y: 500, width: k, height: k)) }
    for i in [0, 1, 2, 3, 4, 6] { key(CGRect(x: 200 + CGFloat(i) * (k + gap), y: 414, width: k, height: k)) }
    key(CGRect(x: 200 + 5 * (k + gap), y: 414, width: k, height: k)) // seta para cima
    key(CGRect(x: 200, y: 328, width: k, height: k))
    key(CGRect(x: 286, y: 328, width: 2 * k + gap, height: k))       // espaço
    for i in 3..<7 { key(CGRect(x: 200 + CGFloat(i) * (k + gap), y: 328, width: k, height: k)) }

    // Telinha: moldura vinho + tela acesa com degradê
    let bezel = CGRect(x: 552, y: 572, width: 272, height: 112)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 6, color: c(0, 0, 0, 0.35))
    ctx.addPath(CGPath(roundedRect: bezel, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(c(0.55, 0.10, 0.16)); ctx.fillPath()
    ctx.restoreGState()
    let screen = bezel.insetBy(dx: 16, dy: 14)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.clip()
    ctx.drawLinearGradient(grad([c(1, 0.25, 0.55), c(0.55, 0.3, 1), c(0.1, 0.75, 1)], [0, 0.5, 1]),
                           start: CGPoint(x: screen.minX, y: screen.maxY), end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    // coração em pixel art na tela
    let heart = ["01100110", "11111111", "11111111", "01111110", "00111100", "00011000"]
    let px: CGFloat = 9
    let ox = screen.midX - 4 * px, oy = screen.midY + 3 * px
    ctx.setFillColor(c(1, 1, 1, 0.95))
    for (r, line) in heart.enumerated() {
        for (col, ch) in line.enumerated() where ch == "1" {
            ctx.fill(CGRect(x: ox + CGFloat(col) * px, y: oy - CGFloat(r + 1) * px, width: px, height: px))
        }
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: out).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: render(px))
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! NSBitmapImageRep(cgImage: render(1024)).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out).appendingPathComponent("icon-1024.png"))
print("ok")
