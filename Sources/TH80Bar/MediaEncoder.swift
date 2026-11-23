import AppKit
import ImageIO

/// Converte imagens/GIFs para o formato da tela: 240×135, RGB565 big endian,
/// cada quadro preenchido até 64 KiB.
struct PreparedMedia {
    var frames: [CGImage]      // já em 240×135, para prévia
    var delayMs: Int
    var originalFrameCount: Int

    var encodedFrames: [Data] { frames.map(MediaEncoder.encode) }
}

enum MediaEncoder {
    static let w = TH80Protocol.screenWidth
    static let h = TH80Protocol.screenHeight

    enum MediaError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Não foi possível ler esse arquivo de imagem." }
    }

    static func load(url: URL) throws -> PreparedMedia {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw MediaError.unreadable }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { throw MediaError.unreadable }

        if count == 1 {
            guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw MediaError.unreadable }
            return PreparedMedia(frames: [fit(img, orientation: orientation(src, 0))], delayMs: 100, originalFrameCount: 1)
        }

        // Amostra a linha do tempo do GIF em no máximo 18 quadros de duração uniforme.
        var ends: [Double] = []
        var total = 0.0
        for i in 0..<count {
            total += max(10, frameDelay(src, i))
            ends.append(total)
        }
        let outCount = min(count, TH80Protocol.maxFrames)
        let delay = min(65_535, max(60, Int((total / Double(outCount)).rounded())))
        var frames: [CGImage] = []
        var cache: [Int: CGImage] = [:]
        for k in 0..<outCount {
            let t = Double(k) * total / Double(outCount)
            let idx = min(count - 1, ends.firstIndex(where: { $0 > t }) ?? count - 1)
            if cache[idx] == nil, let img = CGImageSourceCreateImageAtIndex(src, idx, nil) {
                cache[idx] = fit(img, orientation: 1)
            }
            if let f = cache[idx] { frames.append(f) }
        }
        guard !frames.isEmpty else { throw MediaError.unreadable }
        return PreparedMedia(frames: frames, delayMs: delay, originalFrameCount: count)
    }

    private static func orientation(_ src: CGImageSource, _ i: Int) -> Int {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        return props?[kCGImagePropertyOrientation] as? Int ?? 1
    }

    private static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return (d > 0 ? d : 0.1) * 1000
    }

    /// Recorte central (aspect fill) sobre fundo preto.
    static func fit(_ image: CGImage, orientation: Int) -> CGImage {
        let ns = NSImage(cgImage: image, size: .zero)
        var srcW = CGFloat(image.width), srcH = CGFloat(image.height)
        let rotated = (5...8).contains(orientation)
        if rotated { swap(&srcW, &srcH) }

        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(.black)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        let scale = max(CGFloat(w) / srcW, CGFloat(h) / srcH)
        let dw = srcW * scale, dh = srcH * scale
        let rect = CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh)

        if orientation == 1 {
            ctx.draw(image, in: rect)
        } else {
            // Deixa o AppKit aplicar a orientação EXIF.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            ns.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
        return ctx.makeImage()!
    }

    static func encode(_ image: CGImage) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var out = Data(count: TH80Protocol.frameBytes)
        out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
            for i in 0..<(w * h) {
                let r = UInt16(px[i * 4]), g = UInt16(px[i * 4 + 1]), b = UInt16(px[i * 4 + 2])
                let v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                dst[i * 2] = UInt8(v >> 8)
                dst[i * 2 + 1] = UInt8(v & 0xFF)
            }
        }
        return out
    }
}
