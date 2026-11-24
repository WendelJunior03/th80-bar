import SwiftUI

struct KeymapView: View {
    @Bindable var model: KeymapModel
    var stats: TypingStats
    @AppStorage("keymapHeatmap") private var heatmap = false
    @State private var search = ""
    @State private var shortcutMods: Set<Int> = []
    @State private var shortcutBase = 0x06 // C
    @State private var confirmSpecial: (KeyCap, Int)?
    @State private var confirmRestoreAll = false

    private let unit: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.layers.isEmpty {
                    placeholder
                } else {
                    keyboard
                    legend
                }
                Spacer()
            }
            .padding(22)
            Divider()
            sidePanel.frame(width: 300)
        }
        .frame(minWidth: 1180, minHeight: 560)
        .alert("Alterar uma tecla especial?", isPresented: Binding(get: { confirmSpecial != nil }, set: { if !$0 { confirmSpecial = nil } })) {
            Button("Alterar mesmo assim", role: .destructive) {
                if let (k, c) = confirmSpecial { model.assign(c, to: k) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa tecla tem uma função própria do teclado (como Fn). Se trocá-la, você pode perder atalhos como os de luz e Bluetooth. Dá para voltar com “Restaurar original”.")
        }
        .alert("Voltar todas as teclas ao original?", isPresented: $confirmRestoreAll) {
            Button("Restaurar", role: .destructive) { model.restoreAll() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Teclas").font(.title2.bold())
                Text(model.connected ? "Clique numa tecla e escolha a nova função à direita." : "Conecte o teclado pelo cabo USB.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Toggle(isOn: $heatmap) { Label("Mapa de calor", systemImage: "flame") }
                .toggleStyle(.button).help("Cores pelas teclas que você mais usa (precisa das estatísticas ativadas)")
            Picker("Camada", selection: $model.layer) {
                Text("Normal").tag(0)
                Text("Com Fn").tag(1)
                Text("Camada 3").tag(2)
                Text("Camada 4").tag(3)
            }
            .pickerStyle(.segmented).frame(width: 360)
            .disabled(model.layers.isEmpty)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(model.status ?? (model.connected ? "Lendo teclas…" : "Teclado desconectado")).foregroundStyle(.secondary)
            if let e = model.errorMessage {
                Text(e).foregroundStyle(.red)
                Button("Tentar de novo") { model.reload() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var keyboard: some View {
        ZStack(alignment: .topLeading) {
            ForEach(TH80Layout.keys, id: \.self) { key in
                keyCap(key)
                    .frame(width: key.w * unit - 5, height: key.h * unit - 5)
                    .offset(x: key.x * unit, y: key.y * unit)
            }
        }
        .frame(width: TH80Layout.width * unit, height: TH80Layout.height * unit, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
    }

    private func keyCap(_ key: KeyCap) -> some View {
        let code = model.code(key) ?? 0
        let selected = model.selected == key
        let changed = model.isChanged(key)
        return Button { model.selected = key } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor.opacity(0.35) : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1.5)
                if heatmap, let heat = heat(code) {
                    RoundedRectangle(cornerRadius: 7).fill(heatColor(heat))
                }
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? Color.accentColor : changed ? Color.orange : Color.primary.opacity(0.08),
                                  lineWidth: selected || changed ? 2 : 1)
                Text(KeyCatalog.shortLabel(code))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(KeyCatalog.isKnown(code) ? Color.primary : .secondary)
                if changed {
                    Circle().fill(.orange).frame(width: 6, height: 6).padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .help(KeyCatalog.longLabel(code))
    }

    /// 0…1 pela quantidade de uso da tecla (escala raiz, para as menos usadas aparecerem).
    private func heat(_ code: Int) -> Double? {
        let maxC = stats.maxKeyCount
        guard maxC > 0, code & 0xFF00 == 0 else { return nil }
        let c = stats.count(forHID: code)
        return c == 0 ? nil : sqrt(Double(c) / Double(maxC))
    }

    private func heatColor(_ t: Double) -> Color {
        Color(hue: 0.62 - 0.62 * t, saturation: 0.85, brightness: 0.95).opacity(0.35 + 0.5 * t)
    }

    private var legend: some View {
        HStack(spacing: 18) {
            if heatmap {
                HStack(spacing: 4) {
                    Text("pouco").foregroundStyle(.secondary)
                    LinearGradient(colors: [heatColor(0.05), heatColor(0.5), heatColor(1)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 90, height: 8).clipShape(Capsule())
                    Text("muito").foregroundStyle(.secondary)
                }
            }
            Label("Alterada", systemImage: "circle.fill").foregroundStyle(.orange)
            Label("▽ Transparente = usa a função da camada Normal", systemImage: "info.circle").foregroundStyle(.secondary)
            Spacer()
            if model.changedCount > 0 {
                Text("\(model.changedCount) tecla(s) alterada(s)").foregroundStyle(.secondary)
                Button("Restaurar tudo ao original…") { confirmRestoreAll = true }
            }
        }
        .font(.callout)
    }

    // MARK: Painel lateral

    @ViewBuilder
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let key = model.selected, let code = model.code(key) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TECLA SELECIONADA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(KeyCatalog.longLabel(code)).font(.title3.bold())
                    if let o = model.originalCode(key), o != code {
                        HStack {
                            Text("Original: \(KeyCatalog.longLabel(o))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restaurar") { model.restoreKey(key) }.controlSize(.small)
                        }
                    }
                }
                Divider()
                shortcutBuilder(key)
                Divider()
                TextField("Buscar função…", text: $search).textFieldStyle(.roundedBorder)
                catalog(key)
            } else {
                Spacer()
                Text("Selecione uma tecla no desenho").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
            if let e = model.errorMessage, !model.layers.isEmpty {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(18)
        .disabled(model.busy)
    }

    private func shortcutBuilder(_ key: KeyCap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CRIAR ATALHO").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(KeyCatalog.modifierBits, id: \.bit) { m in
                    Toggle(isOn: Binding(get: { shortcutMods.contains(m.bit) },
                                         set: { if $0 { shortcutMods.insert(m.bit) } else { shortcutMods.remove(m.bit) } })) {
                        Text(m.symbol).font(.system(size: 15)).frame(width: 22)
                    }
                    .toggleStyle(.button).help(m.name)
                }
                Text("+")
                Picker("", selection: $shortcutBase) {
                    ForEach(KeyCatalog.all.filter { $0.code > 0x01 && $0.code < 0xE0 }) { f in Text(f.label).tag(f.code) }
                }
                .labelsHidden().frame(width: 90)
            }
            Button("Aplicar atalho") {
                let code = shortcutMods.reduce(0, |) | shortcutBase
                apply(code, to: key)
            }
            .disabled(shortcutMods.isEmpty)
            Text("Ex.: ⌘ + C vira uma tecla de copiar.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func catalog(_ key: KeyCap) -> some View {
        let filtered = KeyCatalog.all.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
        return List {
            ForEach(KeyCatalog.groups, id: \.self) { g in
                let items = filtered.filter { $0.group == g }
                if !items.isEmpty {
                    Section(g) {
                        ForEach(items) { f in
                            Button { apply(f.code, to: key) } label: {
                                HStack {
                                    Text(f.label)
                                    Spacer()
                                    if model.code(key) == f.code { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func apply(_ code: Int, to key: KeyCap) {
        if let current = model.code(key), !KeyCatalog.isKnown(current) {
            confirmSpecial = (key, code)
        } else {
            model.assign(code, to: key)
        }
    }
}
