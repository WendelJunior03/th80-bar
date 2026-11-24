import SwiftUI

private struct Effect {
    let name: String
    let icon: String
}

/// Nomes vindos do GMK87 (mesma família de protocolo); no TH80 podem variar.
private let effects: [Effect] = [
    .init(name: "Desligado", icon: "lightbulb.slash"),
    .init(name: "Onda suave", icon: "water.waves"),
    .init(name: "Pulso", icon: "waveform.path"),
    .init(name: "Cascata", icon: "arrow.down.to.line"),
    .init(name: "Ciclo", icon: "arrow.triangle.2.circlepath"),
    .init(name: "Respiração", icon: "wind"),
    .init(name: "Cor fixa", icon: "circle.fill"),
    .init(name: "Ao tocar", icon: "hand.tap"),
    .init(name: "Espalhar", icon: "dot.radiowaves.left.and.right"),
    .init(name: "Linha", icon: "line.3.horizontal"),
    .init(name: "Aleatório", icon: "sparkles"),
    .init(name: "Arco-íris", icon: "rainbow"),
    .init(name: "Cascata RGB", icon: "chevron.down.2"),
    .init(name: "Do centro", icon: "circle.circle"),
    .init(name: "Círculos", icon: "circle.dotted"),
    .init(name: "Chuva", icon: "cloud.rain"),
    .init(name: "Vai e vem", icon: "arrow.left.and.right"),
    .init(name: "Saturação", icon: "drop.halffull"),
    .init(name: "Centro RGB", icon: "sun.max"),
]

private enum Tab: String, CaseIterable {
    case screen = "Tela", light = "Luz", settings = "Ajustes"
    var icon: String {
        switch self {
        case .screen: "rectangle.inset.filled"
        case .light: "light.max"
        case .settings: "gearshape"
        }
    }
}

struct MenuView: View {
    @Bindable var model: KeyboardModel
    @AppStorage("tab") private var tab: Tab = .screen

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.connected, let cfg = model.config {
                tabBar.padding(.horizontal, 14).padding(.bottom, 10)
                Group {
                    switch tab {
                    case .screen: ScreenTab(model: model, cfg: cfg)
                    case .light: LightTab(model: model)
                    case .settings: SettingsTab(model: model)
                    }
                }
                .padding(.horizontal, 14)
            } else if model.connected {
                ProgressView().controlSize(.small).padding(30)
            } else {
                disconnected
            }
            feedback.padding(.horizontal, 14)
            Spacer(minLength: 12)
        }
        .frame(width: 330)
        .animation(.snappy(duration: 0.2), value: tab)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [model.rgb.color.opacity(0.9), model.rgb.color.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "keyboard.fill").foregroundStyle(.white).font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 34, height: 34)
            .shadow(color: model.rgb.color.opacity(0.4), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("TH80 Pro V2").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(model.connected ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    Text(model.connected ? "Conectado via USB" : "Desconectado")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
            } else if model.connected {
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Ler o estado do teclado")
            }
        }
        .padding(14)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Label(t.rawValue, systemImage: t.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(tab == t ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .shadow(color: .black.opacity(tab == t ? 0.12 : 0), radius: 2, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == t ? .primary : .secondary)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    }

    private var disconnected: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Conecte o teclado pelo cabo USB").font(.headline)
            Text("Pelo Bluetooth o teclado não libera o controle da tela e da luz.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Divider().padding(.vertical, 4)
            SettingsTab(model: model)
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var feedback: some View {
        if let s = model.status, model.uploadProgress == nil {
            Text(s).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
        }
        if let e = model.errorMessage {
            Label(e, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 10)
        }
    }
}

// MARK: - Cartão

private struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tela

private struct ScreenTab: View {
    @Bindable var model: KeyboardModel
    let cfg: TH80Config
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            if let media = model.pendingMedia {
                pending(media)
            } else {
                screenPreview
                modeTiles
                HStack(spacing: 8) {
                    Button { model.chooseMedia() } label: {
                        Label("Imagem ou GIF", systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Button {
                        openWindow(id: "editor")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Label("Desenhar", systemImage: "paintbrush.pointed").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    Button { model.syncClock() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .controlSize(.large).help("Acertar o relógio do teclado com o do Mac")
                }
                .disabled(model.busy)
            }
        }
    }

    /// Simulação da tela do teclado.
    private var screenPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black)
            if cfg.screenMode == 0 {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 2) {
                        Text(ctx.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                }
            } else if let img = model.lastUpload {
                Image(decorative: img, scale: 1).resizable().interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).padding(4)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 26))
                    Text(cfg.frameCount > 1 ? "Animação salva · \(cfg.frameCount) quadros" : "Imagem salva")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 302, height: 170)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
        .overlay(alignment: .bottomTrailing) {
            if cfg.screenMode != 0 && cfg.frameCount > 1 && model.lastUpload != nil {
                Text("\(cfg.frameCount) quadros").font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white)
                    .padding(8)
            }
        }
    }

    private var modeTiles: some View {
        HStack(spacing: 8) {
            tile("Relógio", icon: "clock", selected: cfg.screenMode == 0) { model.setScreenMode(0) }
            tile("Imagem / GIF", icon: "photo", selected: cfg.screenMode != 0) { model.setScreenMode(1) }
        }
        .disabled(model.busy)
    }

    private func tile(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.45)),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pending(_ media: PreparedMedia) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AnimatedPreview(frames: media.frames, delayMs: media.delayMs)
                .frame(width: 302, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(model.pendingMediaName ?? "").font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(media.frames.count > 1
                     ? "\(media.frames.count) quadros · \(media.delayMs) ms cada"
                        + (media.originalFrameCount > media.frames.count ? " (reduzido de \(media.originalFrameCount))" : "")
                     : "Imagem estática · 240 × 135")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Label("O envio apaga a memória de imagens do teclado, incluindo os números do relógio e a animação de fábrica. Eles não podem ser restaurados por aqui.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

            if let p = model.uploadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: p)
                    Text("Enviando \(Int(p * 100))% · não desconecte o cabo").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Button("Cancelar") { model.cancelMedia() }.controlSize(.large)
                    Button { model.uploadPendingMedia() } label: {
                        Label("Enviar para o teclado", systemImage: "arrow.up.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .disabled(model.busy)
            }
        }
    }
}

// MARK: - Luz

private struct LightTab: View {
    @Bindable var model: KeyboardModel
    @State private var hexText = ""
    @State private var dragHue: Double?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(spacing: 10) {
            Card(title: "Cor") { colorSection }
            Card(title: "Intensidade") {
                sliderRow(icon: "sun.max", value: $model.brightness, range: 0...9)
                sliderRow(icon: "speedometer", value: $model.speed, range: 0...4)
            }
            Card(title: "Efeito") { effectGrid }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(RGBColor.presets, id: \.self) { c in
                    let selected = !model.rainbow && model.rgb == c
                    Button { model.pickColor(c) } label: {
                        Circle().fill(c.color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }

            hueBar

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(model.rainbow ? AnyShapeStyle(rainbowGradient) : AnyShapeStyle(model.rgb.color))
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.15)))
                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                    .frame(width: 84)
                    .onSubmit {
                        if let c = RGBColor(hex: hexText) { model.pickColor(c) } else { hexText = model.rgb.hex }
                    }
                Spacer()
                Toggle(isOn: Binding(get: { model.rainbow }, set: { model.rainbow = $0; model.applyLighting() })) {
                    Text("Arco-íris").font(.caption)
                }
                .toggleStyle(.switch).controlSize(.mini)
            }
            .onAppear { hexText = model.rgb.hex }
            .onChange(of: model.rgb) { _, c in hexText = c.hex }

            if !colorEffects.contains(model.effect) && !model.rainbow {
                Text("O efeito atual pode ignorar a cor. Use “Cor fixa” ou “Respiração” para vê-la.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private let colorEffects: Set<Int> = [5, 6, 7, 8, 9, 13, 15, 16]

    private var rainbowGradient: LinearGradient {
        LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) },
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Faixa de matiz: arraste para escolher, solta para aplicar.
    private var hueBar: some View {
        GeometryReader { geo in
            let hue = dragHue ?? model.rgb.hue
            ZStack(alignment: .leading) {
                Capsule().fill(rainbowGradient)
                Circle().fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: hue * (geo.size.width - 18))
                    .opacity(model.rainbow ? 0 : 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in dragHue = min(1, max(0, (v.location.x - 9) / (geo.size.width - 18))) }
                .onEnded { _ in
                    if let h = dragHue { model.pickColor(RGBColor(hue: h)) }
                    dragHue = nil
                })
        }
        .frame(height: 18)
    }

    private func sliderRow(icon: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                if !editing { model.applyLighting() }
            }
            .controlSize(.small)
            Text("\(value.wrappedValue)").font(.system(.caption, design: .rounded)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 14)
        }
    }

    private var effectGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(effects.indices, id: \.self) { i in
                let selected = model.effect == i
                Button { model.pickEffect(i) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: effects[i].icon).font(.system(size: 14))
                        Text(effects[i].name).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.background.opacity(0.6)),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Ajustes

private struct SettingsTab: View {
    @Bindable var model: KeyboardModel

    var body: some View {
        VStack(spacing: 10) {
            Card {
                Toggle("Acertar relógio ao conectar", isOn: $model.syncClockOnConnect)
                Divider()
                Toggle("Abrir ao iniciar o Mac", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.toggleLaunchAtLogin($0) }))
            }
            .toggleStyle(.switch).controlSize(.small).font(.callout)

            HStack {
                Text("TH80 Bar 1.2 · protocolo de th80-studio (MIT)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }.keyboardShortcut("q").controlSize(.small)
            }
        }
    }
}

/// Prévia animada dos quadros que serão enviados.
struct AnimatedPreview: View {
    let frames: [CGImage]
    let delayMs: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: Double(max(delayMs, 60)) / 1000)) { ctx in
            let i = frames.count > 1
                ? Int(ctx.date.timeIntervalSinceReferenceDate * 1000 / Double(max(delayMs, 60))) % frames.count
                : 0
            Image(decorative: frames[i], scale: 1).resizable().interpolation(.high)
        }
    }
}
