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

    init(ipAddress: NSString, port: Int32, device: Int32) throws
    {
        guard let modbusdevice = modbus_new_tcp(ipAddress.cString(using: String.Encoding.ascii.rawValue) , port)
        else
        {
            let errorString = String(cString:modbus_strerror(errno))
            throw ModbusError.couldNotCreateDevice(error:errorString)
        }

        self.modbusdevice = modbusdevice

        let modbusErrorRecoveryMode = modbus_error_recovery_mode(rawValue: MODBUS_ERROR_RECOVERY_LINK.rawValue | MODBUS_ERROR_RECOVERY_PROTOCOL.rawValue)

        modbus_set_error_recovery(modbusdevice, modbusErrorRecoveryMode)
        modbus_set_slave(modbusdevice, device)
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
    func readInputBitsFrom(startAddress: Int32, count: Int32) async throws -> [UInt8]
    {
        return try await withCheckedThrowingContinuation
        {   continuation in

            let returnArray =  UnsafeMutablePointer<UInt8>.allocate(capacity: Int(count))

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

    func readRegistersFrom(startAddress: Int32, count: Int32) async throws -> [UInt16]
    {
        return try await withCheckedThrowingContinuation
        {   continuation in

            let returnArray =  UnsafeMutablePointer<UInt16>.allocate(capacity: Int(count))

            if modbus_read_registers(modbusdevice, startAddress, count, returnArray) >= 0
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

}

