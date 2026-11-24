import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class KeyboardModel {
    var connected = false
    var config: TH80Config?
    var status: String?
    var errorMessage: String?
    var busy = false
    var uploadProgress: Double?

    var pendingMedia: PreparedMedia?
    var pendingMediaName: String?

    // Edição de iluminação (o que a interface mostra)
    var effect = 0
    var brightness = 9
    var speed = 2
    var rainbow = false
    var rgb = RGBColor(r: 0, g: 102, b: 255)
    /// Primeiro quadro do último envio, para a prévia da tela.
    var lastUpload: CGImage? = LastUploadStore.load()

    // Perfis e automações
    var presets: [LightPreset] { didSet { Prefs.save("presets", presets) } }
    var schedule: ScheduleSettings { didSet { Prefs.save("schedule", schedule); if schedule != oldValue { scheduleChanged() } } }
    var meeting: MeetingSettings { didSet { Prefs.save("meeting", meeting); reevaluate() } }
    var lock: LockSettings { didSet { Prefs.save("lock", lock); reevaluate() } }
    var dailyCard: DailyCardSettings { didSet { Prefs.save("dailyCard", dailyCard) } }
    /// Slot 2 da tela contém a imagem de "ausente" (gravada no último envio).
    var awaySlotReady: Bool { didSet { UserDefaults.standard.set(awaySlotReady, forKey: "awaySlotReady") } }

    private(set) var inMeeting = false
    private(set) var screenLocked = false

    var syncClockOnConnect: Bool {
        didSet { UserDefaults.standard.set(syncClockOnConnect, forKey: "syncClockOnConnect") }
    }
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private let hid = HIDDevice.screen()
    private var client: TH80Client { TH80Client(hid: hid) }
    private let queue = DispatchQueue(label: "th80.io")

    /// Luz que o usuário (ou o horário) escolheu; as automações voltam para ela.
    private var baseline: LightPreset?
    /// Último visual aplicado pelo app, para não regravar à toa.
    private var lastApplied: LightPreset?
    /// Luz pedida enquanto outra gravação estava em andamento.
    private var queuedLight: LightPreset?
    private var timers: [Timer] = []
    private var hotKey: GlobalHotKey?

    init() {
        syncClockOnConnect = UserDefaults.standard.object(forKey: "syncClockOnConnect") as? Bool ?? false
        presets = Prefs.load("presets", LightPreset.defaults)
        schedule = Prefs.load("schedule", ScheduleSettings())
        meeting = Prefs.load("meeting", MeetingSettings())
        lock = Prefs.load("lock", LockSettings())
        dailyCard = Prefs.load("dailyCard", DailyCardSettings())
        awaySlotReady = UserDefaults.standard.bool(forKey: "awaySlotReady")

        hid.onConnectionChange = { [weak self] up in
            guard let self else { return }
            self.connected = up
            if up {
                self.refresh(thenSyncClock: self.syncClockOnConnect)
            } else {
                self.config = nil
                self.uploadProgress = nil
                self.lastApplied = nil
            }
        }
        hid.start()
        startWatchers()
    }

    // MARK: Execução de I/O

    /// Roda trabalho de I/O fora da main thread e publica o resultado.
    private func run(_ label: String?, _ work: @escaping (TH80Client) throws -> TH80Config?,
                     done: ((Bool) -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        if let label { status = label }
        let client = self.client
        queue.async {
            let result = Result { try work(client) }
            DispatchQueue.main.async {
                self.busy = false
                self.status = nil
                switch result {
                case .success(let cfg):
                    if let cfg { self.apply(cfg, keepLighting: self.queuedLight != nil) }
                    done?(true)
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                    done?(false)
                }
                if let next = self.queuedLight {
                    self.queuedLight = nil
                    self.writeLight(next)
                }
            }
        }
    }

    private func apply(_ cfg: TH80Config, keepLighting: Bool = false) {
        config = cfg
        guard !keepLighting else { return }
        effect = cfg.effect
        brightness = cfg.brightness
        speed = cfg.speed
        rainbow = cfg.colorMode == 255
        rgb = RGBColor(r: cfg.red, g: cfg.green, b: cfg.blue)
    }

    func refresh(thenSyncClock: Bool = false) {
        run("Lendo teclado…", { c in
            var cfg = try c.readConfig()
            if thenSyncClock {
                cfg.setClock(Date())
                try c.writeConfig(cfg)
            }
            return cfg
        }, done: { [weak self] ok in
            guard let self, ok, let cfg = self.config else { return }
            let current = self.preset(from: cfg)
            self.lastApplied = current
            if self.baseline == nil { self.baseline = current }
            self.scheduleTick(force: true)
            self.reevaluate()
            self.checkDailyCard()
        })
    }

    /// Lê o estado atual, aplica a mudança e grava — nunca sobrescreve campos que não mudaram.
    private func modify(_ label: String, done: ((Bool) -> Void)? = nil, _ change: @escaping (inout TH80Config) -> Void) {
        run(label, { c in
            var cfg = try c.readConfig()
            change(&cfg)
            try c.writeConfig(cfg)
            return try c.readConfig()
        }, done: done)
    }

    // MARK: Tela

    func setScreenMode(_ mode: Int) {
        if mode == 0 { return syncClock() }
        modify("Mostrando imagem…") { $0.screenMode = mode }
    }

    /// Acerta a hora e mostra o relógio na tela (como no app oficial, as duas coisas vão juntas).
    func syncClock() {
        modify("Acertando relógio…") { cfg in
            cfg.screenMode = 0
            cfg.setClock(Date())
        }
    }

    func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .gif]
        panel.allowsMultipleSelection = false
        panel.message = "Escolha uma imagem ou GIF para a tela do teclado (240 × 135)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingMedia = try MediaEncoder.load(url: url)
            pendingMediaName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelMedia() {
        pendingMedia = nil
        pendingMediaName = nil
    }

    func uploadPendingMedia() {
        guard let media = pendingMedia else { return }
        upload(frames: media.frames, delayMs: media.delayMs, label: "Enviando para a tela… mantenha o cabo conectado") { [weak self] ok in
            if ok { self?.cancelMedia() }
        }
    }

    /// Envia uma animação para a posição 1; a posição 2 recebe a tela de "ausente" se ativada.
    func upload(frames: [CGImage], delayMs: Int, label: String, done: ((Bool) -> Void)? = nil) {
        guard !busy else { return }
        let main = frames.map(MediaEncoder.encode)
        let withAway = lock.enabled && lock.awayScreen
        let second = withAway ? [MediaEncoder.encode(ScreenArt.awayImage(text: lock.awayText))] : main
        uploadProgress = 0
        run(label, { [weak self] c in
            let base = try c.readConfig()
            try c.uploadSlots(main, second, delayMs: delayMs, base: base) { p in
                DispatchQueue.main.async { self?.uploadProgress = p }
            }
            return try c.readConfig()
        }, done: { [weak self] ok in
            guard let self else { return }
            self.uploadProgress = nil
            if ok {
                self.lastUpload = frames.first
                LastUploadStore.save(frames, delayMs: delayMs)
                self.awaySlotReady = withAway
            }
            done?(ok)
        })
    }

    /// Reenvia a última arte com a tela de "ausente" na posição 2.
    func prepareAwayScreen() {
        guard let saved = LastUploadStore.loadAll() else {
            errorMessage = "Envie uma imagem ou desenho primeiro; a tela de ausente vai junto."
            return
        }
        upload(frames: saved.frames, delayMs: saved.delayMs, label: "Preparando tela de ausente…")
    }

    // MARK: Iluminação

    func preset(from cfg: TH80Config, name: String = "Atual") -> LightPreset {
        LightPreset(name: name, effect: cfg.effect, brightness: cfg.brightness, speed: cfg.speed,
                    rainbow: cfg.colorMode == 255, r: cfg.red, g: cfg.green, b: cfg.blue)
    }

    /// Estado atual da interface como perfil.
    var uiPreset: LightPreset {
        LightPreset(name: "Atual", effect: effect, brightness: brightness, speed: speed, rainbow: rainbow,
                    r: rgb.r, g: rgb.g, b: rgb.b)
    }

    /// Chamado pela interface depois de mexer em cor/efeito/brilho/velocidade.
    func applyLighting() {
        let p = uiPreset
        baseline = p
        if let cfg = config, preset(from: cfg).sameLook(p) { lastApplied = p; return }
        writeLight(p)
    }

    func pickColor(_ c: RGBColor) {
        rgb = c
        rainbow = false
        applyLighting()
    }

    func pickEffect(_ e: Int) {
        effect = e
        applyLighting()
    }

    func applyPreset(_ p: LightPreset) {
        effect = p.effect; brightness = p.brightness; speed = p.speed; rainbow = p.rainbow; rgb = p.rgb
        applyLighting()
    }

    func cyclePreset() {
        guard !presets.isEmpty else { return }
        let i = presets.firstIndex { $0.sameLook(uiPreset) }.map { ($0 + 1) % presets.count } ?? 0
        applyPreset(presets[i])
    }

    func saveCurrentAsPreset(named name: String) {
        var p = uiPreset
        p.name = name.isEmpty ? "Perfil \(presets.count + 1)" : name
        presets.append(p)
    }

    func deletePreset(_ p: LightPreset) { presets.removeAll { $0.id == p.id } }

    /// Grava um visual no teclado (ou enfileira se já houver gravação em andamento).
    private func writeLight(_ p: LightPreset) {
        if busy { queuedLight = p; return }
        if let cfg = config, preset(from: cfg).sameLook(p) { lastApplied = p; return }
        lastApplied = p
        modify("Aplicando iluminação…") { cfg in
            cfg.effect = p.effect
            cfg.brightness = p.brightness
            cfg.speed = p.speed
            if p.rainbow {
                cfg.colorMode = 255
            } else {
                cfg.colorMode = 0
                cfg.red = p.r
                cfg.green = p.g
                cfg.blue = p.b
            }
        }
    }

    // MARK: Automações

    /// Decide a luz certa agora: bloqueio > reunião > escolha do usuário/horário.
    private func reevaluate() {
        guard connected, config != nil, var target = baseline else { return }
        if screenLocked && lock.enabled && lock.lightsOff {
            target.brightness = 0
        } else if inMeeting && meeting.enabled {
            target = LightPreset(name: "Reunião", effect: 6, brightness: 9, speed: 2, rainbow: false,
                                 r: meeting.r, g: meeting.g, b: meeting.b)
        }
        if let last = lastApplied, last.sameLook(target) { return }
        writeLight(target)
    }

    private func startWatchers() {
        // Câmera/microfone: consulta a cada 3 s (barato e sem permissões).
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollMeeting() }
        })
        // Horário e cartão do dia: a cada minuto.
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleTick(force: false)
                self?.checkDailyCard()
            }
        })
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockChanged(true) }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockChanged(false) }
        }
        // ⌃⌥P alterna entre os perfis de luz.
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { [weak self] in
            MainActor.assumeIsolated { self?.cyclePreset() }
        }
    }

    private func pollMeeting() {
        guard meeting.enabled else {
            if inMeeting { inMeeting = false; reevaluate() }
            return
        }
        let now = (meeting.useCamera && MediaUsage.cameraInUse()) || (meeting.useMicrophone && MediaUsage.microphoneInUse())
        if now != inMeeting {
            inMeeting = now
            reevaluate()
        }
    }

    private func lockChanged(_ locked: Bool) {
        screenLocked = locked
        guard lock.enabled else { return }
        reevaluate()
        guard lock.awayScreen && awaySlotReady && connected else { return }
        let mode = locked ? 2 : 1
        guard config?.screenMode != mode else { return }
        if busy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.screenLocked == locked else { return }
                self.lockChanged(locked)
            }
        } else {
            modify(locked ? "Tela de ausente…" : "Voltando…") { $0.screenMode = mode }
        }
    }

    private func scheduleChanged() {
        UserDefaults.standard.removeObject(forKey: "schedulePeriod")
        scheduleTick(force: true)
    }

    /// Aplica o perfil de dia/noite quando o período muda (ou ao ligar/conectar, se mudou desde a última vez).
    private func scheduleTick(force: Bool) {
        guard schedule.enabled, connected, config != nil else { return }
        let night = schedule.isNight()
        let period = night ? "noite" : "dia"
        let last = UserDefaults.standard.string(forKey: "schedulePeriod")
        guard last != period else { return }
        if last == nil && !force { UserDefaults.standard.set(period, forKey: "schedulePeriod"); return }
        UserDefaults.standard.set(period, forKey: "schedulePeriod")
        let id = night ? schedule.nightPreset : schedule.dayPreset
        guard let p = presets.first(where: { $0.id == id }) else { return }
        effect = p.effect; brightness = p.brightness; speed = p.speed; rainbow = p.rainbow; rgb = p.rgb
        baseline = p
        reevaluate()
    }

    // MARK: Cartão do dia

    var cardPreview: CGImage?

    private func checkDailyCard() {
        guard dailyCard.enabled, connected, !busy else { return }
        let today = DailyCardService.todayKey()
        guard dailyCard.lastSent != today, Calendar.current.component(.hour, from: Date()) >= dailyCard.hour else { return }
        sendDailyCard()
    }

    func previewDailyCard() {
        let s = dailyCard
        Task {
            let info = await DailyCardService.gather(s)
            cardPreview = ScreenArt.dailyCard(info)
        }
    }

    func sendDailyCard() {
        let s = dailyCard
        Task {
            let info = await DailyCardService.gather(s)
            let img = ScreenArt.dailyCard(info)
            cardPreview = img
            upload(frames: [img], delayMs: 1000, label: "Enviando cartão do dia…") { [weak self] ok in
                if ok { self?.dailyCard.lastSent = DailyCardService.todayKey() }
            }
        }
    }

    // MARK: App

    func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Não foi possível alterar o início automático: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
