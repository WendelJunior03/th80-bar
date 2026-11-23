import SwiftUI

/// Nomes vindos do GMK87 (mesma família de protocolo); no TH80 podem variar.
private let effectNames = [
    "Desligado", "Onda horizontal suave", "Pulso horizontal", "Cascata", "Ciclo de cores",
    "Respiração", "Cor fixa", "Brilho na tecla pressionada", "Brilho espalhando", "Brilho na linha",
    "Padrão aleatório", "Arco-íris em ciclo", "Cascata arco-íris", "Onda do centro", "Círculos",
    "Chuva", "Onda esquerda-direita", "Ciclo de saturação", "Arco-íris do centro",
]

struct MenuView: View {
    @Bindable var model: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.connected, let cfg = model.config {
                Divider()
                screenSection(cfg)
                Divider()
                lightingSection
            } else if model.connected {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else {
                Text("Conecte o TH80 Pro V2 pelo cabo USB. Bluetooth não expõe o canal da tela.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            feedback
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("EPOMAKER TH80 Pro V2").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(model.connected ? .green : .secondary).frame(width: 7, height: 7)
                    Text(model.connected ? "Conectado via USB" : "Desconectado")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.connected {
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Ler o estado do teclado")
                    .disabled(model.busy)
            }
        }
    }

    // MARK: Tela

    @ViewBuilder
    private func screenSection(_ cfg: TH80Config) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tela", systemImage: "rectangle.inset.filled").font(.subheadline.bold())

            Picker("", selection: Binding(
                get: { cfg.screenMode == 0 ? 0 : 1 },
                set: { model.setScreenMode($0) })) {
                Text("Relógio").tag(0)
                Text("Imagem / GIF").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().disabled(model.busy)

            HStack {
                Button("Acertar relógio agora", systemImage: "clock.arrow.circlepath") { model.syncClock() }
                Spacer()
                Text(cfg.frameCount > 1 ? "\(cfg.frameCount) quadros salvos" : "1 imagem salva")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(model.busy)

            if let media = model.pendingMedia {
                mediaPreview(media, cfg)
            } else {
                Button("Enviar imagem ou GIF…", systemImage: "photo.badge.plus") { model.chooseMedia() }
                    .disabled(model.busy)
            }
        }
    }

    @ViewBuilder
    private func mediaPreview(_ media: PreparedMedia, _ cfg: TH80Config) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AnimatedPreview(frames: media.frames, delayMs: media.delayMs)
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity)

            Text(model.pendingMediaName ?? "")
                .font(.caption).lineLimit(1).truncationMode(.middle)
            if media.originalFrameCount > media.frames.count {
                Text("GIF de \(media.originalFrameCount) quadros reduzido para \(media.frames.count) (limite seguro), \(media.delayMs) ms cada.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if cfg.frameCount > TH80Protocol.maxFrames {
                Label("Isso apaga a animação de fábrica (\(cfg.frameCount) quadros) e não dá para restaurá-la por aqui.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let p = model.uploadProgress {
                ProgressView(value: p) { Text("Enviando… \(Int(p * 100))%").font(.caption) }
            } else {
                HStack {
                    Button("Cancelar") { model.cancelMedia() }
                    Spacer()
                    Button("Enviar para o teclado") { model.uploadPendingMedia() }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(model.busy)
            }
        }
    }

    // MARK: Iluminação

    private var lightingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Iluminação", systemImage: "light.max").font(.subheadline.bold())

            Picker("Efeito", selection: $model.effect) {
                ForEach(effectNames.indices, id: \.self) { i in
                    Text("\(i) · \(effectNames[i])").tag(i)
                }
                if !effectNames.indices.contains(model.effect) {
                    Text("\(model.effect) · Outro").tag(model.effect)
                }
            }
            .onChange(of: model.effect) { _, _ in if !model.busy { model.applyLighting() } }

            sliderRow("Brilho", value: $model.brightness, range: 0...9)
            sliderRow("Velocidade", value: $model.speed, range: 0...4)

            HStack {
                Toggle("Arco-íris", isOn: $model.rainbow)
                    .onChange(of: model.rainbow) { _, _ in if !model.busy { model.applyLighting() } }
                Spacer()
                ColorPicker("Cor", selection: $model.color, supportsOpacity: false)
                    .disabled(model.rainbow)
                Button("Aplicar cor") { model.applyLighting() }
                    .disabled(model.rainbow || model.busy)
            }
        }
        .disabled(model.busy)
    }

    private func sliderRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                if !editing { model.applyLighting() }
            }
            Text("\(value.wrappedValue)").monospacedDigit().frame(width: 18)
        }
    }

    // MARK: Rodapé

    @ViewBuilder
    private var feedback: some View {
        if let s = model.status {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let e = model.errorMessage {
            Label(e, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Acertar relógio ao conectar", isOn: $model.syncClockOnConnect)
            Toggle("Abrir ao iniciar o Mac", isOn: Binding(
                get: { model.launchAtLogin }, set: { model.toggleLaunchAtLogin($0) }))
            HStack {
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .toggleStyle(.checkbox).font(.callout)
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
