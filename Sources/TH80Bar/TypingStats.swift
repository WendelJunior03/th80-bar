import AppKit
import Observation

/// Conta teclas pressionadas (só a quantidade por tecla, nunca o texto).
/// Precisa da permissão "Monitoramento de Entrada" do macOS.
@MainActor
@Observable
final class TypingStats {
    struct Store: Codable {
        var daily: [String: Int] = [:]   // "yyyy-MM-dd" → total
        var keys: [Int: Int] = [:]       // código HID → total acumulado
    }

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "statsEnabled")
            enabled ? start() : stop()
        }
    }
    private(set) var store: Store
    private(set) var hasPermission = CGPreflightListenEventAccess()
    private(set) var running = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var dirty = false
    private var timer: Timer?
    private var permissionTimer: Timer?

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TH80Bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("estatisticas.json")
    }

    init() {
        store = (try? JSONDecoder().decode(Store.self, from: Data(contentsOf: Self.url))) ?? Store()
        enabled = UserDefaults.standard.bool(forKey: "statsEnabled")
        if enabled { start() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    // MARK: Números

    var today: Int { store.daily[DailyCardService.todayKey()] ?? 0 }

    /// Últimos 7 dias, do mais antigo para hoje.
    var week: [(label: String, count: Int)] {
        let cal = Calendar.current
        let pt = Locale(identifier: "pt_BR")
        return (0..<7).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: Date())!
            return (d.formatted(.dateTime.weekday(.abbreviated).locale(pt)), store.daily[DailyCardService.todayKey(d)] ?? 0)
        }
    }

    var topKeys: [(code: Int, count: Int)] {
        store.keys.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    var maxKeyCount: Int { store.keys.values.max() ?? 0 }

    func count(forHID code: Int) -> Int { store.keys[code] ?? 0 }

    func reset() {
        store = Store()
        dirty = true
        save()
    }

    // MARK: Captura

    func requestPermission() {
        CGRequestListenEventAccess()
        // O macOS só libera depois que o usuário marca o app nos Ajustes; verificamos de tempos em tempos.
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                self.hasPermission = CGPreflightListenEventAccess()
                if self.hasPermission {
                    t.invalidate()
                    if self.enabled { self.start() }
                }
            }
        }
    }

    private func start() {
        hasPermission = CGPreflightListenEventAccess()
        guard hasPermission, tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            let stats = Unmanaged<TypingStats>.fromOpaque(ctx!).takeUnretainedValue()
            let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let flags = event.flags
            MainActor.assumeIsolated { stats.handle(type: type, keycode: keycode, isRepeat: isRepeat, flags: flags) }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
    }

    private func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
        running = false
        save()
    }

    private var lastFlags: CGEventFlags = []

    private func handle(type: CGEventType, keycode: Int, isRepeat: Bool, flags: CGEventFlags) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if type == .flagsChanged {
            // Conta só quando o modificador é pressionado (não quando é solto).
            let pressed = flags.rawValue & ~lastFlags.rawValue
            lastFlags = flags
            guard pressed != 0 else { return }
        } else if isRepeat {
            return
        }
        guard let hid = Self.hidUsage[keycode] else { return }
        store.keys[hid, default: 0] += 1
        store.daily[DailyCardService.todayKey(), default: 0] += 1
        dirty = true
    }

    private func save() {
        guard dirty else { return }
        dirty = false
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: Self.url, options: .atomic) }
    }

    /// Código de tecla do macOS → código HID (o mesmo que o teclado usa no mapa de teclas).
    static let hidUsage: [Int: Int] = [
        0x00: 0x04, 0x0B: 0x05, 0x08: 0x06, 0x02: 0x07, 0x0E: 0x08, 0x03: 0x09, 0x05: 0x0A, 0x04: 0x0B, 0x22: 0x0C,
        0x26: 0x0D, 0x28: 0x0E, 0x25: 0x0F, 0x2E: 0x10, 0x2D: 0x11, 0x1F: 0x12, 0x23: 0x13, 0x0C: 0x14, 0x0F: 0x15,
        0x01: 0x16, 0x11: 0x17, 0x20: 0x18, 0x09: 0x19, 0x0D: 0x1A, 0x07: 0x1B, 0x10: 0x1C, 0x06: 0x1D,
        0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x17: 0x22, 0x16: 0x23, 0x1A: 0x24, 0x1C: 0x25, 0x19: 0x26, 0x1D: 0x27,
        0x24: 0x28, 0x35: 0x29, 0x33: 0x2A, 0x30: 0x2B, 0x31: 0x2C, 0x1B: 0x2D, 0x18: 0x2E, 0x21: 0x2F, 0x1E: 0x30,
        0x2A: 0x31, 0x29: 0x33, 0x27: 0x34, 0x32: 0x35, 0x2B: 0x36, 0x2F: 0x37, 0x2C: 0x38, 0x39: 0x39, 0x0A: 0x64,
        0x7A: 0x3A, 0x78: 0x3B, 0x63: 0x3C, 0x76: 0x3D, 0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x64: 0x41, 0x65: 0x42,
        0x6D: 0x43, 0x67: 0x44, 0x6F: 0x45, 0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B, 0x75: 0x4C, 0x77: 0x4D, 0x79: 0x4E,
        0x7C: 0x4F, 0x7B: 0x50, 0x7D: 0x51, 0x7E: 0x52,
        0x3B: 0xE0, 0x38: 0xE1, 0x3A: 0xE2, 0x37: 0xE3, 0x3E: 0xE4, 0x3C: 0xE5, 0x3D: 0xE6, 0x36: 0xE7,
    ]
}
