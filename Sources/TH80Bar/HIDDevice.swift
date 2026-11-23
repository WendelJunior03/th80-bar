import Foundation
import IOKit.hid

/// Transporte HID para a interface proprietária da tela do TH80 Pro V2
/// (VID 0x320F, PID 0x5055, usage page 0xFF1C, usage 0x92, report ID 4).
///
/// O IOHIDManager roda numa thread própria com run loop; `transact` bloqueia
/// a thread chamadora (nunca a main) até a resposta chegar.
final class HIDDevice: @unchecked Sendable {
    static let vendorID = 0x320F
    static let productID = 0x5055
    static let usagePage = 0xFF1C
    static let usage = 0x92

    enum HIDError: LocalizedError {
        case notConnected
        case writeFailed(IOReturn)
        case timeout(UInt8)
        case rejected(UInt8, [UInt8])

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Teclado não conectado por USB."
            case .writeFailed(let r): return String(format: "Falha ao enviar para o teclado (0x%08x).", r)
            case .timeout(let c): return String(format: "Sem resposta do teclado ao comando 0x%02X.", c)
            case .rejected(let c, let r):
                return String(format: "O teclado recusou o comando 0x%02X (%@).", c,
                              r.map { String(format: "%02x", $0) }.joined())
            }
        }
    }

    /// Chamado na main thread quando o teclado conecta/desconecta.
    var onConnectionChange: ((Bool) -> Void)?

    private var manager: IOHIDManager!
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    private var thread: Thread!
    private let ready = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var pending: [UInt8]?          // pedido aguardando resposta
    private var response: [UInt8]?
    private let responseSignal = DispatchSemaphore(value: 0)
    /// Serializa transações (uma de cada vez).
    private let transactionLock = NSLock()

    var isConnected: Bool { lock.withLock { device != nil } }

    func start() {
        thread = Thread { [unowned self] in self.runLoopMain() }
        thread.name = "TH80 HID"
        thread.start()
        ready.wait()
    }

    private func runLoopMain() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: Self.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDDevice>.fromOpaque(ctx!).takeUnretainedValue().attach(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDDevice>.fromOpaque(ctx!).takeUnretainedValue().detach(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        ready.signal()
        while true { CFRunLoopRunInMode(.defaultMode, 3600, false) }
    }

    private func attach(_ dev: IOHIDDevice) {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 128, { ctx, _, _, _, _, report, len in
            let bytes = Array(UnsafeBufferPointer(start: report, count: len))
            Unmanaged<HIDDevice>.fromOpaque(ctx!).takeUnretainedValue().received(bytes)
        }, ctx)
        lock.withLock { device = dev }
        DispatchQueue.main.async { self.onConnectionChange?(true) }
    }

    private func detach(_ dev: IOHIDDevice) {
        lock.withLock { if device == dev { device = nil } }
        responseSignal.signal() // destrava quem estiver esperando
        DispatchQueue.main.async { self.onConnectionChange?(false) }
    }

    private func received(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        // A resposta ecoa report ID, checksum e comando (bytes 0..3).
        guard let req = pending, bytes.count >= 8, Array(bytes[0..<4]) == Array(req[0..<4]) else { return }
        pending = nil
        response = bytes
        responseSignal.signal()
    }

    /// Envia um pacote de 64 bytes e devolve a resposta de 8 bytes.
    func transact(_ packet: [UInt8], timeout: TimeInterval = 3) throws -> [UInt8] {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        guard let dev = lock.withLock({ device }) else { throw HIDError.notConnected }

        while responseSignal.wait(timeout: .now()) == .success {} // descarta sinais antigos
        lock.withLock { pending = packet; response = nil }

        let result = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(packet[0]), $0.baseAddress!, packet.count)
        }
        guard result == kIOReturnSuccess else {
            lock.withLock { pending = nil }
            throw HIDError.writeFailed(result)
        }
        _ = responseSignal.wait(timeout: .now() + timeout)
        let reply: [UInt8]? = lock.withLock {
            defer { pending = nil }
            return response
        }
        guard let reply else {
            throw isConnected ? HIDError.timeout(packet[3]) : HIDError.notConnected
        }
        return reply
    }
}
