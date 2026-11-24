import SwiftUI

extension EditorModel {
    /// Substitui o desenho por quadros prontos (galeria, texto animado).
    func load(frames images: [CGImage], delayMs: Int) {
        frames = images.prefix(TH80Protocol.maxFrames).map { PixelFrame(image: $0) }
        current = 0
        self.delayMs = Double(min(1000, max(60, delayMs)))
        playing = frames.count > 1
        touch()
    }
}

// MARK: - Galeria

struct GallerySheet: View {
    let onPick: ([CGImage], Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: [String: [CGImage]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Galeria de animações").font(.title2.bold())
            Text("Escolha uma para abrir no editor. Dá para desenhar por cima antes de enviar.").foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(240), spacing: 16), count: 3), spacing: 16) {
                ForEach(ScreenArt.gallery) { a in
                    Button {
                        if let f = rendered[a.id] { onPick(f, a.delayMs); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Group {
                                if let f = rendered[a.id] {
                                    AnimatedPreview(frames: f, delayMs: a.delayMs)
                                } else {
                                    ZStack { Color.black; ProgressView().controlSize(.small) }
                                }
                            }
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(a.name).font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack { Spacer(); Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .task {
            for a in ScreenArt.gallery where rendered[a.id] == nil {
                let frames = await Task.detached { a.make() }.value
                rendered[a.id] = frames
            }
        }
    }
}

// MARK: - Texto animado

struct TextAnimationSheet: View {
    let onUse: ([CGImage], Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = "Olá, mundo!"
    @State private var style: ScreenArt.TextStyle = .typewriter
    @State private var fg = RGBColor(r: 255, g: 255, b: 255)
    @State private var bg = RGBColor(r: 0, g: 0, b: 0)

    private var result: (frames: [CGImage], delayMs: Int) {
        ScreenArt.animatedText(text, style: style, color: fg, background: bg)
    }

    var body: some View {
        let r = result
        VStack(alignment: .leading, spacing: 16) {
            Text("Texto animado").font(.title2.bold())
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Seu texto", text: $text).textFieldStyle(.roundedBorder).frame(width: 280)
                    Picker("Estilo", selection: $style) {
                        ForEach(ScreenArt.TextStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 280)
                    ColorPicker("Cor do texto", selection: Binding(get: { fg.color }, set: { fg = RGBColor(nsColor: NSColor($0)) }),
                                supportsOpacity: false)
                    ColorPicker("Fundo", selection: Binding(get: { bg.color }, set: { bg = RGBColor(nsColor: NSColor($0)) }),
                                supportsOpacity: false)
                    Text("\(r.frames.count) quadros · \(r.delayMs) ms").font(.caption).foregroundStyle(.secondary)
                }
                AnimatedPreview(frames: r.frames, delayMs: r.delayMs)
                    .frame(width: 360, height: 202)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .id("\(text)\(style)\(fg.hex)\(bg.hex)")
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Abrir no editor") { onUse(r.frames, r.delayMs); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}
