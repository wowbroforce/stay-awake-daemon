import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif

// Minecraft RCON client (Source RCON protocol over raw TCP)

struct RCONError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private enum RCONPacketType {
    static let auth: Int32 = 3
    static let authResponse: Int32 = 2
    static let execCommand: Int32 = 2
}

final class RCONClient {
    private var socketFD: Int32 = -1

    func connect(host: String, port: UInt16) throws {
        socketFD = socket(AF_INET, sysSockStream, 0)
        guard socketFD >= 0 else { throw RCONError(message: "socket() failed") }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw RCONError(message: "invalid RCON host address")
        }

        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                sysConnect(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw RCONError(message: "connect() failed (is rcon.enabled=true?)") }
    }

    func close() {
        if socketFD >= 0 { sysClose(socketFD) }
        socketFD = -1
    }

    private func sendPacket(requestID: Int32, type: Int32, body: String) throws {
        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: requestID.littleEndian) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: type.littleEndian) { Array($0) })
        payload.append(contentsOf: body.utf8)
        payload.append(0) // body terminator
        payload.append(0) // packet terminator

        var length = Int32(payload.count).littleEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(payload)

        try packet.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) in
            guard let base = rawBuf.baseAddress else { return }
            var totalSent = 0
            while totalSent < packet.count {
                let sent = sysSend(socketFD, base + totalSent, packet.count - totalSent, 0)
                guard sent > 0 else { throw RCONError(message: "send() failed") }
                totalSent += sent
            }
        }
    }

    private func readExactly(_ count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRead = 0
        try buffer.withUnsafeMutableBytes { (rawBuf: UnsafeMutableRawBufferPointer) in
            guard let base = rawBuf.baseAddress else { return }
            while totalRead < count {
                let n = sysRecv(socketFD, base + totalRead, count - totalRead, 0)
                guard n > 0 else { throw RCONError(message: "recv() failed or connection closed") }
                totalRead += n
            }
        }
        return buffer
    }

    private func readInt32LE() throws -> Int32 {
        let bytes = try readExactly(4)
        return bytes.withUnsafeBytes { $0.load(as: Int32.self) }.littleEndian
    }

    private func recvPacket() throws -> (requestID: Int32, type: Int32, body: String) {
        let length = try readInt32LE()
        guard (10...65536).contains(length) else {
            throw RCONError(message: "invalid RCON packet length \(length)")
        }
        let payload = try readExactly(Int(length))
        let requestID = payload[0..<4].withUnsafeBytes { $0.load(as: Int32.self) }.littleEndian
        let type = payload[4..<8].withUnsafeBytes { $0.load(as: Int32.self) }.littleEndian
        let body = String(decoding: payload[8..<(payload.count - 2)], as: UTF8.self)
        return (requestID, type, body)
    }

    func authenticate(password: String) throws {
        try sendPacket(requestID: 1, type: RCONPacketType.auth, body: password)
        var response = try recvPacket()
        // Some RCON server implementations send a spurious empty response
        // packet before the real auth response - skip it if present.
        if response.type != RCONPacketType.authResponse {
            response = try recvPacket()
        }
        guard response.requestID == 1 else {
            throw RCONError(message: "RCON authentication rejected (wrong password?)")
        }
    }

    func execute(command: String) throws -> String {
        try sendPacket(requestID: 2, type: RCONPacketType.execCommand, body: command)
        return try recvPacket().body
    }
}

func minecraftHasPlayers(_ minecraft: MinecraftConfig) -> Bool {
    let client = RCONClient()
    defer { client.close() }
    do {
        try client.connect(host: minecraft.host, port: minecraft.port)
        try client.authenticate(password: minecraft.password)
        let response = try client.execute(command: "list")
        // "There are 2 of a max of 20 players online: alice, bob"
        guard let range = response.range(of: "There are ") else { return false }
        let afterPrefix = response[range.upperBound...]
        guard let numberEnd = afterPrefix.firstIndex(of: " ") else { return false }
        return Int(afterPrefix[afterPrefix.startIndex..<numberEnd]).map { $0 > 0 } ?? false
    } catch {
        logError("RCON check failed\(minecraft.logLabel): \(error)")
        return false
    }
}
