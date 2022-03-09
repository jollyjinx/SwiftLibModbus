import XCTest
@testable import SwiftLibModbus

final class SwiftLibModbusTests: XCTestCase {
    var device:ModbusDevice!

    override func setUp() async throws {
        print("setup")

//        device = try? ModbusDevice(ipAddress: "10.112.16.107", port: 502, device: 3)       // testing with an SMA inverter right now. (sunnyboy3)
        device = try? ModbusDevice(ipAddress: "10.98.16.156", port: 502, device: 180)       // testing with an Phoenix Charger
//        device = try? ModbusDevice(ipAddress: "10.112.16.127", port: 502, device: 3)       // testing with an SMA inverter right now (sunnyboy4)
        XCTAssertNotNil(device)
        do
        {   try await device.connect()
            print("Connected")
            await device.disconnect()
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }

    override func tearDown() async throws {
        print("tearDown")

        XCTAssertNotNil(device)
        await device.disconnect()
    }

//    func testReadGridFrequency() async throws
//    {
//        print("testReadGridFrequency")
//
//        do
//        {
//            let values:[UInt32] = try await device.readRegisters(from: 30803, count: 1)
//            let frequency =  Decimal(values[0]) / 100
//            print("Frequency:\(frequency) Hz")
//        }
//        catch
//        {
//            print("Error \(error)")
//            XCTFail()
//        }
//    }
//
//    func testReadGridFrequency2() async throws
//    {
//        print("daily yield")
//
//        do
//        {
//            let values:[UInt64] = try await device.readRegisters(from: 30517, count: 1)
//            let yield =  Decimal(values[0]) / 1000
//            print("daily yield:\( yield ) kWh")
//        }
//        catch
//        {
//            print("Error \(error)")
//            XCTFail()
//        }
//    }
//
//
//    func testReadName() async throws
//    {
//        print("testReadName")
//
//        do
//        {
//            let values:[UInt8] = try await withTimeout(seconds: 0.11, operation: { let v:[UInt8] = try await self.device.readRegisters(from: 40631, count: 12) ; return v }    )
//
//            let validCharacters = values[0..<(values.firstIndex(where: { $0 == 0 }) ?? values.count)]
//            let string = String(validCharacters.map{ Character(UnicodeScalar($0)) })
//
//            print("Name:\( string )")
//        }
//        catch
//        {
//            print("Error \(error)")
//            XCTFail()
//        }
//    }

    func testReadName() async throws
    {
        print("testReadName")

        do
        {
            let values:[UInt8] = try await withTimeout(seconds: 0.11, operation: { let v:[UInt8] = try await self.device.readRegisters(from: 310, count: 10) ; return v }    )

            let validCharacters = values[0..<(values.firstIndex(where: { $0 == 0 }) ?? values.count)]
            let string = String(validCharacters.map{ Character(UnicodeScalar($0)) })

            print("Name:\( string )")
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }

    func testReadBitfield() async throws
    {
        print("testReadBitfield")

        struct PhoenixErrorCodes: OptionSet {
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
        }

        do
        {
            let values:[UInt16] = try await withTimeout(seconds: 2.0, operation: { let v:[UInt16] = try await self.device.readInputRegisters(from: 107, count: 1) ; return v }    )

            let errorCodes = PhoenixErrorCodes(rawValue: values.first!)

            print("errorCodes:\( errorCodes )")
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }



}
