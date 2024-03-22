//
//  ModbusDevice.swift
//  
//
//  Created by Patrick Stein on 25.02.22.
//

import Foundation
import CModbus

#if !NSEC_PER_SEC
let NSEC_PER_SEC = 1_000_000_000
#endif


public enum ModbusError: Error {
    case couldNotCreateDevice(error:String)
    case couldNotConnect(error:String)
    case couldNotRead(error:String)
    case couldNotWrite(error:String)
}

public enum ModbusRegisterType:String,Encodable,Decodable,Sendable
{
    case coil
    case discrete
    case holding
    case input
}
public enum ModbusDeviceEndianness:String,Encodable,Decodable,Sendable
{
    case bigEndian
    case littleEndian
}

public enum ModbusParity : Sendable
{
    case none
    case even
    case odd

    var value:UInt8 {   switch(self)
                        {
                            case .none: return Character("N").asciiValue!
                            case .even: return Character("E").asciiValue!
                            case .odd: return Character("O").asciiValue!
                        }
                    }
}


public actor ModbusDevice
{
    let modbusdevice: OpaquePointer
    let autoReconnectAfter:TimeInterval         // SMA servers tend to hang when a connection is too long
    let disconnectWhenIdleAfter:TimeInterval    // SMA servers have a problem when tcp connection is not used and keep it internally forever

    var connected = false

    public init(device:String,slaveid:Int = 1, baudRate:Int = 9600,dataBits:Int = 8, parity:ModbusParity = .none , stopBits:Int = 1,autoReconnectAfter:TimeInterval = 10.0 ,disconnectWhenIdleAfter:TimeInterval = 10.0) throws
    {
        guard let modbusdevice = modbus_new_rtu(device.cString(using: .utf8), Int32(baudRate), CChar(parity.value), Int32(dataBits), Int32(stopBits))
        else
        {
            throw ModbusError.couldNotCreateDevice(error:"Could not create device:\(device) (\(baudRate)-\(parity)-\(stopBits))")
        }
        self.autoReconnectAfter      = autoReconnectAfter
        self.disconnectWhenIdleAfter = disconnectWhenIdleAfter
        self.modbusdevice = modbusdevice
        self.connected = true

        modbus_set_slave(modbusdevice, Int32(slaveid))
        modbus_connect(self.modbusdevice)
    }


    public init(networkAddress: String, port: UInt16, deviceAddress: UInt16,autoReconnectAfter:TimeInterval = 3600.0,disconnectWhenIdleAfter:TimeInterval = 10.0) throws
    {
        self.autoReconnectAfter      = autoReconnectAfter
        self.disconnectWhenIdleAfter = disconnectWhenIdleAfter

        let host = Host.init(name: networkAddress)
        let ipAddresses = host.addresses

        guard ipAddresses.count > 0
        else
        {
            throw ModbusError.couldNotCreateDevice(error:"No Addresses for Name:\(networkAddress) found.")
        }

        for ipAddress in ipAddresses
        {
            if let device = modbus_new_tcp(ipAddress.cString(using: String.Encoding.ascii) , Int32(port) )
            {
                self.modbusdevice = device
                let modbusErrorRecoveryMode = modbus_error_recovery_mode(rawValue: MODBUS_ERROR_RECOVERY_LINK.rawValue | MODBUS_ERROR_RECOVERY_PROTOCOL.rawValue)

                modbus_set_error_recovery(modbusdevice, modbusErrorRecoveryMode)
                modbus_set_slave(modbusdevice, Int32(deviceAddress) )
                return
            }
        }

        let errorString = String(cString:modbus_strerror(errno))
        throw ModbusError.couldNotCreateDevice(error:"could not create device:\(errorString) ipAddresses:\(ipAddresses)")
    }


    public func connect() async throws
    {
        return try await withCheckedThrowingContinuation
        {
            continuation in

            if -1 == modbus_connect(self.modbusdevice)
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotConnect(error:errorString))
            }
            else
            {
                startAutoReconnectTimer()
                startDisconnectWhenIdleTimer()
                connected = true
                continuation.resume()
            }
        }
    }

    public func disconnect() {
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


    var _autoReconnectTask:Task<(),Error>?

    private func startAutoReconnectTimer()
    {
        guard autoReconnectAfter > 0 else { return }

        _autoReconnectTask?.cancel()
        _autoReconnectTask = Task {
                                        try await Task.sleep(nanoseconds: UInt64( autoReconnectAfter * Double(NSEC_PER_SEC) ))
                                        self.disconnect()
                                    }
    }

    var _disconnectWhenIdleTask:Task<(),Error>?

    private func startDisconnectWhenIdleTimer()
    {
        guard disconnectWhenIdleAfter > 0 else { return }

        _disconnectWhenIdleTask?.cancel()
        _disconnectWhenIdleTask = Task {
                                        try await Task.sleep(nanoseconds: UInt64( disconnectWhenIdleAfter * Double(NSEC_PER_SEC) ))
                                        self.disconnect()
                                    }
    }




    public func readInputBitsFrom(startAddress: Int,count: Int,type:ModbusRegisterType) async throws -> [Bool]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }

        switch type
        {
            case .coil:      return try await readInputCoilsFrom(startAddress:startAddress,count: count)
            case .discrete:  return try await readInputBitsFrom(startAddress: startAddress, count: count)
            case .holding:   throw ModbusError.couldNotRead(error: "read holding for bits not supported")
            case .input:     throw ModbusError.couldNotRead(error: "read holding for bits not supported")
        }
    }


    public func readInputCoilsFrom(startAddress: Int, count: Int) async throws -> [Bool]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }

        return try await withCheckedThrowingContinuation
        {   continuation in

            let returnArray =  UnsafeMutablePointer<Bool>.allocate(capacity: Int(count))

            if modbus_read_bits(self.modbusdevice, Int32(startAddress), Int32(count), returnArray) >= 0
            {
                let boolArray = Array(UnsafeBufferPointer(start: returnArray, count: Int(count)))

                continuation.resume(returning: boolArray)
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotRead(error:errorString))
            }
        }
    }

    public func writeInputCoil(startAddress: Int, value:Bool) async throws
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }

        return try await withCheckedThrowingContinuation
        {   continuation in

            if modbus_write_bit(self.modbusdevice, Int32(startAddress), value ? 1 : 0 ) >= 0
            {
                continuation.resume()
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotRead(error:errorString))
            }
        }
    }


    public func readInputBitsFrom(startAddress: Int, count: Int) async throws -> [Bool]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }

        return try await withCheckedThrowingContinuation
        {   continuation in

            let returnArray =  UnsafeMutablePointer<Bool>.allocate(capacity: Int(count))

            if modbus_read_input_bits(self.modbusdevice, Int32(startAddress), Int32(count), returnArray) >= 0
            {
                let boolArray = Array(UnsafeBufferPointer(start: returnArray, count: Int(count)))

                continuation.resume(returning: boolArray)
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotRead(error:errorString))
            }
        }
    }


    public func readInputRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int,endianness:ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        return try await readRegisters(from:startAddress, count: count, type: .input,endianness:endianness) as [T]
    }

    public func readHoldingRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int,endianness:ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        return try await readRegisters(from:startAddress, count: count, type: .holding,endianness:endianness) as [T]
    }

    public func readASCIIString(from:Int,count:Int,type:ModbusRegisterType,endianness:ModbusDeviceEndianness = .bigEndian) async throws -> String
    {
        let values:[UInt8] = try await readRegisters(from: from, count: count,type: type,endianness:endianness)

        let validCharacters = values[0..<(values.firstIndex(where: { $0 == 0 }) ?? values.count)]
        let string = String(validCharacters.map{ Character(UnicodeScalar($0)) })
        return string
    }

    public func writeASCIIString(start:Int,count:Int,string:String,endianness:ModbusDeviceEndianness = .bigEndian) async throws
    {
        var values  = [UInt8](repeating: 0, count: count)
        for (index,character) in string.enumerated()
        {
            values[index] = character.asciiValue ?? 0
        }
        try await writeRegisters(to: start, arrayToWrite:values,endianness:endianness)
    }





    private func convertBigEndian<T:FixedWidthInteger>(typedPointer:UnsafeMutablePointer<T>,count:Int)
    {
        for i in 0..<count {
            typedPointer[i] = typedPointer[i].bigEndian
        }
    }


    public func readRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int,type: ModbusRegisterType,endianness:ModbusDeviceEndianness = .bigEndian) async throws -> [T]
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }

        return try await withCheckedThrowingContinuation
        {   continuation in

            let wordCount       = ((T.bitWidth * count) + 15 ) / 16
            let byteCount       = wordCount * 2
            let rawPointer      = UnsafeMutableRawPointer.allocate(byteCount: byteCount,alignment:8); defer { rawPointer.deallocate() }
            let uint16Pointer   = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
                uint16Pointer.initialize(repeating: 0, count: wordCount)

            let modbusfunction = type == .input ? modbus_read_input_registers : modbus_read_registers

            if modbusfunction(modbusdevice, Int32(startAddress), Int32(wordCount), uint16Pointer ) >= 0
            {
                let returnPointer = rawPointer.bindMemory(to: T.self, capacity: count)

                if endianness == .bigEndian
                {
                    convertBigEndian(typedPointer:uint16Pointer, count:wordCount)
                    convertBigEndian(typedPointer:returnPointer, count:count)
                }

                let returnArray:[T] = Array(UnsafeBufferPointer(start: returnPointer, count: count))

                continuation.resume(returning: returnArray )
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotRead(error:errorString))
            }
        }
    }



    public func writeRegisters<T:FixedWidthInteger>(to startAddress: Int, arrayToWrite : [T],endianness:ModbusDeviceEndianness = .bigEndian) async throws
    {
        try await connectWhenNeeded(); defer { startDisconnectWhenIdleTimer() }
        guard arrayToWrite.count > 0 else { return }

        return try await withCheckedThrowingContinuation
        {   continuation in

            let wordCount       = ((T.bitWidth * arrayToWrite.count) + 15 ) / 16
            let byteCount       = wordCount * 2

            let rawPointer      = UnsafeMutableRawPointer.allocate(byteCount: byteCount,alignment:8); defer { rawPointer.deallocate() }
            let uint16Pointer   = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)

            let cleanLast       = UnsafeMutableBufferPointer(start: uint16Pointer, count: wordCount)
            cleanLast[wordCount - 1] = 0x0000
            rawPointer.copyMemory(from: arrayToWrite, byteCount: arrayToWrite.count * MemoryLayout<T>.size)

            if endianness == .bigEndian
            {
                convertBigEndian(typedPointer:rawPointer.bindMemory(to: T.self, capacity: arrayToWrite.count), count:arrayToWrite.count)
                convertBigEndian(typedPointer:uint16Pointer, count:wordCount)
            }

            if modbus_write_registers(modbusdevice, Int32(startAddress), Int32(wordCount), uint16Pointer) >= 0
            {
                continuation.resume()
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotWrite(error:errorString))
            }
        }
    }

}

