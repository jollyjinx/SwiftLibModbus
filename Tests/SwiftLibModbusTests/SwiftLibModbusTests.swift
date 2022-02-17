import XCTest
@testable import SwiftLibModbus

final class SwiftLibModbusTests: XCTestCase {
    var device:SwiftLibModbus!

    override func setUp() async throws {
        print("setup")
        device = SwiftLibModbus(ipAddress: "10.112.16.107", port: 502, device: 3)       // testing with an sma inverter right now.
        XCTAssertNotNil(device)
        do
        {   try await device.connect()
            print("Connected")
            device.disconnect()
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }


    func testReadGridFrequency() async throws {
        print("testReadGridFrequency")

        do
        {
            let frequency = try await device.readRegistersFrom(startAddress: 30803, count: 2)

            print("Frequency:\(frequency)")
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }


}
