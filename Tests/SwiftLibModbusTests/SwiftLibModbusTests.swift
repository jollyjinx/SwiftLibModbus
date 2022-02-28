import XCTest
@testable import SwiftLibModbus

final class SwiftLibModbusTests: XCTestCase {
    var device:ModbusDevice!

    override func setUp() async throws {
        print("setup")

        device = try? ModbusDevice(ipAddress: "10.112.16.107", port: 502, device: 3)       // testing with an SMA inverter right now. (sunnyboy3)
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

    func testReadGridFrequency() async throws
    {
        print("testReadGridFrequency")

        do
        {
            let values:[UInt32] = try await device.readRegisters(from: 30803, count: 1)
            let frequency =  Decimal(values[0]) / 100
            print("Frequency:\(frequency) Hz")
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }

    func testReadGridFrequency2() async throws
    {
        print("daily yield")

        do
        {
            let values:[UInt64] = try await device.readRegisters(from: 30517, count: 1)
            let yield =  Decimal(values[0]) / 1000
            print("daily yield:\( yield ) kWh")
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }


    func testReadName() async throws
    {
        print("Name")

        do
        {
            let values:[UInt8] = try await withTimeout(seconds: 0.11, operation: { let v:[UInt8] = try await self.device.readRegisters(from: 40631, count: 12) ; return v }    )

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


}
