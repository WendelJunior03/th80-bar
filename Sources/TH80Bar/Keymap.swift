import Foundation
import Observation

// MARK: - Catálogo de funções (códigos VIA/QMK básicos)

struct KeyFunction: Hashable, Identifiable {
    let code: Int
    let label: String
    let group: String
    var id: Int { code }
}

enum KeyCatalog {
    static let modifierBits: [(bit: Int, symbol: String, name: String)] = [
        (0x0100, "⌃", "Control"), (0x0200, "⇧", "Shift"), (0x0400, "⌥", "Option/Alt"), (0x0800, "⌘", "Command/Win"),
    ]

    static let all: [KeyFunction] = {
        var list: [KeyFunction] = [
            .init(code: 0x00, label: "Nada", group: "Especial"),
            .init(code: 0x01, label: "Transparente", group: "Especial"),
        ]
        for i in 0..<26 { list.append(.init(code: 0x04 + i, label: String(UnicodeScalar(65 + i)!), group: "Letras")) }
        for i in 0..<10 { list.append(.init(code: 0x1E + i, label: "\((i + 1) % 10)", group: "Números")) }
        let symbols: [(Int, String)] = [
            (0x28, "Enter"), (0x29, "Esc"), (0x2A, "Backspace"), (0x2B, "Tab"), (0x2C, "Espaço"),
            (0x2D, "-"), (0x2E, "="), (0x2F, "["), (0x30, "]"), (0x31, "\\"), (0x33, ";"), (0x34, "'"),
            (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock"), (0x64, "ISO \\"),
        ]
        symbols.forEach { list.append(.init(code: $0.0, label: $0.1, group: "Símbolos e edição")) }
        for i in 0..<12 { list.append(.init(code: 0x3A + i, label: "F\(i + 1)", group: "Funções")) }
        for i in 0..<12 { list.append(.init(code: 0x68 + i, label: "F\(i + 13)", group: "Funções")) }
        let nav: [(Int, String)] = [
            (0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"), (0x4A, "Home"),
            (0x4B, "Page Up"), (0x4C, "Delete"), (0x4D, "End"), (0x4E, "Page Down"),
            (0x4F, "→"), (0x50, "←"), (0x51, "↓"), (0x52, "↑"),
        ]
        nav.forEach { list.append(.init(code: $0.0, label: $0.1, group: "Navegação")) }
        let mods: [(Int, String)] = [
            (0xE0, "Control esq."), (0xE1, "Shift esq."), (0xE2, "Option/Alt esq."), (0xE3, "Command/Win esq."),
            (0xE4, "Control dir."), (0xE5, "Shift dir."), (0xE6, "Option/Alt dir."), (0xE7, "Command/Win dir."),
        ]
        mods.forEach { list.append(.init(code: $0.0, label: $0.1, group: "Modificadores")) }
        let media: [(Int, String)] = [
            (0xA8, "Mudo"), (0xA9, "Volume +"), (0xAA, "Volume −"), (0xAB, "Próxima faixa"),
            (0xAC, "Faixa anterior"), (0xAD, "Parar"), (0xAE, "Play/Pause"), (0xBD, "Brilho +"), (0xBE, "Brilho −"),
        ]
        media.forEach { list.append(.init(code: $0.0, label: $0.1, group: "Mídia")) }
        return list
    }()

    static let groups = ["Letras", "Números", "Símbolos e edição", "Funções", "Navegação", "Modificadores", "Mídia", "Especial"]

    private static let byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    /// Rótulo curto para mostrar na tecla.
    static func shortLabel(_ code: Int) -> String {
        if let f = byCode[code] {
            switch f.code {
            case 0x00: return "∅"
            case 0x01: return "▽"
            case 0x2A: return "⌫"
            case 0x28: return "⏎"
            case 0x2B: return "⇥"
            case 0x2C: return "␣"
            case 0x39: return "⇪"
            case 0xE0, 0xE4: return "⌃"
            case 0xE1, 0xE5: return "⇧"
            case 0xE2, 0xE6: return "⌥"
            case 0xE3, 0xE7: return "⌘"
            case 0xA8: return "🔇"
            case 0xA9: return "🔊"
            case 0xAA: return "🔉"
            case 0xAE: return "⏯"
            case 0xAB: return "⏭"
            case 0xAC: return "⏮"
            default:
                return f.label.replacingOccurrences(of: "Page ", with: "Pg").replacingOccurrences(of: "Print Screen", with: "PrtSc")
                    .replacingOccurrences(of: "Scroll Lock", with: "ScrLk").replacingOccurrences(of: "Backspace", with: "⌫")
            }
        }
        if let (mods, base) = shortcutParts(code) { return mods + shortLabel(base) }
        if code == fnCode { return "Fn" }
        return String(format: "%04X", code)
    }

    static func longLabel(_ code: Int) -> String {
        if let f = byCode[code] { return f.label }
        if let (mods, base) = shortcutParts(code) { return "Atalho \(mods)\(longLabel(base))" }
        if code == fnCode { return "Fn (função do teclado)" }
        return String(format: "Especial (0x%04X)", code)
    }

    /// Código próprio da Epomaker para a tecla Fn (lido do teclado).
    static let fnCode = 0x5F10

    static func isKnown(_ code: Int) -> Bool { byCode[code] != nil || shortcutParts(code) != nil }

    /// Códigos de atalho QMK: bits de modificador (0x0100–0x0F00) + tecla básica.
    static func shortcutParts(_ code: Int) -> (String, Int)? {
        let mods = code & 0x0F00, base = code & 0xFF
        guard code & ~0x0FFF == 0, mods != 0, byCode[base] != nil, base > 0x01 else { return nil }
        let symbols = modifierBits.filter { mods & $0.bit != 0 }.map(\.symbol).joined()
        return (symbols, base)
    }
}

// MARK: - Cliente VIA

struct VIAClient {
    let hid: HIDDevice
    static let rows = 8, cols = 16

    private func request(_ bytes: [UInt8]) throws -> [UInt8] {
        try hid.transact(bytes + [UInt8](repeating: 0, count: 32 - bytes.count))
    }

    func layerCount() throws -> Int { Int(try request([0x11])[1]) }

    /// Lê a matriz inteira de uma camada (8×16 códigos de 16 bits) em blocos de 28 bytes.
    func readLayer(_ layer: Int) throws -> [Int] {
        let length = Self.rows * Self.cols * 2
        var raw: [UInt8] = []
        var pos = 0
        while pos < length {
            let size = min(28, length - pos)
            let offset = layer * length + pos
            let reply = try request([0x12, UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(size)])
            raw += reply[4..<(4 + size)]
            pos += size
        }
        return stride(from: 0, to: length, by: 2).map { Int(raw[$0]) << 8 | Int(raw[$0 + 1]) }
    }

    func readKey(layer: Int, row: Int, col: Int) throws -> Int {
        let offset = (layer * Self.rows * Self.cols + row * Self.cols + col) * 2
        let reply = try request([0x12, UInt8(offset >> 8), UInt8(offset & 0xFF), 2])
        return Int(reply[4]) << 8 | Int(reply[5])
    }

    func setKey(layer: Int, row: Int, col: Int, code: Int) throws {
        _ = try request([0x05, UInt8(layer), UInt8(row), UInt8(col), UInt8(code >> 8), UInt8(code & 0xFF)])
        guard try readKey(layer: layer, row: row, col: col) == code else {
            throw KeymapError.notConfirmed
        }
    }
}

enum KeymapError: LocalizedError {
    case notConfirmed
    var errorDescription: String? { "O teclado não confirmou a nova função da tecla." }
}

// MARK: - Modelo da janela de teclas

@MainActor
@Observable
final class KeymapModel {
    var connected = false
    var layers: [[Int]] = []         // [camada][row*16+col]
    var original: [[Int]] = []       // backup feito na primeira leitura
    var layer = 0
    var selected: KeyCap?
    var busy = false
    var status: String?
    var errorMessage: String?

    private let hid = HIDDevice.via()
    private let queue = DispatchQueue(label: "th80.via")

    private static var backupURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TH80Bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("teclas-originais.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.backupURL),
           let saved = try? JSONDecoder().decode([[Int]].self, from: data) { original = saved }
        hid.onConnectionChange = { [weak self] up in
            self?.connected = up
            if up { self?.reload() } else { self?.layers = [] }
        }
        hid.start()
    }

    func code(_ key: KeyCap, layer l: Int? = nil) -> Int? {
        let l = l ?? layer
        guard layers.indices.contains(l) else { return nil }
        return layers[l][key.row * VIAClient.cols + key.col]
    }

    func originalCode(_ key: KeyCap) -> Int? {
        guard original.indices.contains(layer) else { return nil }
        return original[layer][key.row * VIAClient.cols + key.col]
    }

    func isChanged(_ key: KeyCap) -> Bool {
        guard let c = code(key), let o = originalCode(key) else { return false }
        return c != o
    }

    var changedCount: Int {
        guard layers.count == original.count else { return 0 }
        return zip(layers, original).reduce(0) { acc, pair in acc + zip(pair.0, pair.1).filter { $0 != $1 }.count }
    }

    private func run(_ label: String, _ work: @escaping (VIAClient) throws -> [[Int]]) {
        guard !busy else { return }
        busy = true
        status = label
        errorMessage = nil
        let client = VIAClient(hid: hid)
        queue.async {
            let result = Result { try work(client) }
            DispatchQueue.main.async {
                self.busy = false
                self.status = nil
                switch result {
                case .success(let l):
                    self.layers = l
                    if self.original.isEmpty, !l.isEmpty {
                        self.original = l
                        if let data = try? JSONEncoder().encode(l) { try? data.write(to: Self.backupURL) }
                    }
                case .failure(let e): self.errorMessage = e.localizedDescription
                }
            }
        }
    }

    func reload() {
        run("Lendo teclas…") { c in
            let n = min(4, try c.layerCount())
            return try (0..<n).map { try c.readLayer($0) }
        }
    }

    func assign(_ code: Int, to key: KeyCap) {
        let l = layer
        let current = layers
        run("Gravando tecla…") { c in
            try c.setKey(layer: l, row: key.row, col: key.col, code: code)
            var updated = current
            updated[l][key.row * VIAClient.cols + key.col] = code
            return updated
        }
    }

    func restoreKey(_ key: KeyCap) {
        guard let o = originalCode(key) else { return }
        assign(o, to: key)
    }

    func restoreAll() {
        let orig = original
        let current = layers
        run("Restaurando teclas originais…") { c in
            var updated = current
            for l in orig.indices where updated.indices.contains(l) {
                for i in orig[l].indices where updated[l][i] != orig[l][i] {
                    try c.setKey(layer: l, row: i / VIAClient.cols, col: i % VIAClient.cols, code: orig[l][i])
                    updated[l][i] = orig[l][i]
                }
            }
            return updated
        }
    }
}
