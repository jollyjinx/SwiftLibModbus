import XCTest
@testable import SwiftLibModbus

final class SwiftLibModbusTests: XCTestCase {
    func testConnectSunnyboy3() async throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        print("Test started")
        let a = SwiftLibModbus(ipAddress: "10.112.16.107", port: 502, device: 3)
        XCTAssertNotNil(a)
        
        do
        {   try await a.connect()
            print("Connected")
            a.disconnect()
        }
        catch
        {
            print("Error \(error)")
            XCTFail()
        }
    }
}
