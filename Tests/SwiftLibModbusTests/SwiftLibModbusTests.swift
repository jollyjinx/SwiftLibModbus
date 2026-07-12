//
//  SwiftLibModbusTests.swift
//

import CModbus
import Foundation
import SwiftLibModbus
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin)
private let streamSocketType = SOCK_STREAM
#else
private let streamSocketType = Int32(SOCK_STREAM.rawValue)
#endif

private struct TCPListeningSocket
{
    let descriptor: Int32
    let port: UInt16

    init() throws
    {
        let descriptor = socket(AF_INET, streamSocketType, 0)
        guard descriptor >= 0
        else
        {
            throw NSError(domain: "TCPListeningSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
        }

        var reuseAddress: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout.size(ofValue: reuseAddress))) == 0
        else
        {
            let error = NSError(domain: "TCPListeningSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            _ = close(descriptor)
            throw error
        }

        var address = sockaddr_in()
#if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
#endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0
        else
        {
            let error = NSError(domain: "TCPListeningSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            _ = close(descriptor)
            throw error
        }

        guard listen(descriptor, 8) == 0
        else
        {
            let error = NSError(domain: "TCPListeningSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            _ = close(descriptor)
            throw error
        }

        var boundAddress = sockaddr_in()
#if canImport(Darwin)
        boundAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
#endif
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0
        else
        {
            let error = NSError(domain: "TCPListeningSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            _ = close(descriptor)
            throw error
        }

        self.descriptor = descriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    func closeSocket()
    {
        _ = close(descriptor)
    }
}

private func responseTimeout(of context: OpaquePointer) -> timeval
{
    var timeout = timeval()
    modbus_get_response_timeout(context, &timeout)
    return timeout
}

private func receiveExactly(_ count: Int, from socket: Int32) throws -> [UInt8]
{
    var bytes = [UInt8](repeating: 0, count: count)
    var received = 0

    while received < count
    {
        let result = bytes.withUnsafeMutableBytes { buffer in
            recv(socket, buffer.baseAddress!.advanced(by: received), count - received, 0)
        }
        guard result > 0
        else
        {
            throw NSError(domain: "ModbusTestServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Could not receive request"])
        }
        received += result
    }

    return bytes
}

private func sendAll(_ bytes: [UInt8], to socket: Int32) throws
{
    var sent = 0

    while sent < bytes.count
    {
        let result = bytes.withUnsafeBytes { buffer in
            send(socket, buffer.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
        }
        guard result > 0
        else
        {
            throw NSError(domain: "ModbusTestServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Could not send response"])
        }
        sent += result
    }
}

private func serveRegisterReads(count: Int, on server: TCPListeningSocket) async throws -> [UInt8]
{
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async
        {
            let client = accept(server.descriptor, nil, nil)
            guard client >= 0
            else
            {
                continuation.resume(throwing: NSError(domain: "ModbusTestServer", code: Int(errno)))
                return
            }
            defer { _ = close(client) }

            do
            {
                var addresses = [UInt8]()
                for _ in 0 ..< count
                {
                    let header = try receiveExactly(7, from: client)
                    let messageLength = Int(header[4]) << 8 | Int(header[5])
                    let body = try receiveExactly(messageLength - 1, from: client)
                    let address = header[6]
                    addresses.append(address)

                    let response: [UInt8] = [
                        header[0], header[1], 0, 0, 0, 5,
                        address, body[0], 2, 0, address,
                    ]
                    try sendAll(response, to: client)
                }
                continuation.resume(returning: addresses)
            }
            catch
            {
                continuation.resume(throwing: error)
            }
        }
    }
}

// Kept as a compile-time contract for all address-aware overloads. The packet-level
// test below exercises the common transaction path without requiring live hardware.
private func compileAddressAwareAPI(_ device: ModbusDevice) async throws
{
    let _: [Bool] = try await device.readInputBitsFrom(startAddress: 0, count: 1, type: .coil, deviceAddress: 1)
    let _: [Bool] = try await device.readInputCoilsFrom(startAddress: 0, count: 1, deviceAddress: 1)
    let _: [Bool] = try await device.readInputBitsFrom(startAddress: 0, count: 1, deviceAddress: 1)
    try await device.writeInputCoil(startAddress: 0, value: true, deviceAddress: 1)

    let _: [UInt16] = try await device.readInputRegisters(from: 0, count: 1, deviceAddress: 1)
    let _: [UInt16] = try await device.readHoldingRegisters(from: 0, count: 1, deviceAddress: 1)
    let _: [UInt16] = try await device.readRegisters(from: 0, count: 1, type: .holding, deviceAddress: 1)
    let _: [Float32] = try await device.readRegisters(from: 0, count: 1, type: .holding, deviceAddress: 1)
    let _: String = try await device.readASCIIString(from: 0, count: 1, type: .holding, deviceAddress: 1)
    try await device.writeRegisters(to: 0, arrayToWrite: [UInt16(1)], deviceAddress: 1)
    try await device.writeASCIIString(start: 0, count: 1, string: "A", deviceAddress: 1)
}

@Suite("Device Tests")
struct DeviceTests
{
    @Test("Reverse Engineer HM310T", .disabled("Only works when attached"))
    func reverseEngineerHM310T() async throws
    {
        let modbusDevice = try ModbusDevice(device: "/dev/tty.usbserial-42340", baudRate: 9600)
        let stripesize = 0x10

        var store = [Int: [UInt16]]()
        let emptyline = [UInt16](repeating: 0, count: stripesize)

        func readData(from address: Int) async throws
        {
            let data: [UInt16] = try await modbusDevice.readRegisters(from: address, count: stripesize, type: .holding)

            let previous: [UInt16] = store[address] ?? emptyline

            if data != previous
            {
                print("\(String(format: "%04x", address)): \(data.map { $0 == 0 ? "  -   " : String(format: "%04x  ", $0) }.joined(separator: " ")) ")
                print("\(String(format: "%04x", address)): \(data.map { $0 == 0 ? "      " : String(format: "%05d ", $0) }.joined(separator: " ")) ")
                print("")
                store[address] = data
            }
        }

        for address in stride(from: 0x000, to: 0xFFFF, by: stripesize)
        {
            try await readData(from: address)
        }

        for _ in 0 ... 20
        {
            print("Reading again")

            for address in store.keys
            {
                try await readData(from: address)
            }
        }
    }

    @Test("Float32 Phoenix Controller", .disabled("Only works when a Phoenix Contact device is attached"))
    func float32PhoenixController() async throws
    {
        let modbusDevice = try ModbusDevice(networkAddress: "10.98.16.12", port: 502, deviceAddress: 180)

        let startAddress = 352
        let endAddress = 358
        let stridesize: Int = MemoryLayout<Float32>.size / MemoryLayout<UInt16>.size
        let count = Int(endAddress - startAddress) / stridesize

        var store = [Int: [Float32]]()
        let emptyline = [Float32](repeating: 0, count: count)

        func readData(from address: Int) async throws
        {
            let data: [Float32] = try await modbusDevice.readRegisters(from: startAddress, count: count, type: .holding, endianness: .littleEndian)
            let previous: [Float32] = store[address] ?? emptyline

            if data != previous
            {
                print("\(String(format: "0x%04x | %05d", address, address)): \(data.map { $0 == 0 ? "  -   " : String(format: "%08x  ", $0.bitPattern) }.joined(separator: " ")) ")
                print("\(String(format: "0x%04x | %05d", address, address)): \(data.map { $0 == 0 ? "      " : String(format: "%.2f ", $0) }.joined(separator: " ")) ")
                print("")
                store[address] = data
            }
        }

        for address in stride(from: 352, to: 358, by: stridesize)
        {
            try await readData(from: address)
        }

        for _ in 0 ... 20
        {
            print("Reading again")

            for address in store.keys
            {
                try await readData(from: address)
            }
        }
    }

    @Test("TCP connect preserves configured response timeout")
    func tcpConnectPreservesConfiguredResponseTimeout() throws
    {
        let server = try TCPListeningSocket()
        defer { server.closeSocket() }

        guard let context = modbus_new_tcp("127.0.0.1", Int32(server.port))
        else
        {
            Issue.record("Expected modbus_new_tcp to create a TCP context")
            return
        }
        defer { modbus_free(context) }

        var configuredTimeout = timeval(tv_sec: 0, tv_usec: 200_000)
        modbus_set_response_timeout(context, &configuredTimeout)

        let expectedTimeout = responseTimeout(of: context)

        for _ in 0 ..< 5
        {
            let connectResult = modbus_connect(context)
            #expect(connectResult == 0)
            guard connectResult == 0
            else
            {
                return
            }

            modbus_close(context)

            let currentTimeout = responseTimeout(of: context)
            #expect(currentTimeout.tv_sec == expectedTimeout.tv_sec)
            #expect(currentTimeout.tv_usec == expectedTimeout.tv_usec)
        }
    }

    @Test("TCP operations select their device address atomically")
    func tcpOperationsSelectDeviceAddressAtomically() async throws
    {
        let server = try TCPListeningSocket()
        defer { server.closeSocket() }

        async let observedAddresses = serveRegisterReads(count: 2, on: server)
        let device = try ModbusDevice(networkAddress: "127.0.0.1", port: server.port, deviceAddress: 42, disconnectWhenIdleAfter: 0)

        async let firstRead: [UInt16] = device.readRegisters(from: 0, count: 1, type: .holding, deviceAddress: 1)
        async let secondRead: [UInt16] = device.readRegisters(from: 0, count: 1, type: .holding, deviceAddress: 2)

        let (first, second, addresses) = try await (firstRead, secondRead, observedAddresses)
        #expect(Set(addresses) == Set([1, 2]))
        #expect(Set([first[0], second[0]]) == Set([1, 2]))
    }
}
