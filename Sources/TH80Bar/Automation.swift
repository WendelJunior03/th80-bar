import AppKit
import Carbon.HIToolbox
import CoreAudio
import CoreMediaIO

// MARK: - Perfis de luz

struct LightPreset: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var effect: Int
    var brightness: Int
    var speed: Int
    var rainbow: Bool
    var r: Int, g: Int, b: Int

    var rgb: RGBColor { RGBColor(r: r, g: g, b: b) }

    /// Mesmo visual (ignora nome e id).
    func sameLook(_ o: LightPreset) -> Bool {
        effect == o.effect && brightness == o.brightness && speed == o.speed && rainbow == o.rainbow
            && (rainbow || (r == o.r && g == o.g && b == o.b))
    }

    static let defaults: [LightPreset] = [
        .init(name: "Trabalho", effect: 6, brightness: 5, speed: 2, rainbow: false, r: 255, g: 230, b: 200),
        .init(name: "Jogo", effect: 11, brightness: 9, speed: 3, rainbow: true, r: 255, g: 0, b: 0),
        .init(name: "Noite", effect: 6, brightness: 2, speed: 2, rainbow: false, r: 255, g: 110, b: 20),
        .init(name: "Foco", effect: 5, brightness: 4, speed: 1, rainbow: false, r: 0, g: 120, b: 255),
    ]
}

/// Persistência simples em UserDefaults.
enum Prefs {
    static func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return v
    }

    static func save<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct ScheduleSettings: Codable, Equatable {
    var enabled = false
    var nightStart = 22 * 60   // minutos desde meia-noite
    var dayStart = 7 * 60
    var dayPreset: UUID?
    var nightPreset: UUID?

    func isNight(_ date: Date = Date()) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = c.hour! * 60 + c.minute!
        return nightStart > dayStart ? (m >= nightStart || m < dayStart) : (m >= nightStart && m < dayStart)
    }
}

struct MeetingSettings: Codable, Equatable {
    var enabled = false
    var useCamera = true
    var useMicrophone = true
    var r = 255, g = 0, b = 0
    var rgb: RGBColor { RGBColor(r: r, g: g, b: b) }
}

struct LockSettings: Codable, Equatable {
    var enabled = false
    var lightsOff = true
    var awayScreen = true
    var awayText = "Volto já"
}

// MARK: - Câmera e microfone em uso

enum MediaUsage {
    static func microphoneInUse() -> Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size = UInt32(0)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used = UInt32(0)
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == noErr else { return false }
        for d in devices {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running = UInt32(0)
            var u = UInt32(0)
            if CMIOObjectGetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

// MARK: - Atalho global (⌃⌥P alterna perfis)

final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        Self.handlers[id] = action
        if !Self.installed {
            Self.installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { GlobalHotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let hkID = EventHotKeyID(signature: OSType(0x5448_3830), id: id) // "TH80"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }
}

// MARK: - Pomodoro

struct PomodoroSettings: Codable, Equatable {
    var focusMinutes = 25
    var breakMinutes = 5
    var useLight = true
    var useScreen = true
    var focusPreset: UUID?
    var breakPreset: UUID?
    var sound = true
}

enum PomodoroPhase: String { case focus, rest }

// MARK: - Perfil por app

struct AppRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var bundleID: String
    var name: String
    var preset: UUID?
}
