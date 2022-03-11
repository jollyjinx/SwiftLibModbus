import XCTest
@testable import SwiftLibModbus

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


final class SwiftLibModbusTests: XCTestCase {
    var device:ModbusDevice!
    var dockerTask:Process?

    deinit
    {
        print("deinit")
    }


    override func setUp() async throws
    {
        print("setup")
        try Process.run( URL(fileURLWithPath: "/usr/local/bin/docker"),arguments: ["stop","modbusserver"])
        sleep(1)

        guard let thisTestBundle = Bundle.allBundles.filter({ $0.bundlePath.hasSuffix(".xctest") }).first   else { print("no xctest bundle found"); return }
        guard let resourceBundlePath = thisTestBundle.path(forResource:nil , ofType: "bundle")              else { print("no resourceBundlePath found"); return }
        guard let resourceBundle = Bundle.init(path: resourceBundlePath)                                    else { print("no resourceBundle could be created"); return }
        guard let serverConfigPath = resourceBundle.path(forResource: "server_config", ofType: "json")      else { print("no server config file found \(resourceBundle)"); return }

        try Process.run( URL(fileURLWithPath: "/usr/local/bin/docker"),
                         arguments:["run","--rm","--init","--name","modbusserver","--platform","linux/amd64","-p","5020:5020","-v",serverConfigPath+":/server_config.json","oitc/modbus-server:latest","-f/server_config.json"])
        sleep(1)


//        device = try ModbusDevice(networkAddress: "10.112.16.107", port: 502, deviceAddress: 3)       // testing with an SMA inverter right now. (sunnyboy3)
//        device = try ModbusDevice(networkAddress: "10.98.16.156", port: 502, deviceAddress: 180)       // testing with an Phoenix Charger
        device = try ModbusDevice(networkAddress: "127.0.0.1", port: 5020, deviceAddress: 180)       // testing with an Phoenix Charger
//        device = try ModbusDevice(networkAddress: "10.112.16.127", port: 502, deviceAddress: 3)       // testing with an SMA inverter right now (sunnyboy4)
//            device = try ModbusDevice(networkAddress: "evcharger.jinx.eu", port: 502, deviceAddress: 180)       // testing with an Phoenix Charger
            try await device.connect()
            print("Connected")
    }

    override func tearDown() async throws {
        print("tearDown")
        await device?.disconnect()
        dockerTask?.interrupt()
        dockerTask?.terminate()
        dockerTask?.waitUntilExit()
        try Process.run( URL(fileURLWithPath: "/usr/local/bin/docker"),arguments: ["stop","modbusserver"])
        sleep(1)
    }

    func testReadGridFrequency() async throws
    {
        print("testReadGridFrequency")

        do
        {
            let values:[UInt32] = try await device.readHoldingRegisters(from: 30803, count: 1)
            let frequency =  Decimal(values[0]) / 100
            print("Frequency:\(frequency) Hz")
            XCTAssert( frequency == 50.01 )
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }

    func testReadDailyYield() async throws
    {
        print("daily yield")

        do
        {
            let values8:[UInt8]     = try await device.readHoldingRegisters(from: 30516, count: 8)
            let values16:[UInt16]   = try await device.readHoldingRegisters(from: 30516, count: 4)
            let values32:[UInt32]   = try await device.readHoldingRegisters(from: 30516, count: 2)
            let values64:[UInt64]   = try await device.readHoldingRegisters(from: 30516, count: 1)

            print("values8:\(values8.map({ String(format: "0x%02x", $0) }).joined(separator: ","))")
            print("values16:\(values16.map({ String(format: "0x%04x", $0) }).joined(separator: ","))")
            print("values32:\(values32.map({ String(format: "0x%08x", $0) }).joined(separator: ","))")
            print("values64:\(values64.map({ String(format: "0x%016x", $0) }).joined(separator: ","))")
            let yield =  Decimal(values64[0]) / 1000
            print("daily yield:\( yield ) kWh")
            XCTAssert( yield == Decimal(37181234)/1000 )
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }

    func testReadWriteInts() async throws
    {
        print("testReadWriteInts()")

        do
        {
            for value:UInt8 in 0...255
            {
                try await device.writeRegisters(to: 30516, arrayToWrite: [value])
                let read:[UInt8] = try await device.readHoldingRegisters(from: 30516, count: 1)
                print("Testing :\(value) == \(read.first!)")
                XCTAssert(read.first! == value)
            }
            for value:UInt16 in [0x0000,0x0001,0x00F,0x0010,0x0011,0x00FF,0x0100,0x0101,0x0f00,0x0f01,0xf0ff,0xff00,0xfffe,0xffff]
            {
                try await device.writeRegisters(to: 30516, arrayToWrite: [value])
                let read:[UInt16] = try await device.readHoldingRegisters(from: 30516, count: 1)
                print("Testing :\(value) == \(read.first!)")
                XCTAssert(read.first! == value)
            }
            for value:UInt32 in [0x0000,0x0001,0x00F,0x0010,0x0011,0x00FF,0x0100,0x0101,0x0f00,0x0f01,0xf0ff,0xff00,0xfffe,0xffff,
                                 0x0001_0000,0x0001_0001,0x00F,0x0001_0010,0x0001_0011,0x0001_00FF,0x0001_0100,0x0001_0101,0x0001_0f00,0x0001_0f01,0x0001_f0ff,0xff00,0x0001_fffe,0xffff
                                ]
            {
                try await device.writeRegisters(to: 30516, arrayToWrite: [value])
                let read:[UInt32] = try await device.readHoldingRegisters(from: 30516, count: 1)
                print("Testing :\(value) == \(read.first!)")
                XCTAssert(read.first! == value)
            }
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }


    func testReadName() async throws
    {
        print("testReadName()")

        do
        {
            let string = try await readString(from: 1310, count: 10)
            XCTAssert(string == "charger")
        }
        catch
        {
            XCTFail("Error \(error)")
        }
    }

    func readString(from:Int,count:Int) async throws -> String
    {
        let values:[UInt8] = try await withTimeout(seconds: 0.11, operation: { let v:[UInt8] = try await self.device.readHoldingRegisters(from: from, count: count) ; return v }    )

        let validCharacters = values[0..<(values.firstIndex(where: { $0 == 0 }) ?? values.count)]
        let string = String(validCharacters.map{ Character(UnicodeScalar($0)) })
        return string
    }
    func writeString(start:Int,string:String) async throws
    {
        var name = string.map { $0.asciiValue ?? 0 }
        name.append(0)
        assert(name.count <= 10)
        try await self.device.writeRegisters(to: start, arrayToWrite:name)
    }

    func testWriteName() async throws
    {
        print("testWriteName()")

        do
        {
            for stringToWrite in ["evchar","EvChar"]
            {
                try await writeString(start:310,string:stringToWrite)
                let readSting = try await readString(from: 310, count: 10)

                XCTAssert(readSting == stringToWrite )
            }

        }
        catch
        {
            XCTFail("Error \(error)")
        }
    }

    func testReadBitfield() async throws
    {
        print("testReadBitfield()")

        struct PhoenixErrorCodes: OptionSet {

            enum ErrorCodes:String,CaseIterable
            {
                case cableReject13and20A
                case cableReject13A
                case invalidPPValue
                case invalidCPValue
                case statusF
                case lockError
                case unlockError
                case lossLDduringLock
                case powerOverload
            }

            let rawValue: UInt16
            static let cableReject13and20A  = PhoenixErrorCodes(rawValue: 1 << 0)
            static let cableReject13A       = PhoenixErrorCodes(rawValue: 1 << 1)
            static let invalidPPValue       = PhoenixErrorCodes(rawValue: 1 << 2)
            static let invalidCPValue       = PhoenixErrorCodes(rawValue: 1 << 3)
            static let statusF              = PhoenixErrorCodes(rawValue: 1 << 4)
            static let lockError            = PhoenixErrorCodes(rawValue: 1 << 5)
            static let unlockError          = PhoenixErrorCodes(rawValue: 1 << 6)
            static let lossLDduringLock     = PhoenixErrorCodes(rawValue: 1 << 7)
            static let powerOverload        = PhoenixErrorCodes(rawValue: 1 << 8)

            var description:String {
                var options:[String] = []

                var value = 1
                for errorCode in ErrorCodes.allCases
                {
                    if self.rawValue & UInt16(value) != 0
                    {
                        options.append( errorCode.rawValue )
                    }
                    value <<= 1
                }
                return options.joined(separator: ",")
            }
        }

        do
        {
            let values:[UInt16] = try await withTimeout(seconds: 2.0, operation: { let v:[UInt16] = try await self.device.readInputRegisters(from: 108, count: 1) ; return v }    )

            let errorCodes = PhoenixErrorCodes(rawValue: values.first!)

            print("errorCodes:\( errorCodes.description )")

            XCTAssert(errorCodes.rawValue == 0x01FF)
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }



}
