import AppKit
import SwiftUI

// MARK: - Canvas (AppKit, para desenho fluido com o mouse)

final class CanvasNSView: NSView {
    var editor: EditorModel!
    private var last: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var scale: CGFloat { bounds.width / CGFloat(PixelFrame.w) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let editor else { return }
        ctx.interpolationQuality = .none
        // A imagem do CGContext tem origem embaixo; a view é invertida.
        func drawImage(_ img: CGImage, alpha: CGFloat) {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }
        drawImage(editor.frame.image, alpha: 1)
        if editor.onionSkin && !editor.playing && editor.current > 0 {
            drawImage(editor.frames[editor.current - 1].image, alpha: 0.28)
        }
        // Pré-visualização do tamanho do pincel
        if let p = hover, [.brush, .eraser].contains(editor.tool) {
            let r = editor.brushSize * scale / 2
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: p.x * scale - r, y: p.y * scale - r, width: r * 2, height: r * 2))
        }
    }

    private var hover: CGPoint?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch editor?.tool {
        case .text: .iBeam
        case .picker, .fill: .pointingHand
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / scale, y: p.y / scale)
    }

    override func mouseMoved(with event: NSEvent) { hover = point(event); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        MainActor.assumeIsolated {
            switch editor.tool {
            case .brush, .eraser:
                editor.beginStroke()
                editor.strokeSegment(from: p, to: p)
                last = p
            case .fill: editor.fill(at: p)
            case .picker: editor.pickColor(at: p)
            case .text: editor.placeText(at: p)
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        hover = p
        if let a = last {
            MainActor.assumeIsolated { editor.strokeSegment(from: a, to: p) }
            last = p
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if last != nil { MainActor.assumeIsolated { editor.endStroke() } }
        last = nil
    }
}

struct CanvasView: NSViewRepresentable {
    let editor: EditorModel
    let revision: Int
    let current: Int
    let tool: EditorTool

    func makeNSView(context: Context) -> CanvasNSView {
        let v = CanvasNSView()
        v.editor = editor
        return v
    }

    func updateNSView(_ v: CanvasNSView, context: Context) {
        v.needsDisplay = true
        v.window?.invalidateCursorRects(for: v)
    }
}

// MARK: - Janela do editor

struct EditorView: View {
    @Bindable var editor: EditorModel
    @Bindable var keyboard: KeyboardModel
    @State private var showSendConfirm = false
    @State private var showGallery = false
    @State private var showTextAnim = false

    var body: some View {
        HStack(spacing: 0) {
            toolbar
            Divider()
            VStack(spacing: 14) {
                topBar
                canvas
                frameStrip
            }
            .padding(18)
            Divider()
            sidePanel
        }
        .frame(minWidth: 1080, minHeight: 640)
        .background(.background)
        .task(id: editor.playing) { await playLoop() }
        .sheet(isPresented: $showGallery) { GallerySheet { editor.load(frames: $0, delayMs: $1) } }
        .sheet(isPresented: $showTextAnim) { TextAnimationSheet { editor.load(frames: $0, delayMs: $1) } }
    }

    // Ferramentas
    private var toolbar: some View {
        VStack(spacing: 6) {
            ForEach(EditorTool.allCases, id: \.self) { t in
                Button { editor.tool = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                        .background(editor.tool == t ? Color.accentColor.opacity(0.2) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(editor.tool == t ? Color.accentColor : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            Divider().padding(.vertical, 6)
            Button { editor.undo() } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 15)).frame(width: 40, height: 36)
            }
            .buttonStyle(.plain).help("Desfazer (⌘Z)").keyboardShortcut("z")
            Button { editor.clearFrame() } label: {
                Image(systemName: "trash").font(.system(size: 15)).frame(width: 40, height: 36)
            }
            .buttonStyle(.plain).help("Limpar quadro")
            Spacer()
        }
        .padding(10)
        .frame(width: 62)
    }

    private var topBar: some View {
        HStack {
            Text("Quadro \(editor.current + 1) de \(editor.frames.count)").font(.headline)
            Spacer()
            Toggle("Papel vegetal", isOn: $editor.onionSkin).toggleStyle(.checkbox)
                .help("Mostra o quadro anterior bem fraquinho por baixo")
            Button { editor.playing.toggle() } label: {
                Label(editor.playing ? "Parar" : "Tocar", systemImage: editor.playing ? "stop.fill" : "play.fill")
            }
            .disabled(editor.frames.count < 2)
        }
    }

    private var canvas: some View {
        CanvasView(editor: editor, revision: editor.revision, current: editor.current, tool: editor.tool)
            .aspectRatio(CGFloat(PixelFrame.w) / CGFloat(PixelFrame.h), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var frameStrip: some View {
        HStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(editor.frames.enumerated()), id: \.offset) { i, f in
                            Button { editor.playing = false; editor.current = i } label: {
                                VStack(spacing: 3) {
                                    Image(decorative: f.image, scale: 1).resizable().interpolation(.none)
                                        .frame(width: 96, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(i == editor.current ? Color.accentColor : .clear, lineWidth: 2.5))
                                    Text("\(i + 1)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain).id(i)
                        }
                    }
                    .padding(.vertical, 2)
                    .id(editor.revision) // atualiza miniaturas
                }
                .onChange(of: editor.current) { _, i in withAnimation { proxy.scrollTo(i) } }
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Button { editor.addFrame(duplicate: false) } label: { Image(systemName: "plus") }
                        .help("Novo quadro em branco")
                    Button { editor.addFrame(duplicate: true) } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicar quadro")
                }
                .disabled(!editor.canAddFrame)
                HStack(spacing: 4) {
                    Button { editor.moveFrame(by: -1) } label: { Image(systemName: "arrow.left") }.help("Mover para trás")
                    Button { editor.moveFrame(by: 1) } label: { Image(systemName: "arrow.right") }.help("Mover para frente")
                    Button { editor.deleteFrame() } label: { Image(systemName: "minus") }.help("Apagar quadro")
                }
                Text("\(editor.frames.count)/\(TH80Protocol.maxFrames)").font(.caption2).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .frame(height: 78)
    }

    // Painel lateral
    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Cor") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6), spacing: 8) {
                        ForEach(EditorView.palette, id: \.self) { c in
                            Button { editor.color = c; if editor.tool == .eraser || editor.tool == .picker { editor.tool = .brush } } label: {
                                Circle().fill(c.color).frame(width: 24, height: 24)
                                    .overlay(Circle().strokeBorder(.black.opacity(0.2)))
                                    .overlay(Circle().strokeBorder(editor.color == c ? Color.accentColor : .clear, lineWidth: 2.5).padding(-3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ColorPicker("Outra cor", selection: Binding(
                        get: { editor.color.color },
                        set: { editor.color = RGBColor(nsColor: NSColor($0)) }), supportsOpacity: false)
                    ColorPicker("Fundo / borracha", selection: Binding(
                        get: { editor.background.color },
                        set: { editor.background = RGBColor(nsColor: NSColor($0)) }), supportsOpacity: false)
                }

                if editor.tool == .text {
                    section("Texto") {
                        TextField("Digite o texto", text: $editor.text).textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Tamanho")
                            Slider(value: $editor.fontSize, in: 10...90)
                            Text("\(Int(editor.fontSize))").monospacedDigit().frame(width: 24)
                        }
                        Toggle("Negrito", isOn: $editor.bold)
                        Text("Clique no desenho para colocar o texto.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    section("Pincel") {
                        HStack {
                            Circle().fill(.primary).frame(width: max(3, editor.brushSize), height: max(3, editor.brushSize))
                                .frame(width: 30)
                            Slider(value: $editor.brushSize, in: 1...30)
                            Text("\(Int(editor.brushSize))").monospacedDigit().frame(width: 22)
                        }
                    }
                }

                section("Animação") {
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { 1060 - editor.delayMs }, set: { editor.delayMs = 1060 - $0 }),
                               in: 60...1000) { editing in if !editing { editor.delayChanged() } }
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                    Text("\(Int(editor.delayMs)) ms por quadro").font(.caption).foregroundStyle(.secondary)
                }

                section("Modelos") {
                    Button { showGallery = true } label: { Label("Galeria de animações…", systemImage: "sparkles.rectangle.stack") }
                    Button { showTextAnim = true } label: { Label("Texto animado…", systemImage: "character.cursor.ibeam") }
                }
                .buttonStyle(.link)

                section("Arquivo") {
                    Button { editor.importMedia() } label: { Label("Importar imagem ou GIF…", systemImage: "square.and.arrow.down") }
                    Button { editor.exportGIF() } label: { Label("Exportar como GIF…", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { editor.newProject() } label: { Label("Começar do zero", systemImage: "doc") }
                }
                .buttonStyle(.link)

                Spacer(minLength: 0)
                sendBox
            }
            .padding(18)
        }
        .frame(width: 270)
        .background(.quaternary.opacity(0.3))
    }

    private var sendBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = keyboard.uploadProgress {
                ProgressView(value: p)
                Text("Enviando \(Int(p * 100))% · não desconecte o cabo").font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    showSendConfirm = true
                } label: {
                    Label("Enviar para o teclado", systemImage: "keyboard.badge.ellipsis").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!keyboard.connected || keyboard.busy)
                if !keyboard.connected {
                    Text("Conecte o teclado pelo cabo USB.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let e = keyboard.errorMessage {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
        .confirmationDialog("Enviar \(editor.frames.count) quadro(s) para a tela?", isPresented: $showSendConfirm) {
            Button("Enviar") {
                editor.playing = false
                keyboard.upload(frames: editor.frames.map(\.image), delayMs: Int(editor.delayMs),
                                label: "Enviando desenho… mantenha o cabo conectado")
            }
        } message: {
            Text("Substitui a imagem atual da tela. Leva de 20 a 60 segundos.")
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.5)
            content()
        }
    }

    private func playLoop() async {
        guard editor.playing else { return }
        while editor.playing && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(editor.delayMs)))
            guard editor.playing else { break }
            editor.current = (editor.current + 1) % editor.frames.count
        }
    }

    static let palette: [RGBColor] = [
        .init(r: 255, g: 255, b: 255), .init(r: 160, g: 160, b: 160), .init(r: 60, g: 60, b: 60),
        .init(r: 0, g: 0, b: 0), .init(r: 255, g: 59, b: 48), .init(r: 255, g: 149, b: 0),
        .init(r: 255, g: 204, b: 0), .init(r: 52, g: 199, b: 89), .init(r: 0, g: 199, b: 190),
        .init(r: 0, g: 122, b: 255), .init(r: 88, g: 86, b: 214), .init(r: 255, g: 45, b: 85),
        .init(r: 175, g: 82, b: 222), .init(r: 162, g: 132, b: 94), .init(r: 255, g: 182, b: 193),
        .init(r: 144, g: 238, b: 144), .init(r: 135, g: 206, b: 250), .init(r: 255, g: 240, b: 150),
    ]
}
