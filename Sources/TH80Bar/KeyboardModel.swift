import AppKit
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

    // Edição de iluminação (aplicada no teclado ao soltar o controle)
    var effect = 0
    var brightness = 9
    var speed = 2
    var rainbow = false
    var rgb = RGBColor(r: 0, g: 102, b: 255)
    /// Primeiro quadro do último envio, para a prévia da tela.
    var lastUpload: CGImage? = LastUploadStore.load()

    var syncClockOnConnect: Bool {
        didSet { UserDefaults.standard.set(syncClockOnConnect, forKey: "syncClockOnConnect") }
    }
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private let hid = HIDDevice()
    private var client: TH80Client { TH80Client(hid: hid) }
    private let queue = DispatchQueue(label: "th80.io")
    /// Mudança de luz feita enquanto outra gravação estava em andamento.
    private var lightingQueued = false

    init() {
        syncClockOnConnect = UserDefaults.standard.object(forKey: "syncClockOnConnect") as? Bool ?? true
        hid.onConnectionChange = { [weak self] up in
            guard let self else { return }
            self.connected = up
            if up {
                self.refresh(thenSyncClock: self.syncClockOnConnect)
            } else {
                self.config = nil
                self.uploadProgress = nil
            }
        }
        hid.start()
    }

    /// Roda trabalho de I/O fora da main thread e publica o resultado.
    private func run(_ label: String?, _ work: @escaping (TH80Client) throws -> TH80Config?) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        if let label { status = label }
        let client = self.client
        queue.async {
            let result = Result { try work(client) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let cfg):
                    if let cfg { self.apply(cfg, keepLighting: self.lightingQueued) }
                    self.status = nil
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                    self.status = nil
                }
                if self.lightingQueued {
                    self.lightingQueued = false
                    self.applyLighting()
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
        run("Lendo teclado…") { c in
            var cfg = try c.readConfig()
            if thenSyncClock {
                cfg.setClock(Date())
                try c.writeConfig(cfg)
            }
            return cfg
        }
    }

    /// Lê o estado atual, aplica a mudança e grava — nunca sobrescreve campos que não mudaram.
    private func modify(_ label: String, _ change: @escaping (inout TH80Config) -> Void) {
        run(label) { c in
            var cfg = try c.readConfig()
            change(&cfg)
            try c.writeConfig(cfg)
            return try c.readConfig()
        }
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
        let frames = media.encodedFrames
        uploadProgress = 0
        run("Enviando para a tela… mantenha o cabo conectado") { [weak self] c in
            let base = try c.readConfig()
            try c.uploadFrames(frames, delayMs: media.delayMs, base: base) { p in
                DispatchQueue.main.async { self?.uploadProgress = p }
            }
            return try c.readConfig()
        }
        // limpa a prévia quando terminar
        Task { @MainActor in
            while busy { try? await Task.sleep(for: .milliseconds(200)) }
            uploadProgress = nil
            if errorMessage == nil {
                if let first = media.frames.first {
                    lastUpload = first
                    LastUploadStore.save(first)
                }
                cancelMedia()
            }
        }
    }

    // MARK: Iluminação

    func applyLighting() {
        let (e, b, s, rb) = (effect, brightness, speed, rainbow)
        let (r, g, bl) = (rgb.r, rgb.g, rgb.b)
        // Evita regravar quando a UI só refletiu o que acabou de ser lido do teclado.
        if let cfg = config, cfg.effect == e, cfg.brightness == b, cfg.speed == s,
           (cfg.colorMode == 255) == rb, rb || (cfg.red == r && cfg.green == g && cfg.blue == bl) {
            return
        }
        if busy {
            lightingQueued = true
            return
        }
        modify("Aplicando iluminação…") { cfg in
            cfg.effect = e
            cfg.brightness = b
            cfg.speed = s
            if rb {
                cfg.colorMode = 255
            } else {
                cfg.colorMode = 0
                cfg.red = r
                cfg.green = g
                cfg.blue = bl
            }
        }
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
