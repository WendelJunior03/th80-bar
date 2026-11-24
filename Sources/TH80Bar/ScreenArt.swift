import AppKit

/// Geradores de imagens/animações para a tela de 240×135.
enum ScreenArt {
    static let w = TH80Protocol.screenWidth
    static let h = TH80Protocol.screenHeight
    static let frameCount = TH80Protocol.maxFrames

    /// Cria um quadro; o desenho usa coordenadas com origem embaixo à esquerda.
    static func canvas(_ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
    }

    static func hue(_ h: Double, s: Double = 1, b: Double = 1, a: Double = 1) -> CGColor {
        let c = NSColor(deviceHue: h - floor(h), saturation: s, brightness: b, alpha: a)
        return color(c.redComponent, c.greenComponent, c.blueComponent, a)
    }

    @discardableResult
    static func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .bold, color: NSColor,
                     center: CGPoint, design: NSFontDescriptor.SystemDesign = .rounded) -> CGSize {
        let str = attributed(s, size: size, weight: weight, color: color, design: design)
        let sz = str.size()
        str.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
        return sz
    }

    static func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight = .bold, color: NSColor,
                           design: NSFontDescriptor.SystemDesign = .rounded) -> NSAttributedString {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(design), let f = NSFont(descriptor: d, size: size) { font = f }
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }

    static func symbol(_ name: String, size: CGFloat, color: NSColor, center: CGPoint) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        let s = img.size
        img.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
    }

    /// Gerador pseudoaleatório determinístico (as animações saem sempre iguais).
    struct Rand {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    // MARK: - Galeria

    struct Animation: Identifiable {
        let id: String
        let name: String
        let delayMs: Int
        let make: () -> [CGImage]
    }

    static let gallery: [Animation] = [
        .init(id: "matrix", name: "Chuva digital", delayMs: 90, make: matrix),
        .init(id: "stars", name: "Hiperespaço", delayMs: 70, make: starfield),
        .init(id: "synth", name: "Synthwave", delayMs: 80, make: synthwave),
        .init(id: "plasma", name: "Plasma", delayMs: 90, make: plasma),
        .init(id: "heart", name: "Coração", delayMs: 70, make: heart),
        .init(id: "snow", name: "Neve", delayMs: 100, make: snow),
        .init(id: "spin", name: "Arco-íris", delayMs: 70, make: spinner),
        .init(id: "waves", name: "Ondas", delayMs: 80, make: waves),
    ]

    private static func frames(_ draw: (Double, CGContext) -> Void) -> [CGImage] {
        (0..<frameCount).map { i in canvas { draw(Double(i) / Double(frameCount), $0) } }
    }

    static func matrix() -> [CGImage] {
        var rnd = Rand(state: 7)
        let cols = 24, cell: CGFloat = 10, trail = 9
        let span = Double(h) / Double(cell) + Double(trail)
        let columns = (0..<cols).map { _ in (offset: rnd.next() * span, speed: Double(1 + Int(rnd.next() * 2))) }
        let glyphs = Array("アカサタナハマヤラワ0123456789ｦｱｳｴｵｶｷｸｹｺ")
        let seeds = (0..<(cols * 20)).map { _ in Int(rnd.next() * 1000) }
        return frames { t, _ in
            for (c, col) in columns.enumerated() {
                let head = (col.offset + col.speed * t * span).truncatingRemainder(dividingBy: span)
                for k in 0..<trail {
                    let row = Int(head) - k
                    guard row >= 0, Double(row) < Double(h) / Double(cell) else { continue }
                    let fade = 1 - Double(k) / Double(trail)
                    let g = glyphs[(seeds[(c * 20 + row) % seeds.count] + Int(t * 18) * (k == 0 ? 1 : 0)) % glyphs.count]
                    let colr = k == 0 ? NSColor(deviceRed: 0.8, green: 1, blue: 0.85, alpha: 1)
                        : NSColor(deviceRed: 0, green: fade, blue: 0.25 * fade, alpha: 1)
                    text(String(g), size: 10, weight: .medium, color: colr,
                         center: CGPoint(x: CGFloat(c) * cell + 5, y: CGFloat(h) - CGFloat(row) * cell - 5), design: .monospaced)
                }
            }
        }
    }

    static func starfield() -> [CGImage] {
        var rnd = Rand(state: 3)
        let stars = (0..<140).map { _ in (a: rnd.next() * 2 * .pi, r0: rnd.next(), tint: rnd.next()) }
        let cx = Double(w) / 2, cy = Double(h) / 2, maxR = 150.0
        return frames { t, ctx in
            for s in stars {
                let r = (s.r0 + t).truncatingRemainder(dividingBy: 1)
                let d = r * r * maxR
                let size = 0.6 + r * 2.6
                let x = cx + cos(s.a) * d, y = cy + sin(s.a) * d
                ctx.setFillColor(color(0.75 + 0.25 * s.tint, 0.85, 1, min(1, r * 3)))
                ctx.fillEllipse(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
            }
        }
    }

    static func synthwave() -> [CGImage] {
        let horizon = 58.0
        return frames { t, ctx in
            // céu
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [color(0.10, 0.02, 0.25), color(0.55, 0.10, 0.45), color(1, 0.45, 0.30)] as CFArray,
                                 locations: [1, 0.45, 0])!
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: Double(h)), options: [])
            // sol com faixas que descem
            let sun = CGRect(x: 120 - 34, y: horizon - 10, width: 68, height: 68)
            ctx.saveGState()
            ctx.addEllipse(in: sun)
            ctx.clip()
            let sunGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [color(1, 0.9, 0.3), color(1, 0.3, 0.55)] as CFArray, locations: [1, 0])!
            ctx.drawLinearGradient(sunGrad, start: CGPoint(x: 0, y: sun.maxY), end: CGPoint(x: 0, y: sun.minY), options: [])
            ctx.setFillColor(color(0.55, 0.10, 0.45))
            for i in 0..<5 {
                let y = horizon - 10 + (Double(i) + t) * 9
                ctx.fill(CGRect(x: sun.minX, y: y, width: sun.width, height: 1.5 + Double(i) * 0.5))
            }
            ctx.restoreGState()
            // chão
            ctx.setFillColor(color(0.06, 0.0, 0.14))
            ctx.fill(CGRect(x: 0, y: 0, width: Double(w), height: horizon))
            ctx.setStrokeColor(color(1, 0.2, 0.9))
            ctx.setLineWidth(1)
            for i in 0..<8 {
                let k = (Double(i) + t) / 8
                let y = horizon * (1 - k * k)
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: Double(w), y: y))
            }
            for i in -10...10 {
                ctx.move(to: CGPoint(x: 120 + Double(i) * 6, y: horizon))
                ctx.addLine(to: CGPoint(x: 120 + Double(i) * 40, y: 0))
            }
            ctx.strokePath()
        }
    }

    static func plasma() -> [CGImage] {
        (0..<frameCount).map { i in
            let t = Double(i) / Double(frameCount) * 2 * .pi
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let fx = Double(x) / 30, fy = Double(y) / 30
                    var v = sin(fx + t) + sin(fy + t)
                    v += sin((fx + fy) / 2 + t) + sin(sqrt(fx * fx + fy * fy) - t)
                    let hue = v / 8 + 0.5
                    let r = 0.5 + 0.5 * sin(2 * .pi * hue), g = 0.5 + 0.5 * sin(2 * .pi * hue + 2.1), b = 0.5 + 0.5 * sin(2 * .pi * hue + 4.2)
                    let o = (y * w + x) * 4
                    p[o] = UInt8(r * 255); p[o + 1] = UInt8(g * 255); p[o + 2] = UInt8(b * 255); p[o + 3] = 255
                }
            }
            return ctx.makeImage()!
        }
    }

    static func heart() -> [CGImage] {
        var rnd = Rand(state: 11)
        let sparkles = (0..<30).map { _ in (x: rnd.next() * Double(w), y: rnd.next() * Double(h), p: rnd.next()) }
        return frames { t, ctx in
            ctx.setFillColor(color(0.12, 0.02, 0.10))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            for s in sparkles {
                let a = max(0, sin(2 * .pi * (t + s.p)))
                ctx.setFillColor(color(1, 0.6, 0.8, a))
                ctx.fillEllipse(in: CGRect(x: s.x, y: s.y, width: 2, height: 2))
            }
            // batida dupla
            let beat = pow(max(0, sin(2 * .pi * t * 2)), 6)
            let scale = 1 + 0.16 * beat
            ctx.saveGState()
            ctx.translateBy(x: 120, y: 62)
            ctx.scaleBy(x: scale * 2.1, y: scale * 2.1)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -18))
            path.addCurve(to: CGPoint(x: -22, y: 8), control1: CGPoint(x: -14, y: -8), control2: CGPoint(x: -24, y: -2))
            path.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: -20, y: 22), control2: CGPoint(x: -4, y: 20))
            path.addCurve(to: CGPoint(x: 22, y: 8), control1: CGPoint(x: 4, y: 20), control2: CGPoint(x: 20, y: 22))
            path.addCurve(to: CGPoint(x: 0, y: -18), control1: CGPoint(x: 24, y: -2), control2: CGPoint(x: 14, y: -8))
            ctx.addPath(path)
            ctx.setShadow(offset: .zero, blur: 8 + 10 * beat, color: color(1, 0.2, 0.5))
            ctx.setFillColor(color(1, 0.18 + 0.2 * beat, 0.42))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    static func snow() -> [CGImage] {
        var rnd = Rand(state: 5)
        let flakes = (0..<90).map { _ in (x: rnd.next() * Double(w), y0: rnd.next(), speed: Double(1 + Int(rnd.next() * 2)), size: 1 + rnd.next() * 2.5, ph: rnd.next()) }
        return frames { t, ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color(0.02, 0.04, 0.15), color(0.10, 0.20, 0.40)] as CFArray, locations: [1, 0])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: Double(h)), end: .zero, options: [])
            ctx.setFillColor(color(0.92, 0.95, 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: 10))
            for f in flakes {
                let y = Double(h) - ((f.y0 + f.speed * t).truncatingRemainder(dividingBy: 1)) * Double(h + 6)
                let x = f.x + sin(2 * .pi * (t + f.ph)) * 4
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: f.size, height: f.size))
            }
        }
    }

    static func spinner() -> [CGImage] {
        (0..<frameCount).map { i in
            let t = Double(i) / Double(frameCount)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let dx = Double(x) - 120, dy = Double(y) - 67.5
                    let ang = atan2(dy, dx) / (2 * .pi) + t
                    let dist = sqrt(dx * dx + dy * dy)
                    let hh = ang - floor(ang)
                    let k = min(1, dist / 40)
                    let r = 0.5 + 0.5 * sin(2 * .pi * hh), g = 0.5 + 0.5 * sin(2 * .pi * hh + 2.1), b = 0.5 + 0.5 * sin(2 * .pi * hh + 4.2)
                    let o = (y * w + x) * 4
                    p[o] = UInt8(r * k * 255); p[o + 1] = UInt8(g * k * 255); p[o + 2] = UInt8(b * k * 255); p[o + 3] = 255
                }
            }
            return ctx.makeImage()!
        }
    }

    static func waves() -> [CGImage] {
        frames { t, ctx in
            ctx.setFillColor(color(0.02, 0.03, 0.10))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let layers: [(CGColor, Double, Double, Int)] = [
                (color(0.0, 0.8, 1, 0.55), 80, 14, 1), (color(0.6, 0.2, 1, 0.55), 62, 12, 2), (color(1, 0.2, 0.6, 0.6), 44, 10, 3),
            ]
            for (c, base, amp, k) in layers {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 0))
                for x in stride(from: 0.0, through: Double(w), by: 2) {
                    let y = base + amp * sin(x / 240 * 2 * .pi * Double(k) + 2 * .pi * t * Double(k))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: Double(w), y: 0))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(c)
                ctx.fillPath()
            }
        }
    }

    // MARK: - Texto animado

    enum TextStyle: String, CaseIterable, Identifiable {
        case typewriter = "Máquina de escrever"
        case marquee = "Letreiro rolando"
        case blink = "Piscando"
        case rainbow = "Arco-íris"
        var id: String { rawValue }
    }

    static func animatedText(_ s: String, style: TextStyle, color fg: RGBColor, background bg: RGBColor) -> (frames: [CGImage], delayMs: Int) {
        let text = s.isEmpty ? " " : s
        let fgNS = NSColor(deviceRed: Double(fg.r) / 255, green: Double(fg.g) / 255, blue: Double(fg.b) / 255, alpha: 1)
        func fitSize(_ str: String, max m: CGFloat) -> CGFloat {
            var size = m
            while size > 12 && attributed(str, size: size, color: fgNS).size().width > 220 { size -= 2 }
            return size
        }
        func base(_ ctx: CGContext) {
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        let center = CGPoint(x: 120, y: 67)
        switch style {
        case .typewriter:
            let chars = Array(text)
            let size = fitSize(text + "▌", max: 44)
            let steps = min(chars.count, 13)
            var out: [CGImage] = []
            for k in 1...steps {
                let n = Int((Double(chars.count) * Double(k) / Double(steps)).rounded(.up))
                let shown = String(chars.prefix(n))
                out.append(canvas { ctx in base(ctx); typeLine(shown, cursor: true, full: text, size: size, color: fgNS) })
            }
            for k in 0..<min(5, frameCount - steps) {
                out.append(canvas { ctx in base(ctx); typeLine(text, cursor: k % 2 == 1, full: text, size: size, color: fgNS) })
            }
            return (out, 140)
        case .marquee:
            let str = attributed(text, size: 70, color: fgNS)
            let tw = str.size().width
            let total = Double(w) + tw
            let out = (0..<frameCount).map { i in
                canvas { ctx in
                    base(ctx)
                    let x = Double(w) - total * Double(i) / Double(frameCount)
                    str.draw(at: NSPoint(x: x, y: 67 - str.size().height / 2))
                }
            }
            return (out, 90)
        case .blink:
            let size = fitSize(text, max: 60)
            return ([canvas { ctx in base(ctx); _ = ScreenArt.text(text, size: size, color: fgNS, center: center) },
                     canvas { ctx in base(ctx) }], 500)
        case .rainbow:
            let size = fitSize(text, max: 56)
            let out = (0..<frameCount).map { i in
                canvas { ctx in
                    base(ctx)
                    let full = NSMutableAttributedString()
                    for (j, ch) in text.enumerated() {
                        let c = NSColor(deviceHue: (Double(j) * 0.08 + Double(i) / Double(frameCount)).truncatingRemainder(dividingBy: 1),
                                        saturation: 0.9, brightness: 1, alpha: 1)
                        full.append(attributed(String(ch), size: size, color: c))
                    }
                    let sz = full.size()
                    full.draw(at: NSPoint(x: 120 - sz.width / 2, y: 67 - sz.height / 2))
                }
            }
            return (out, 80)
        }
    }

    /// Linha da máquina de escrever, alinhada como o texto completo (não "pula" ao crescer).
    private static func typeLine(_ shown: String, cursor: Bool, full: String, size: CGFloat, color: NSColor) {
        let fullW = attributed(full, size: size, color: color).size().width
        let str = attributed(shown + (cursor ? "▌" : ""), size: size, color: color)
        str.draw(at: NSPoint(x: 120 - fullW / 2, y: 67 - str.size().height / 2))
    }

    // MARK: - Ausente

    static func awayImage(text: String) -> CGImage {
        canvas { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color(0.05, 0.06, 0.12), color(0.12, 0.10, 0.25)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
            symbol("lock.fill", size: 30, color: NSColor(deviceWhite: 0.9, alpha: 1), center: CGPoint(x: 120, y: 88))
            ScreenArt.text(text, size: 26, color: .white, center: CGPoint(x: 120, y: 42))
        }
    }

    // MARK: - Cartão do dia

    struct DayInfo {
        var date = Date()
        var temperature: Int?
        var minTemp: Int?
        var maxTemp: Int?
        var weatherSymbol = "cloud.sun.fill"
        var weatherText = ""
        var city = ""
        var event: String?
    }

    static func dailyCard(_ info: DayInfo) -> CGImage {
        canvas { ctx in
            let hour = Calendar.current.component(.hour, from: info.date)
            let top = hour < 12 ? color(0.98, 0.62, 0.35) : color(0.25, 0.35, 0.80)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color(0.06, 0.08, 0.22), top] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])

            let pt = Locale(identifier: "pt_BR")
            let weekday = info.date.formatted(.dateTime.weekday(.wide).locale(pt)).capitalized
            let day = info.date.formatted(.dateTime.day().month(.wide).locale(pt))
            let w1 = attributed(weekday, size: 22, color: .white)
            w1.draw(at: NSPoint(x: 12, y: 96))
            attributed(day, size: 14, weight: .semibold, color: NSColor(deviceWhite: 1, alpha: 0.85)).draw(at: NSPoint(x: 12, y: 78))

            if let t = info.temperature {
                symbol(info.weatherSymbol, size: 26, color: .white, center: CGPoint(x: 200, y: 108))
                ScreenArt.text("\(t)°", size: 22, color: .white, center: CGPoint(x: 200, y: 78))
                if let mn = info.minTemp, let mx = info.maxTemp {
                    ScreenArt.text("\(mn)° / \(mx)°", size: 10, weight: .semibold, color: NSColor(deviceWhite: 1, alpha: 0.8),
                                   center: CGPoint(x: 200, y: 62))
                }
            }

            ctx.setFillColor(color(0, 0, 0, 0.35))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 8, y: 8, width: 224, height: 40), cornerWidth: 9, cornerHeight: 9, transform: nil))
            ctx.fillPath()
            symbol(info.event == nil ? "checkmark.circle" : "calendar", size: 14, color: .white, center: CGPoint(x: 24, y: 28))
            let ev = attributed(info.event ?? (info.weatherText.isEmpty ? "Bom dia!" : info.weatherText), size: 13, weight: .semibold, color: .white)
            ev.draw(with: NSRect(x: 40, y: 18, width: 186, height: 20), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}
