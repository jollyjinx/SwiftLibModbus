import XCTest
@testable import SwiftLibModbus

final class SwiftLibModbusTests: XCTestCase {
    var device:ModbusDevice!

    override func setUp() async throws {
        print("setup")


        device = try? ModbusDevice(ipAddress: "10.112.16.107", port: 502, device: 3)       // testing with an sma inverter right now. (sunnyboy3)
//        device = try? ModbusDevice(ipAddress: "10.112.16.127", port: 502, device: 3)       // testing with an sma inverter right now (sunnyboy4)
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


    func testReadGridFrequency() async throws
    {
        print("testReadGridFrequency")

        do
        {
            let frequency:[UInt32] = try await device.readRegisters(from: 30803, count: 1)

            print("Frequency:\(frequency[0])")
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
            print("daily yield:\( yield )")
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
            let values:[UInt8] = try await device.readRegisters(from: 40631, count: 12)

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
