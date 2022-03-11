//
//  ModbusDevice.swift
//  
//
//  Created by Patrick Stein on 25.02.22.
//

import Foundation
import CModbus

enum ModbusError: Error {
    case couldNotCreateDevice(error:String)
    case couldNotConnect(error:String)
}
actor ModbusDevice
{
    let modbusdevice: OpaquePointer

    init(networkAddress: String, port: Int32, deviceAddress: Int32) throws
    {
        let host = Host.init(name: networkAddress)
        let ipAddresses = host.addresses

        guard ipAddresses.count > 0
        else
        {
            throw ModbusError.couldNotCreateDevice(error:"No Addresses for Name\(networkAddress) found")
        }

        for ipAddress in ipAddresses
        {
            if let device = modbus_new_tcp(ipAddress.cString(using: String.Encoding.ascii) , port)
            {
                self.modbusdevice = device
                let modbusErrorRecoveryMode = modbus_error_recovery_mode(rawValue: MODBUS_ERROR_RECOVERY_LINK.rawValue | MODBUS_ERROR_RECOVERY_PROTOCOL.rawValue)

                modbus_set_error_recovery(modbusdevice, modbusErrorRecoveryMode)
                modbus_set_slave(modbusdevice, deviceAddress)
                return
            }
        }

        let errorString = String(cString:modbus_strerror(errno))
        throw ModbusError.couldNotCreateDevice(error:errorString)
    }


    func connect() async throws
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
                continuation.resume()
            }
        }
    }
    func disconnect() {
        modbus_close(modbusdevice)
    }


    func readInputBitsFrom(startAddress: Int32, count: Int32) async throws -> [Bool]
    {
        return try await withCheckedThrowingContinuation
        {   continuation in

            let returnArray =  UnsafeMutablePointer<Bool>.allocate(capacity: Int(count))

            if modbus_read_input_bits(self.modbusdevice, startAddress, count, returnArray) >= 0
            {
                let intArray = Array(UnsafeBufferPointer(start: returnArray, count: Int(count)))

                continuation.resume(returning: intArray)
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotConnect(error:errorString))
            }
        }
    }

    private enum ModbusRegisterType
    {
        case holding
        case input
    }

    func readInputRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int) async throws -> [T]
    {
        return try await readRegisters(from:startAddress, count: count, type: .input) as [T]
    }

    func readHoldingRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int) async throws -> [T]
    {
        return try await readRegisters(from:startAddress, count: count, type: .holding) as [T]
    }


    private func convertBigEndian<T:FixedWidthInteger>(typedPointer:UnsafeMutablePointer<T>,count:Int)
    {
        for i in 0..<count {
            typedPointer[i] = typedPointer[i].bigEndian
        }
    }


    private func readRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int,type: ModbusRegisterType) async throws -> [T]
    {
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

                if T.bitWidth != 16
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
                continuation.resume(throwing: ModbusError.couldNotConnect(error:errorString))
            }
        }
    }



    func writeRegisters<T:FixedWidthInteger>(to startAddress: Int, arrayToWrite : [T]) async throws
    {
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

            if T.bitWidth != 16
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
                continuation.resume(throwing: ModbusError.couldNotConnect(error:errorString))
            }
        }
    }

//    func writeRegistersFromAndOn(address: Int32, numberArray: NSArray, success: @escaping () -> Void, failure: @escaping (NSError) -> Void) {
//        modbusQueue.async {
//            let valueArray: UnsafeMutablePointer<UInt16> = UnsafeMutablePointer<UInt16>.allocate(capacity: numberArray.count)
//            for i in 0..<numberArray.count {
//                valueArray[i] = UInt16(numberArray[i] as! Int)
//            }
//
//            if modbus_write_registers(self.mb!, address, Int32(numberArray.count), valueArray) >= 0 {
//                DispatchQueue.main.async {
//                    success()
//                }
//            } else {
//                let error = self.buildNSError(errno: errno)
//                DispatchQueue.main.async {
//                    failure(error)
//                }
//            }
//        }
//    }
//
//    func writeRegister(address: Int32, value: Int32, success: @escaping () -> Void, failure: @escaping (NSError) -> Void) {
//        modbusQueue.async {
//            if modbus_write_register(self.mb!, address, value) >= 0 {
//                DispatchQueue.main.async {
//                    success()
//                }
//            } else {
//                let error = self.buildNSError(errno: errno)
//                DispatchQueue.main.async {
//                    failure(error)
//                }
//            }
//        }
//    }

}

