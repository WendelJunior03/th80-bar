import AppKit
import Observation
import UniformTypeIdentifiers

/// Um quadro editável de 240×135 com seu próprio contexto de desenho.
final class PixelFrame {
    static let w = TH80Protocol.screenWidth
    static let h = TH80Protocol.screenHeight

    let ctx: CGContext

    init(fill: CGColor = .black) {
        ctx = CGContext(data: nil, width: Self.w, height: Self.h, bitsPerComponent: 8, bytesPerRow: Self.w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(fill)
        ctx.fill(CGRect(x: 0, y: 0, width: Self.w, height: Self.h))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
    }

    convenience init(image: CGImage) {
        self.init()
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: Self.w, height: Self.h))
    }

    var image: CGImage { ctx.makeImage()! }

    var pixels: UnsafeMutablePointer<UInt32> {
        ctx.data!.bindMemory(to: UInt32.self, capacity: Self.w * Self.h)
    }

    func snapshot() -> Data { Data(bytes: ctx.data!, count: Self.w * Self.h * 4) }

    func restore(_ data: Data) {
        data.withUnsafeBytes { ctx.data!.copyMemory(from: $0.baseAddress!, byteCount: data.count) }
    }

    func copy() -> PixelFrame {
        let f = PixelFrame()
        f.restore(snapshot())
        return f
    }

    /// Pixel em coordenadas de tela (y para baixo), formato RGBA da memória.
    func pixel(x: Int, y: Int) -> UInt32 { pixels[y * Self.w + x] }

    func floodFill(x: Int, y: Int, color: UInt32) {
        let w = Self.w, h = Self.h, p = pixels
        let target = p[y * w + x]
        guard target != color else { return }
        var stack = [(x, y)]
        while let (cx, cy) = stack.popLast() {
            var lx = cx
            while lx > 0 && p[cy * w + lx - 1] == target { lx -= 1 }
            var rx = cx
            while rx < w - 1 && p[cy * w + rx + 1] == target { rx += 1 }
            for i in lx...rx {
                p[cy * w + i] = color
                if cy > 0 && p[(cy - 1) * w + i] == target { stack.append((i, cy - 1)) }
                if cy < h - 1 && p[(cy + 1) * w + i] == target { stack.append((i, cy + 1)) }
            }
        }
    }
}

enum EditorTool: String, CaseIterable {
    case brush, eraser, fill, text, picker

    var title: String {
        switch self {
        case .brush: "Pincel"
        case .eraser: "Borracha"
        case .fill: "Balde"
        case .text: "Texto"
        case .picker: "Conta-gotas"
        }
    }

    var icon: String {
        switch self {
        case .brush: "paintbrush.pointed.fill"
        case .eraser: "eraser.fill"
        case .fill: "drop.fill"
        case .text: "textformat"
        case .picker: "eyedropper"
        }
    }
}

@MainActor
@Observable
final class EditorModel {
    var frames: [PixelFrame] = [PixelFrame()]
    var current = 0
    var tool: EditorTool = .brush
    var color = RGBColor(r: 255, g: 255, b: 255)
    var background = RGBColor(r: 0, g: 0, b: 0)
    var brushSize: Double = 4
    var text = "Olá!"
    var fontSize: Double = 28
    var bold = true
    var delayMs: Double = 150
    var onionSkin = true
    var playing = false
    /// Incrementa a cada mudança de pixels, para redesenhar canvas e miniaturas.
    var revision = 0

    private var undoStacks: [ObjectIdentifier: [Data]] = [:]
    private var saveWork: DispatchWorkItem?

    var frame: PixelFrame { frames[current] }
    var canAddFrame: Bool { frames.count < TH80Protocol.maxFrames }

    init() { load() }

    // MARK: Desenho

    func beginStroke() {
        let id = ObjectIdentifier(frame)
        var stack = undoStacks[id, default: []]
        stack.append(frame.snapshot())
        if stack.count > 40 { stack.removeFirst() }
        undoStacks[id] = stack
    }

    func endStroke() {
        touch()
    }

    /// Pontos em coordenadas da tela do teclado (y para baixo).
    func strokeSegment(from a: CGPoint, to b: CGPoint) {
        let ctx = frame.ctx
        let c = tool == .eraser ? background : color
        ctx.setStrokeColor(c.cgColor)
        ctx.setLineWidth(brushSize)
        ctx.move(to: flip(a))
        ctx.addLine(to: flip(b))
        ctx.strokePath()
    }

    func fill(at p: CGPoint) {
        guard let (x, y) = pixelCoords(p) else { return }
        beginStroke()
        frame.floodFill(x: x, y: y, color: color.rgbaWord)
        touch()
    }

    func pickColor(at p: CGPoint) {
        guard let (x, y) = pixelCoords(p) else { return }
        color = RGBColor(rgbaWord: frame.pixel(x: x, y: y))
        tool = .brush
    }

    func placeText(at p: CGPoint) {
        guard !text.isEmpty else { return }
        beginStroke()
        let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color.nsColor])
        let size = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: frame.ctx, flipped: false)
        let q = flip(p)
        str.draw(at: NSPoint(x: q.x - size.width / 2, y: q.y - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        touch()
    }

    func clearFrame() {
        beginStroke()
        frame.ctx.setFillColor(background.cgColor)
        frame.ctx.fill(CGRect(x: 0, y: 0, width: PixelFrame.w, height: PixelFrame.h))
        touch()
    }

    func undo() {
        let id = ObjectIdentifier(frame)
        guard let last = undoStacks[id]?.popLast() else { NSSound.beep(); return }
        frame.restore(last)
        touch()
    }

    private func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: CGFloat(PixelFrame.h) - p.y) }

    private func pixelCoords(_ p: CGPoint) -> (Int, Int)? {
        let x = Int(p.x), y = Int(p.y)
        guard (0..<PixelFrame.w).contains(x), (0..<PixelFrame.h).contains(y) else { return nil }
        return (x, y)
    }

    // MARK: Quadros

    func addFrame(duplicate: Bool) {
        guard canAddFrame else { return }
        let f = duplicate ? frame.copy() : PixelFrame(fill: background.cgColor)
        frames.insert(f, at: current + 1)
        current += 1
        touch()
    }

    func deleteFrame() {
        guard frames.count > 1 else { clearFrame(); return }
        frames.remove(at: current)
        current = min(current, frames.count - 1)
        touch()
    }

    func moveFrame(by delta: Int) {
        let target = current + delta
        guard frames.indices.contains(target) else { return }
        frames.swapAt(current, target)
        current = target
        touch()
    }

    func newProject() {
        frames = [PixelFrame(fill: background.cgColor)]
        current = 0
        undoStacks = [:]
        touch()
    }

    // MARK: Importar / exportar

    func importMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .gif]
        panel.message = "A imagem ou GIF vira os quadros do desenho (até 18)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let media = try? MediaEncoder.load(url: url) else { NSSound.beep(); return }
        frames = media.frames.map { PixelFrame(image: $0) }
        current = 0
        if media.frames.count > 1 { delayMs = Double(min(1000, media.delayMs)) }
        undoStacks = [:]
        touch()
    }

    func exportGIF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "desenho-th80.gif"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delayMs / 1000]] as CFDictionary
        frames.forEach { CGImageDestinationAddImage(dest, $0.image, frameProps) }
        CGImageDestinationFinalize(dest)
    }

    var preparedMedia: PreparedMedia {
        PreparedMedia(frames: frames.map(\.image), delayMs: Int(delayMs), originalFrameCount: frames.count)
    }

    // MARK: Salvamento automático

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TH80Bar/Desenho", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func touch() {
        revision += 1
        saveWork?.cancel()
        let images = frames.map(\.image)
        let delay = delayMs
        let work = DispatchWorkItem {
            let dir = Self.folder
            try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
            for (i, img) in images.enumerated() {
                let url = dir.appendingPathComponent(String(format: "quadro-%02d.png", i))
                if let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(d, img, nil)
                    CGImageDestinationFinalize(d)
                }
            }
            try? "\(Int(delay))".write(to: dir.appendingPathComponent("intervalo.txt"), atomically: true, encoding: .utf8)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func delayChanged() { touch() }

    private func load() {
        let dir = Self.folder
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let loaded = files.compactMap { url -> PixelFrame? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            return PixelFrame(image: img)
        }
        if !loaded.isEmpty { frames = Array(loaded.prefix(TH80Protocol.maxFrames)) }
        if let s = try? String(contentsOf: dir.appendingPathComponent("intervalo.txt"), encoding: .utf8),
           let d = Double(s) { delayMs = d }
    }
}

extension RGBColor {
    /// No mesmo espaço de cor dos quadros, para o valor gravado ser exatamente o escolhido.
    var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1])!
    }
    var nsColor: NSColor { NSColor(deviceRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    /// Palavra RGBA como fica na memória do CGContext (little endian: R no byte baixo).
    var rgbaWord: UInt32 { UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | 0xFF00_0000 }

    init(rgbaWord v: UInt32) {
        self.init(r: Int(v & 0xFF), g: Int(v >> 8 & 0xFF), b: Int(v >> 16 & 0xFF))
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? .white
        self.init(r: Int((c.redComponent * 255).rounded()), g: Int((c.greenComponent * 255).rounded()),
                  b: Int((c.blueComponent * 255).rounded()))
    }
}
