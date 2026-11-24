import Foundation

/// Protocolo da tela/iluminação do TH80 Pro V2.
///
/// Adaptado de th80-studio (Clouddios, MIT): report ID 4, pacotes de 64 bytes,
/// checksum = soma de 16 bits dos bytes 3..63 (little endian nos bytes 1..2),
/// byte 3 = comando, byte 4 = tamanho, bytes 5..7 = posição (24 bits LE),
/// dados a partir do byte 8 (até 56 bytes). Respostas têm 8 bytes.
enum TH80Protocol {
    static let screenWidth = 240
    static let screenHeight = 135
    static let frameBytes = 65_536
    static let maxFrames = 18
    static let chunk = 56

    enum Command: UInt8 {
        case begin = 0x01
        case end = 0x02
        case readConfig = 0x05
        case writeConfig = 0x06
        case writeImage = 0x21
        case eraseImages = 0x23
    }

    static func packet(_ command: UInt8, data: [UInt8] = [], position: Int = 0) -> [UInt8] {
        precondition(data.count <= chunk && (0...0xFFFFFF).contains(position))
        var p = [UInt8](repeating: 0, count: 64)
        p[0] = 4
        p[3] = command
        p[4] = UInt8(data.count)
        p[5] = UInt8(position & 0xFF)
        p[6] = UInt8((position >> 8) & 0xFF)
        p[7] = UInt8((position >> 16) & 0xFF)
        p.replaceSubrange(8..<(8 + data.count), with: data)
        let sum = p[3...].reduce(0) { $0 + Int($1) } & 0xFFFF
        p[1] = UInt8(sum & 0xFF)
        p[2] = UInt8(sum >> 8)
        return p
    }

    /// Consulta somente leitura de 4 bytes do bloco de configuração.
    static func configQuery(offset: Int) -> [UInt8] {
        var p = packet(Command.readConfig.rawValue, position: offset)
        p[4] = 4
        let sum = p[3...].reduce(0) { $0 + Int($1) } & 0xFFFF
        p[1] = UInt8(sum & 0xFF)
        p[2] = UInt8(sum >> 8)
        return p
    }
}

/// Bloco de configuração de 48 bytes (iluminação + tela + relógio).
struct TH80Config: Equatable {
    var bytes: [UInt8]

    init(bytes: [UInt8]) {
        precondition(bytes.count == 48)
        self.bytes = bytes
    }

    // Iluminação (offsets confirmados no TH80 por th80-studio)
    var effect: Int { get { Int(bytes[1]) } set { bytes[1] = UInt8(newValue) } }
    var brightness: Int { get { Int(bytes[2]) } set { bytes[2] = UInt8(newValue) } }
    var speed: Int { get { Int(bytes[3]) } set { bytes[3] = UInt8(newValue) } }
    /// 0 = cor fixa (RGB abaixo), 255 = arco-íris.
    var colorMode: Int { get { Int(bytes[5]) } set { bytes[5] = UInt8(newValue) } }
    var red: Int { get { Int(bytes[6]) } set { bytes[6] = UInt8(newValue) } }
    var green: Int { get { Int(bytes[7]) } set { bytes[7] = UInt8(newValue) } }
    var blue: Int { get { Int(bytes[8]) } set { bytes[8] = UInt8(newValue) } }

    // Tela
    /// 0 = relógio, 1 = imagem/animação salva.
    var screenMode: Int { get { Int(bytes[33]) } set { bytes[33] = UInt8(newValue) } }
    var frameCount: Int { Int(bytes[34]) }
    var frameDelayMs: Int { Int(bytes[43]) | Int(bytes[44]) << 8 }

    mutating func setClock(_ date: Date) {
        let c = Calendar(identifier: .gregorian).dateComponents(
            [.second, .minute, .hour, .weekday, .day, .month, .year], from: date)
        func bcd(_ v: Int) -> UInt8 { UInt8(((v / 10) << 4) | (v % 10)) }
        bytes[35] = bcd(c.second!)
        bytes[36] = bcd(c.minute!)
        bytes[37] = bcd(c.hour!)
        bytes[38] = UInt8(c.weekday! - 1) // domingo = 0
        bytes[39] = bcd(c.day!)
        bytes[40] = bcd(c.month!)
        bytes[41] = bcd(c.year! - 2000)
    }

    /// Posição 1 (byte 34) e posição 2 (byte 46); mostra a posição 1.
    mutating func setSlots(count0: Int, count1: Int, delayMs: Int) {
        screenMode = 1
        bytes[34] = UInt8(count0)
        bytes[46] = UInt8(count1)
        let d = min(65_535, max(60, delayMs))
        bytes[43] = UInt8(d & 0xFF)
        bytes[44] = UInt8(d >> 8)
    }
}

/// Operações de alto nível sobre o transporte HID. Rodam fora da main thread.
struct TH80Client {
    let hid: HIDDevice

    private func exchange(_ command: TH80Protocol.Command, data: [UInt8] = [], position: Int = 0) throws {
        if command == .end { Thread.sleep(forTimeInterval: 0.1) }
        let packet = TH80Protocol.packet(command.rawValue, data: data, position: position)
        let reply = try hid.transact(packet, timeout: command == .eraseImages ? 30 : 3)
        if reply[7] == 0xFE || reply[7] == 0xFF {
            throw HIDDevice.HIDError.rejected(command.rawValue, reply)
        }
    }

    func readConfig() throws -> TH80Config {
        var out: [UInt8] = []
        for offset in stride(from: 0, to: 48, by: 4) {
            let reply = try hid.transact(TH80Protocol.configQuery(offset: offset))
            out += reply[4..<8]
        }
        return TH80Config(bytes: out)
    }

    func writeConfig(_ config: TH80Config) throws {
        try exchange(.begin)
        try exchange(.writeConfig, data: config.bytes)
        try exchange(.end)
    }

    /// Grava quadros RGB565 (64 KiB cada): posição 1 seguida da posição 2, num fluxo só.
    /// O envio sempre apaga toda a memória de imagens, então as duas posições vão juntas.
    func uploadSlots(_ slot0: [Data], _ slot1: [Data], delayMs: Int, base: TH80Config,
                     progress: @escaping (Double) -> Void) throws {
        var config = base
        config.setSlots(count0: slot0.count, count1: slot1.count, delayMs: delayMs)
        var payload = Data()
        (slot0 + slot1).forEach { payload.append($0) }

        try writeConfig(config)
        try exchange(.eraseImages)
        try exchange(.begin)
        let bytes = [UInt8](payload)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + TH80Protocol.chunk, bytes.count)
            try exchange(.writeImage, data: Array(bytes[offset..<end]), position: offset)
            offset = end
            if (offset / TH80Protocol.chunk) % 64 == 0 {
                progress(Double(offset) / Double(bytes.count))
            }
        }
        try exchange(.end)
        progress(1)
    }
}
