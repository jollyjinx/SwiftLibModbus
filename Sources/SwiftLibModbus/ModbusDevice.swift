//
//  ModbusDevice.swift
//

import CModbus
import Dispatch
import Foundation

#if !NSEC_PER_SEC
    let NSEC_PER_SEC = 1_000_000_000
#endif

public enum ModbusError: Error
{
    case couldNotCreateDevice(error: String)
    case couldNotConnect(error: String)
    case couldNotRead(error: String)
    case couldNotWrite(error: String)
}

public enum ModbusRegisterType: String, Encodable, Decodable, Sendable
{
    case coil
    case discrete
    case holding
    case input
}

public enum ModbusDeviceEndianness: String, Encodable, Decodable, Sendable
{
    case bigEndian
    case littleEndian
}

public enum ModbusParity: Sendable
{
    case none
    case even
    case odd

    var value: UInt8
    { switch self
        {
            case .none: return Character("N").asciiValue!
            case .even: return Character("E").asciiValue!
            case .odd: return Character("O").asciiValue!
        }
    }
}

public actor ModbusDevice
{
    // Run the actor on a dedicated serial executor so blocking libmodbus calls
    // do not pin Swift's cooperative thread pool.
#if canImport(Darwin)
    private let ioQueue = DispatchSerialQueue(label: "SwiftLibModbus.ModbusDevice")

    nonisolated public var unownedExecutor: UnownedSerialExecutor
    {
        ioQueue.asUnownedSerialExecutor()
    }
#endif

    let modbusdevice: OpaquePointer
    let defaultDeviceAddress: UInt16
    let autoReconnectAfter: TimeInterval // SMA servers tend to hang when a connection is too long
    let disconnectWhenIdleAfter: TimeInterval // SMA servers have a problem when tcp connection is not used and keep it internally forever

    var connected = false

    public init(device: String, slaveid: Int = 1, baudRate: Int = 9600, dataBits: Int = 8, parity: ModbusParity = .none, stopBits: Int = 1, autoReconnectAfter: TimeInterval = 10.0, disconnectWhenIdleAfter: TimeInterval = 10.0) throws
    {
        guard let deviceAddress = UInt16(exactly: slaveid), deviceAddress <= 247
        else
        {
            throw ModbusError.couldNotCreateDevice(error: "Invalid Modbus device address: \(slaveid)")
        }

        guard let modbusdevice = modbus_new_rtu(device.cString(using: .utf8), Int32(baudRate), CChar(parity.value), Int32(dataBits), Int32(stopBits))
        else
        {
            throw ModbusError.couldNotCreateDevice(error: "Could not create device:\(device) (\(baudRate)-\(parity)-\(stopBits))")
        }
        self.autoReconnectAfter = autoReconnectAfter
        self.disconnectWhenIdleAfter = disconnectWhenIdleAfter
        self.modbusdevice = modbusdevice
        defaultDeviceAddress = deviceAddress
        connected = true

        modbus_set_slave(modbusdevice, Int32(deviceAddress))
        modbus_connect(self.modbusdevice)
    }

    public init(networkAddress: String, port: UInt16, deviceAddress: UInt16, autoReconnectAfter: TimeInterval = 3600.0, disconnectWhenIdleAfter: TimeInterval = 10.0) throws
    {
        guard deviceAddress <= 247 || deviceAddress == 255
        else
        {
            throw ModbusError.couldNotCreateDevice(error: "Invalid Modbus TCP device address: \(deviceAddress)")
        }

        self.autoReconnectAfter = autoReconnectAfter
        self.disconnectWhenIdleAfter = disconnectWhenIdleAfter
        defaultDeviceAddress = deviceAddress

        let service = String(port)
        let device = networkAddress.withCString { node in
            service.withCString { service in
                modbus_new_tcp_pi(node, service)
            }
        }

        guard let device
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotCreateDevice(error: "Could not create TCP device for \(networkAddress):\(port): \(errorString)")
        }

        modbusdevice = device
        let modbusErrorRecoveryMode = modbus_error_recovery_mode(rawValue: MODBUS_ERROR_RECOVERY_LINK.rawValue | MODBUS_ERROR_RECOVERY_PROTOCOL.rawValue)

        modbus_set_error_recovery(modbusdevice, modbusErrorRecoveryMode)
        modbus_set_slave(modbusdevice, Int32(deviceAddress))
    }

    public func connect() async throws
    {
        if modbus_connect(self.modbusdevice) == -1
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotConnect(error: errorString)
        }

        startAutoReconnectTimer()
        startDisconnectWhenIdleTimer()
        connected = true
    }

    public func disconnect()
    {
        guard connected else { return }

        modbus_close(modbusdevice)
        connected = false
        _autoReconnectTask?.cancel()
        _disconnectWhenIdleTask?.cancel()
    }

    private func connectWhenNeeded() async throws
    {
        guard !connected else { return }

        try await connect()
    }

    private func selectDevice(address: UInt16) throws
    {
        guard modbus_set_slave(modbusdevice, Int32(address)) >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotConnect(error: "Could not select Modbus device address \(address): \(errorString)")
        }
    }

    var _autoReconnectTask: Task<Void, Error>?

    private func startAutoReconnectTimer()
    {
        guard autoReconnectAfter > 0 else { return }

        _autoReconnectTask?.cancel()
        _autoReconnectTask = Task
        {
            try await Task.sleep(nanoseconds: UInt64(autoReconnectAfter * Double(NSEC_PER_SEC)))
            self.disconnect()
        }
    }

    var _disconnectWhenIdleTask: Task<Void, Error>?

    private func startDisconnectWhenIdleTimer()
    {
        guard disconnectWhenIdleAfter > 0 else { return }

        _disconnectWhenIdleTask?.cancel()
        _disconnectWhenIdleTask = Task
        {
            try await Task.sleep(nanoseconds: UInt64(disconnectWhenIdleAfter * Double(NSEC_PER_SEC)))
            self.disconnect()
        }
    }

    public func readInputBitsFrom(startAddress: Int, count: Int, type: ModbusRegisterType) async throws -> [Bool]
    {
        try await readInputBitsFrom(startAddress: startAddress, count: count, type: type, deviceAddress: defaultDeviceAddress)
    }

    public func readInputBitsFrom(startAddress: Int, count: Int, type: ModbusRegisterType, deviceAddress: UInt16) async throws -> [Bool]
    {
        switch type
        {
            case .coil: return try await readInputCoilsFrom(startAddress: startAddress, count: count, deviceAddress: deviceAddress)
            case .discrete: return try await readInputBitsFrom(startAddress: startAddress, count: count, deviceAddress: deviceAddress)
            case .holding: throw ModbusError.couldNotRead(error: "read holding for bits not supported")
            case .input: throw ModbusError.couldNotRead(error: "read holding for bits not supported")
        }
    }

    public func readInputCoilsFrom(startAddress: Int, count: Int) async throws -> [Bool]
    {
        try await readInputCoilsFrom(startAddress: startAddress, count: count, deviceAddress: defaultDeviceAddress)
    }

    public func readInputCoilsFrom(startAddress: Int, count: Int, deviceAddress: UInt16) async throws -> [Bool]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        try selectDevice(address: deviceAddress)

        var buffer = [UInt8](repeating: 0, count: count)
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            modbus_read_bits(self.modbusdevice, Int32(startAddress), Int32(count), ptr.baseAddress)
        }

        guard result >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotRead(error: errorString)
        }

        return buffer.map { $0 != 0 }
    }

    public func writeInputCoil(startAddress: Int, value: Bool) async throws
    {
        try await writeInputCoil(startAddress: startAddress, value: value, deviceAddress: defaultDeviceAddress)
    }

    public func writeInputCoil(startAddress: Int, value: Bool, deviceAddress: UInt16) async throws
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        try selectDevice(address: deviceAddress)

        guard modbus_write_bit(self.modbusdevice, Int32(startAddress), value ? 1 : 0) >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotRead(error: errorString)
        }
    }

    public func readInputBitsFrom(startAddress: Int, count: Int) async throws -> [Bool]
    {
        try await readInputBitsFrom(startAddress: startAddress, count: count, deviceAddress: defaultDeviceAddress)
    }

    public func readInputBitsFrom(startAddress: Int, count: Int, deviceAddress: UInt16) async throws -> [Bool]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        try selectDevice(address: deviceAddress)

        var buffer = [UInt8](repeating: 0, count: count)
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            modbus_read_input_bits(self.modbusdevice, Int32(startAddress), Int32(count), ptr.baseAddress)
        }

        guard result >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotRead(error: errorString)
        }

        return buffer.map { $0 != 0 }
    }

    public func readInputRegisters<T: FixedWidthInteger>(from startAddress: Int, count: Int, endianness: ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        return try await readRegisters(from: startAddress, count: count, type: .input, endianness: endianness) as [T]
    }

    public func readInputRegisters<T: FixedWidthInteger>(from startAddress: Int, count: Int, endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws -> [T]
    {
        return try await readRegisters(from: startAddress, count: count, type: .input, endianness: endianness, deviceAddress: deviceAddress) as [T]
    }

    public func readHoldingRegisters<T: FixedWidthInteger>(from startAddress: Int, count: Int, endianness: ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        return try await readRegisters(from: startAddress, count: count, type: .holding, endianness: endianness) as [T]
    }

    public func readHoldingRegisters<T: FixedWidthInteger>(from startAddress: Int, count: Int, endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws -> [T]
    {
        return try await readRegisters(from: startAddress, count: count, type: .holding, endianness: endianness, deviceAddress: deviceAddress) as [T]
    }

    public func readASCIIString(from: Int, count: Int, type: ModbusRegisterType, endianness: ModbusDeviceEndianness = .bigEndian) async throws -> String
    {
        try await readASCIIString(from: from, count: count, type: type, endianness: endianness, deviceAddress: defaultDeviceAddress)
    }

    public func readASCIIString(from: Int, count: Int, type: ModbusRegisterType, endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws -> String
    {
        let values: [UInt8] = try await readRegisters(from: from, count: count, type: type, endianness: endianness, deviceAddress: deviceAddress)

        let validCharacters = values[0 ..< (values.firstIndex(where: { $0 == 0 }) ?? values.count)]
        let string = String(validCharacters.map { Character(UnicodeScalar($0)) })
        return string
    }

    public func writeASCIIString(start: Int, count: Int, string: String, endianness: ModbusDeviceEndianness = .bigEndian) async throws
    {
        try await writeASCIIString(start: start, count: count, string: string, endianness: endianness, deviceAddress: defaultDeviceAddress)
    }

    public func writeASCIIString(start: Int, count: Int, string: String, endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws
    {
        var values = [UInt8](repeating: 0, count: count)
        for (index, character) in string.enumerated()
        {
            values[index] = character.asciiValue ?? 0
        }
        try await writeRegisters(to: start, arrayToWrite: values, endianness: endianness, deviceAddress: deviceAddress)
    }

    private func convertBigEndian(typedPointer: UnsafeMutablePointer<some FixedWidthInteger>, count: Int)
    {
        for i in 0 ..< count
        {
            typedPointer[i] = typedPointer[i].bigEndian
        }
    }

    private func convertBigEndian(rawPointer: UnsafeMutableRawPointer, elementSize: Int, count: Int) throws
    {
        switch elementSize
        {
            case MemoryLayout<UInt8>.size: return
            case MemoryLayout<UInt16>.size: let typedPointer = rawPointer.bindMemory(to: UInt16.self, capacity: count)
                convertBigEndian(typedPointer: typedPointer, count: count)
            case MemoryLayout<UInt32>.size: let typedPointer = rawPointer.bindMemory(to: UInt32.self, capacity: count)
                convertBigEndian(typedPointer: typedPointer, count: count)
            case MemoryLayout<UInt64>.size: let typedPointer = rawPointer.bindMemory(to: UInt64.self, capacity: count)
                convertBigEndian(typedPointer: typedPointer, count: count)
            case MemoryLayout<UInt128>.size: let typedPointer = rawPointer.bindMemory(to: UInt128.self, capacity: count)
                convertBigEndian(typedPointer: typedPointer, count: count)
            default: throw ModbusError.couldNotRead(error: "convertBigEndian: unknown elementSize \(elementSize)")
        }
    }

    public func readRegisters<T: FixedWidthInteger>(from startAddress: Int, count: Int, type: ModbusRegisterType, endianness: ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        try await readRegisters(from: startAddress, count: count, type: type, endianness: endianness, deviceAddress: defaultDeviceAddress)
    }

    public func readRegisters<T: FixedWidthInteger>(from startAddress: Int, count: Int, type: ModbusRegisterType, endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws -> [T]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        try selectDevice(address: deviceAddress)

        let wordCount = ((T.bitWidth * count) + 15) / 16
        let byteCount = wordCount * 2

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8); defer { rawPointer.deallocate() }
        let uint16Pointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
        uint16Pointer.initialize(repeating: 0, count: wordCount)

        let modbusfunction = type == .input ? modbus_read_input_registers : modbus_read_registers

        guard modbusfunction(modbusdevice, Int32(startAddress), Int32(wordCount), uint16Pointer) >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotRead(error: errorString)
        }

        let returnPointer = rawPointer.bindMemory(to: T.self, capacity: count)

        if endianness == .bigEndian
        {
            convertBigEndian(typedPointer: uint16Pointer, count: wordCount)
            convertBigEndian(typedPointer: returnPointer, count: count)
        }

        return Array(UnsafeBufferPointer(start: returnPointer, count: count))
    }

    public func readRegisters<T: FloatingPoint>(from startAddress: Int, count: Int, type: ModbusRegisterType, endianness: ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        try await readRegisters(from: startAddress, count: count, type: type, endianness: endianness, deviceAddress: defaultDeviceAddress)
    }

    public func readRegisters<T: FloatingPoint>(from startAddress: Int, count: Int, type: ModbusRegisterType, endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws -> [T]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        try selectDevice(address: deviceAddress)

        let wordCount = ((MemoryLayout<T>.size * 8 * count) + 15) / 16
        let byteCount = wordCount * 2

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8); defer { rawPointer.deallocate() }
        let uint16Pointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
        uint16Pointer.initialize(repeating: 0, count: wordCount)

        let modbusfunction = type == .input ? modbus_read_input_registers : modbus_read_registers

        guard modbusfunction(modbusdevice, Int32(startAddress), Int32(wordCount), uint16Pointer) >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotRead(error: errorString)
        }

        let returnPointer = rawPointer.bindMemory(to: T.self, capacity: count)

        if endianness == .bigEndian
        {
            convertBigEndian(typedPointer: uint16Pointer, count: wordCount)
            try convertBigEndian(rawPointer: rawPointer, elementSize: MemoryLayout<T>.size, count: count)
        }

        return Array(UnsafeBufferPointer(start: returnPointer, count: count))
    }

    public func writeRegisters<T: FixedWidthInteger>(to startAddress: Int, arrayToWrite: [T], endianness: ModbusDeviceEndianness = .bigEndian) async throws
    {
        try await writeRegisters(to: startAddress, arrayToWrite: arrayToWrite, endianness: endianness, deviceAddress: defaultDeviceAddress)
    }

    public func writeRegisters<T: FixedWidthInteger>(to startAddress: Int, arrayToWrite: [T], endianness: ModbusDeviceEndianness = .bigEndian, deviceAddress: UInt16) async throws
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        try selectDevice(address: deviceAddress)
        guard arrayToWrite.count > 0 else { return }

        let wordCount = ((T.bitWidth * arrayToWrite.count) + 15) / 16
        let byteCount = wordCount * 2

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8); defer { rawPointer.deallocate() }
        let uint16Pointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)

        let cleanLast = UnsafeMutableBufferPointer(start: uint16Pointer, count: wordCount)
        cleanLast[wordCount - 1] = 0x0000
        rawPointer.copyMemory(from: arrayToWrite, byteCount: arrayToWrite.count * MemoryLayout<T>.size)

        if endianness == .bigEndian
        {
            convertBigEndian(typedPointer: rawPointer.bindMemory(to: T.self, capacity: arrayToWrite.count), count: arrayToWrite.count)
            convertBigEndian(typedPointer: uint16Pointer, count: wordCount)
        }

        guard modbus_write_registers(modbusdevice, Int32(startAddress), Int32(wordCount), uint16Pointer) >= 0
        else
        {
            let errorString = String(cString: modbus_strerror(errno))
            throw ModbusError.couldNotWrite(error: errorString)
        }
    }
}
