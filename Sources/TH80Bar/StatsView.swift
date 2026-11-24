import Charts
import SwiftUI

struct StatsTab: View {
    @Bindable var stats: TypingStats
    @Bindable var model: KeyboardModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            if !stats.enabled || !stats.hasPermission {
                setup
            } else {
                summary
                chart
                top
                HStack {
                    Button {
                        UserDefaults.standard.set(true, forKey: "keymapHeatmap")
                        openWindow(id: "keymap")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: { Label("Mapa de calor", systemImage: "flame") }
                    Spacer()
                    Button {
                        let top = stats.topKeys.first.map { KeyCatalog.longLabel($0.code) }
                        model.upload(frames: [ScreenArt.statsCard(today: stats.today, week: stats.week.map(\.count), topKey: top)],
                                     delayMs: 1000, label: "Enviando estatísticas…")
                    } label: { Label("Mandar p/ tela", systemImage: "rectangle.inset.filled") }
                    .disabled(model.busy || !model.connected)
                }
                .controlSize(.small)
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Estatísticas de digitação", systemImage: "chart.bar.xaxis").font(.headline)
            Text("Conta quantas vezes cada tecla é apertada, para mostrar quanto você digita e um mapa de calor do teclado. O texto digitado nunca é lido nem guardado.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !stats.hasPermission {
                Text("O macOS pede a permissão “Monitoramento de Entrada”. Marque o TH80 Bar na lista que vai abrir.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Permitir e ativar") {
                    stats.enabled = true
                    stats.requestPermission()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Ativar") { stats.enabled = true }.buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("HOJE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(stats.today.formatted()).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text("teclas").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("7 dias").font(.caption).foregroundStyle(.secondary)
                Text(stats.week.map(\.count).reduce(0, +).formatted()).font(.system(.title3, design: .rounded).bold())
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var chart: some View {
        Chart(Array(stats.week.enumerated()), id: \.offset) { i, day in
            BarMark(x: .value("Dia", "\(i)·\(day.label)"), y: .value("Teclas", day.count))
                .foregroundStyle(i == 6 ? Color.accentColor : Color.accentColor.opacity(0.45))
                .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel { if let s = v.as(String.self) { Text(s.split(separator: "·").last.map(String.init) ?? "") } }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 90)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MAIS USADAS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(stats.topKeys, id: \.code) { k in
                HStack {
                    Text(KeyCatalog.longLabel(k.code)).font(.callout)
                    Spacer()
                    Text(k.count.formatted()).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if stats.topKeys.isEmpty { Text("Comece a digitar…").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}
