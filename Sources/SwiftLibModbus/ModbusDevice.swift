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

import Foundation.NSDate // for TimeInterval

// https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/12
struct TimedOutError: Error, Equatable {}

///
/// Execute an operation in the current task subject to a timeout.
///
/// - Parameters:
///   - seconds: The duration in seconds `operation` is allowed to run before timing out.
///   - operation: The async operation to perform.
/// - Returns: Returns the result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.

public func withTimeout<R>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> R
) async throws -> R {
    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = Date(timeIntervalSinceNow: seconds)

        // Start actual work.
        group.addTask {
            return try await operation()
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval * Double(NSEC_PER_SEC)))
            }
            try Task.checkCancellation()
            // We’ve reached the timeout.
            throw TimedOutError()
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
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

    func readInputRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int) async throws -> [T]
    {
        return try await withCheckedThrowingContinuation
        {   continuation in

            let wordWidth = (T.bitWidth + 15) / 16
            let wordCount = count * wordWidth
            let byteCount = wordCount * 2
            print("Bytecount:\(byteCount) , wordCount:\(wordCount) wordWidth:\(wordWidth)")
            let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount,alignment: 8)
            defer {
              rawPointer.deallocate()
            }
            let typedPointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
            typedPointer.initialize(repeating: 0, count: count)

            if modbus_read_input_registers(modbusdevice, Int32(startAddress), Int32(wordCount), typedPointer ) >= 0
            {
                let readPointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
                let valueArray = UnsafeMutableBufferPointer<UInt16>(start: readPointer, count: wordCount)

                for i in 0..<valueArray.count {
                    valueArray[i] = valueArray[i].bigEndian
                }

                let returnPointer = rawPointer.bindMemory(to: T.self, capacity: count)
                let returnArray:[T] = Array(UnsafeBufferPointer(start: returnPointer, count: count))
                let correctEndian = returnArray.map { $0.bigEndian }
                continuation.resume(returning: correctEndian )
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotConnect(error:errorString))
            }
        }
    }


    func readRegisters<T:FixedWidthInteger>(from startAddress: Int, count: Int) async throws -> [T]
    {
        return try await withCheckedThrowingContinuation
        {   continuation in

            let wordWidth = (T.bitWidth + 15) / 16
            let wordCount = count * wordWidth
            let byteCount = wordCount * 2
            print("Bytecount:\(byteCount) , wordCount:\(wordCount) wordWidth:\(wordWidth)")
            let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount,alignment: 8)
            defer {
              rawPointer.deallocate()
            }
            let typedPointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
            typedPointer.initialize(repeating: 0, count: count)

            if modbus_read_registers(modbusdevice, Int32(startAddress), Int32(wordCount), typedPointer ) >= 0
            {
                let readPointer = rawPointer.bindMemory(to: UInt16.self, capacity: wordCount)
                let valueArray = UnsafeMutableBufferPointer<UInt16>(start: readPointer, count: wordCount)

                for i in 0..<valueArray.count {
                    valueArray[i] = valueArray[i].bigEndian
                }

                let returnPointer = rawPointer.bindMemory(to: T.self, capacity: count)
                let returnArray:[T] = Array(UnsafeBufferPointer(start: returnPointer, count: count))
                let correctEndian = returnArray.map { $0.bigEndian }
                continuation.resume(returning: correctEndian )
            }
            else
            {
                let errorString = String(cString:modbus_strerror(errno))
                continuation.resume(throwing: ModbusError.couldNotConnect(error:errorString))
            }
        }
    }

    func writeRegisters(startAddress: Int32, count: Int32) async throws -> [UInt16]
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

