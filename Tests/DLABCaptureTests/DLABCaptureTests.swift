import XCTest
@testable import DLABCapture

final class DLABCaptureTests: XCTestCase {
    func testCaptureManager() throws {
        XCTAssertNotNil(CaptureManager())
    }
    
    func testVideoStyle() throws {
        let vStyle :VideoStyle = .SD_720_480_16_9
        XCTAssertTrue(vStyle.encodedSize() == NSSize(width: 720, height: 480))
        XCTAssertTrue(vStyle.aspectRatio() == NSSize(width: 40, height: 33))
        XCTAssertTrue(vStyle.visibleSize() == NSSize(width: 704, height: 480))
        // SD:NTSC-DV-Wide
        //   Clean aperture: 16 pixel horizontal, 0 pixel vertical
        //   Horizontal offset range: -7,+8, Vertical offset range: 0,0
        //   resulted (4:3) = 640:480 (pixel aspect ratio=10:11)
        //   resulted (16:9) = 853.333:480 (pixel aspect ratio=40:33)
    }
    
    func testDeviceList() throws {
        let manager = CaptureManager()
        XCTAssertNotNil(manager.deviceList())
    }
    
    func testFindFirstDevice() throws {
        let manager = CaptureManager()
        XCTAssertNotNil(manager.findFirstDevice())
    }
}
