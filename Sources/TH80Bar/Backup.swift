import AppKit
import UniformTypeIdentifiers

/// Exporta/importa tudo num arquivo só: perfis, automações, desenho e mapa de teclas.
struct BackupFile: Codable {
    var version = 1
    var created = Date()
    var presets: [LightPreset]
    var schedule: ScheduleSettings
    var meeting: MeetingSettings
    var lock: LockSettings
    var dailyCard: DailyCardSettings
    var pomodoro: PomodoroSettings
    var appRules: [AppRule]
    var drawing: [Data]          // PNGs dos quadros do editor
    var drawingDelayMs: Int
    var keymap: [[Int]]?         // camadas atuais
    var keymapOriginal: [[Int]]?
}

@MainActor
enum BackupService {
    static func png(_ img: CGImage) -> Data {
        NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) ?? Data()
    }

    static func export(keyboard k: KeyboardModel, editor: EditorModel, keymap: KeymapModel) {
        let file = BackupFile(presets: k.presets, schedule: k.schedule, meeting: k.meeting, lock: k.lock,
                              dailyCard: k.dailyCard, pomodoro: k.pomodoro, appRules: k.appRules,
                              drawing: editor.frames.map { png($0.image) }, drawingDelayMs: Int(editor.delayMs),
                              keymap: keymap.layers.isEmpty ? nil : keymap.layers,
                              keymapOriginal: keymap.original.isEmpty ? nil : keymap.original)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TH80-backup-\(DailyCardService.todayKey()).json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        try? enc.encode(file).write(to: url)
    }

    /// Lê um backup; o mapa de teclas só é gravado no teclado se `applyKeymap` for verdadeiro.
    static func pick() -> BackupFile? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BackupFile.self, from: data)
    }

    static func apply(_ f: BackupFile, keyboard k: KeyboardModel, editor: EditorModel, keymap: KeymapModel, applyKeymap: Bool) {
        k.presets = f.presets
        k.schedule = f.schedule
        k.meeting = f.meeting
        k.lock = f.lock
        k.dailyCard = f.dailyCard
        k.pomodoro = f.pomodoro
        k.appRules = f.appRules
        let frames = f.drawing.compactMap { NSImage(data: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
        if !frames.isEmpty { editor.load(frames: frames, delayMs: f.drawingDelayMs); editor.playing = false }
        if applyKeymap, let layers = f.keymap { keymap.applyLayers(layers) }
    }
}
