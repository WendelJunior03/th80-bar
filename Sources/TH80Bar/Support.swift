import AppKit
import SwiftUI

struct RGBColor: Equatable, Hashable {
    var r: Int, g: Int, b: Int

    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    init(r: Int, g: Int, b: Int) {
        self.r = min(255, max(0, r)); self.g = min(255, max(0, g)); self.b = min(255, max(0, b))
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(r: v >> 16 & 0xFF, g: v >> 8 & 0xFF, b: v & 0xFF)
    }

    /// Cor saturada a partir de um matiz 0…1 (LEDs ficam melhores com saturação e brilho máximos).
    init(hue: Double) {
        let c = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1)
        self.init(r: Int((c.redComponent * 255).rounded()), g: Int((c.greenComponent * 255).rounded()),
                  b: Int((c.blueComponent * 255).rounded()))
    }

    var hue: Double {
        NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1).hueComponent
    }

    static let presets: [RGBColor] = [
        .init(r: 255, g: 255, b: 255), .init(r: 255, g: 0, b: 0), .init(r: 255, g: 80, b: 0),
        .init(r: 255, g: 200, b: 0), .init(r: 0, g: 255, b: 0), .init(r: 0, g: 255, b: 160),
        .init(r: 0, g: 200, b: 255), .init(r: 0, g: 60, b: 255), .init(r: 140, g: 0, b: 255),
        .init(r: 255, g: 0, b: 200),
    ]
}

/// Guarda os quadros do último envio (para a prévia e para reenviar com a tela de "ausente").
enum LastUploadStore {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TH80Bar/UltimoEnvio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func load() -> CGImage? { loadAll()?.frames.first }

    static func loadAll() -> (frames: [CGImage], delayMs: Int)? {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let frames = files.compactMap { url -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        guard !frames.isEmpty else { return nil }
        let delay = (try? String(contentsOf: dir.appendingPathComponent("intervalo.txt"), encoding: .utf8)).flatMap { Int($0) } ?? 100
        return (frames, delay)
    }

    static func save(_ frames: [CGImage], delayMs: Int) {
        let d = dir
        try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
        for (i, img) in frames.enumerated() {
            let url = d.appendingPathComponent(String(format: "quadro-%02d.png", i))
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        try? "\(delayMs)".write(to: d.appendingPathComponent("intervalo.txt"), atomically: true, encoding: .utf8)
    }
}
