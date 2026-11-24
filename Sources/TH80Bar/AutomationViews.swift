import SwiftUI

// MARK: - Perfis (aba Luz)

struct PresetsCard: View {
    @Bindable var model: KeyboardModel
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PERFIS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.5)
                Spacer()
                Text("⌃⌥P alterna").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.presets) { p in
                        let active = p.sameLook(model.uiPreset)
                        Button { model.applyPreset(p) } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(p.rainbow ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                                                    : AnyShapeStyle(p.rgb.color))
                                    .frame(width: 10, height: 10)
                                Text(p.name).font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(active ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? Color.accentColor : .clear))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Apagar perfil", role: .destructive) { model.deletePreset(p) }
                        }
                    }
                    Button { newName = ""; naming = true } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                            .padding(6).background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain).help("Salvar a luz atual como perfil")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .alert("Nome do perfil", isPresented: $naming) {
            TextField("Ex.: Leitura", text: $newName)
            Button("Salvar") { model.saveCurrentAsPreset(named: newName) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Guarda a cor, o efeito, o brilho e a velocidade atuais. Clique com o botão direito num perfil para apagar.")
        }
    }
}

// MARK: - Aba Automações

struct AutoTab: View {
    @Bindable var model: KeyboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                pomodoroCard
                appsCard
                scheduleCard
                meetingCard
                lockCard
                dailyCard
            }
        }
        .frame(maxHeight: 500)
    }

    private var pomodoroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pomodoro", systemImage: "timer").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let label = model.pomodoroLabel {
                    Text("\(model.pomodoroPhase == .focus ? "🍅" : "☕") \(label)")
                        .font(.system(.callout, design: .rounded).bold()).monospacedDigit()
                    Button("Parar") { model.stopPomodoro() }.controlSize(.small)
                } else {
                    Button("Começar") { model.startPomodoro() }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            }
            if model.pomodoroPhase == nil {
                HStack {
                    Stepper("Foco \(model.pomodoro.focusMinutes) min", value: $model.pomodoro.focusMinutes, in: 5...90, step: 5)
                    Stepper("Pausa \(model.pomodoro.breakMinutes)", value: $model.pomodoro.breakMinutes, in: 1...30)
                }
                .font(.callout)
                Toggle("Mudar a luz", isOn: $model.pomodoro.useLight).toggleStyle(.checkbox)
                if model.pomodoro.useLight {
                    presetPicker("Luz do foco", selection: $model.pomodoro.focusPreset)
                    presetPicker("Luz da pausa", selection: $model.pomodoro.breakPreset)
                }
                Toggle("Mostrar Foco/Pausa na tela", isOn: $model.pomodoro.useScreen).toggleStyle(.checkbox)
                Toggle("Tocar som ao trocar", isOn: $model.pomodoro.sound).toggleStyle(.checkbox)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if model.pomodoro.focusPreset == nil { model.pomodoro.focusPreset = model.presets.first { $0.name == "Foco" }?.id ?? model.presets.first?.id }
            if model.pomodoro.breakPreset == nil { model.pomodoro.breakPreset = model.presets.first { $0.name == "Trabalho" }?.id ?? model.presets.first?.id }
        }
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Luz por app", systemImage: "app.badge").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    NSApp.activate(ignoringOtherApps: true)
                    if panel.runModal() == .OK, let url = panel.url { model.addAppRule(url: url) }
                } label: { Image(systemName: "plus") }
                .controlSize(.small).help("Escolher um app")
            }
            if model.appRules.isEmpty {
                Text("Ex.: abrir um jogo deixa a luz no perfil Jogo; ao sair, ela volta.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach($model.appRules) { $rule in
                HStack {
                    Image(nsImage: NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
                        .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                        .resizable().frame(width: 18, height: 18)
                    Text(rule.name).lineLimit(1)
                    Spacer()
                    Picker("", selection: $rule.preset) {
                        ForEach(model.presets) { p in Text(p.name).tag(UUID?.some(p.id)) }
                    }
                    .labelsHidden().frame(width: 100)
                    Button { model.appRules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func card<C: View>(_ title: String, icon: String, isOn: Binding<Bool>, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if isOn.wrappedValue {
                content().font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func minutesBinding(_ kp: WritableKeyPath<ScheduleSettings, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(model.schedule[keyPath: kp]) * 60)
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            model.schedule[keyPath: kp] = c.hour! * 60 + c.minute!
        })
    }

    private func presetPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Nenhum").tag(UUID?.none)
            ForEach(model.presets) { p in Text(p.name).tag(UUID?.some(p.id)) }
        }
    }

    private var scheduleCard: some View {
        card("Luz pelo horário", icon: "moon.stars", isOn: $model.schedule.enabled) {
            HStack {
                DatePicker("Dia a partir de", selection: minutesBinding(\.dayStart), displayedComponents: .hourAndMinute)
            }
            presetPicker("Perfil do dia", selection: $model.schedule.dayPreset)
            DatePicker("Noite a partir de", selection: minutesBinding(\.nightStart), displayedComponents: .hourAndMinute)
            presetPicker("Perfil da noite", selection: $model.schedule.nightPreset)
            Text("Troca sozinho nos horários. Se você mudar a luz na mão, vale até a próxima troca.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if model.schedule.dayPreset == nil { model.schedule.dayPreset = model.presets.first?.id }
            if model.schedule.nightPreset == nil { model.schedule.nightPreset = model.presets.first { $0.name == "Noite" }?.id }
        }
    }

    private var meetingCard: some View {
        card("Luz de reunião", icon: "video", isOn: $model.meeting.enabled) {
            Toggle("Quando a câmera ligar", isOn: $model.meeting.useCamera)
            Toggle("Quando o microfone ligar", isOn: $model.meeting.useMicrophone)
            HStack {
                Text("Cor")
                Spacer()
                ForEach([RGBColor(r: 255, g: 0, b: 0), RGBColor(r: 255, g: 120, b: 0), RGBColor(r: 180, g: 0, b: 255), RGBColor(r: 0, g: 140, b: 255)], id: \.self) { c in
                    Button { model.meeting.r = c.r; model.meeting.g = c.g; model.meeting.b = c.b } label: {
                        Circle().fill(c.color).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(model.meeting.rgb == c ? Color.primary : .clear, lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(model.inMeeting ? "● Em reunião agora" : "Volta à luz normal quando terminar.")
                .font(.caption).foregroundStyle(model.inMeeting ? .red : .secondary)
        }
        .toggleStyle(.checkbox)
    }

    private var lockCard: some View {
        card("Mac bloqueado", icon: "lock", isOn: $model.lock.enabled) {
            Toggle("Apagar a luz", isOn: $model.lock.lightsOff)
            Toggle("Mostrar tela de ausente", isOn: $model.lock.awayScreen)
            if model.lock.awayScreen {
                HStack {
                    Image(decorative: ScreenArt.awayImage(text: model.lock.awayText), scale: 1)
                        .resizable().frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Texto", text: $model.lock.awayText).textFieldStyle(.roundedBorder)
                        if !model.awaySlotReady {
                            Button("Preparar tela de ausente") { model.prepareAwayScreen() }
                                .controlSize(.small).disabled(model.busy || !model.connected)
                        } else {
                            Text("Pronta ✓").font(.caption).foregroundStyle(.green)
                        }
                    }
                }
                Text("A tela de ausente vai junto com cada envio de imagem (fica guardada na 2ª posição). Mudou o texto? Clique em preparar de novo.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .onChange(of: model.lock.awayText) { _, _ in model.awaySlotReady = false }
    }

    private var dailyCard: some View {
        card("Cartão do dia", icon: "sun.horizon", isOn: $model.dailyCard.enabled) {
            Stepper("Enviar às \(model.dailyCard.hour)h", value: $model.dailyCard.hour, in: 0...23)
            Toggle("Clima", isOn: $model.dailyCard.showWeather)
            if model.dailyCard.showWeather {
                TextField("Cidade (ex.: São Paulo)", text: $model.dailyCard.city).textFieldStyle(.roundedBorder)
            }
            Toggle("Próximo compromisso (Calendário)", isOn: $model.dailyCard.showCalendar)
            Toggle("Contagem regressiva", isOn: $model.dailyCard.countdownEnabled)
            if model.dailyCard.countdownEnabled {
                TextField("Para quê? (ex.: Férias)", text: $model.dailyCard.countdownTitle).textFieldStyle(.roundedBorder)
                DatePicker("Data", selection: $model.dailyCard.countdownDate, displayedComponents: .date)
                Text(DailyCardService.countdownText(model.dailyCard)).font(.caption).foregroundStyle(.secondary)
            }
            if let img = model.cardPreview {
                Image(decorative: img, scale: 1).resizable().aspectRatio(240 / 135, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Button("Prévia") { model.previewDailyCard() }
                Button("Enviar agora") { model.sendDailyCard() }.disabled(model.busy || !model.connected)
            }
            .controlSize(.small)
            Text("Substitui a imagem da tela uma vez por dia. O clima vem do Open-Meteo (só o nome da cidade é enviado).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
    }
}
