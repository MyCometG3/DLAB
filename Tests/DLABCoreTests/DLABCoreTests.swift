import XCTest
@testable import DLABCore

final class DLABCoreTests: XCTestCase {
    func testDLABBrowser() throws {
        XCTAssertNotNil(DLABBrowser())
    }
    
    func testDLABBrowser2() throws {
        let browser = DLABBrowser()
        let count = browser.registerDevices()
        XCTAssertGreaterThan(count, 0)
        XCTAssertNotNil(browser.allDevices)
    }
    
    func testDLABDevice() throws {
        let browser = DLABBrowser()
        _ = browser.registerDevices()
        if let allDevices = browser.allDevices {
            XCTAssertNotNil(allDevices.first)
            if let device = allDevices.first {
                XCTAssertNotNil(device.modelName)
                XCTAssertNotNil(device.displayName)
            }
        }
    }
}
