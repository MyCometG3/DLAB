import XCTest
import CoreMedia
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

    func testCaptureManagerNativeTimingForNTSC2398() throws {
        let manager = CaptureManager()

        let timescale = try XCTUnwrap(manager.nativeTimescaleFor(.modeNTSC2398))
        XCTAssertEqual(timescale, 24000)
        let fps = try XCTUnwrap(manager.nativeFPSFor(.modeNTSC2398))
        XCTAssertEqual(fps, Float(24.0 / 1.001), accuracy: 0.0001)
    }

    func testCaptureTimecodeHelperAllowsLargeFrameNumbersForTimeCode64() throws {
        let helper = CaptureTimecodeHelper(formatType: kCMTimeCodeFormatType_TimeCode64)
        var smpteTime = CVSMPTETime()
        smpteTime.type = 0
        smpteTime.hours = 24_856

        let dataBuffer = try XCTUnwrap(
            helper.testingPrepareTimeCodeDataBuffer(
                smpteTime,
                sizes: MemoryLayout<Int64>.size,
                quanta: 24,
                tcType: 0
            )
        )

        var encodedFrameNumberBE: Int64 = 0
        let status = CMBlockBufferCopyDataBytes(
            dataBuffer,
            atOffset: 0,
            dataLength: MemoryLayout<Int64>.size,
            destination: &encodedFrameNumberBE
        )

        XCTAssertEqual(status, kCMBlockBufferNoErr)
        XCTAssertEqual(Int64(bigEndian: encodedFrameNumberBE), 2_147_558_400)
    }

    func testCaptureTimecodeHelperRejectsLargeFrameNumbersForTimeCode32() throws {
        let helper = CaptureTimecodeHelper(formatType: kCMTimeCodeFormatType_TimeCode32)
        var smpteTime = CVSMPTETime()
        smpteTime.type = 0
        smpteTime.hours = 24_856

        let dataBuffer = helper.testingPrepareTimeCodeDataBuffer(
            smpteTime,
            sizes: MemoryLayout<Int32>.size,
            quanta: 24,
            tcType: 0
        )

        XCTAssertNil(dataBuffer)
    }

    func testCaptureManagerPrewarmRequiresRunningCapture() async throws {
        let manager = CaptureManager()

        XCTAssertFalse(manager.recording)
        XCTAssertEqual(manager.duration, 0)

        let result = await manager.prewarmRecordingPathAsync()

        XCTAssertFalse(result)
        XCTAssertFalse(manager.recording)
        XCTAssertEqual(manager.duration, 0)
    }

    func testCaptureManagerTestingWriterConfigReflectsRecordingOptions() throws {
        let manager = CaptureManager()
        let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("capture-manager-config.mov")
        let handler: @Sendable (CaptureWriterDiagnostic) -> Void = { _ in }

        manager.prefix = "Test-"
        manager.sampleTimescale = 0
        manager.encodeAudio = true
        manager.encodeAudioBitrate = 192_000
        manager.encodeVideo = false
        manager.encodeVideoBitrate = 4_000_000
        manager.encodeProRes422 = false
        manager.videoStyle = .SD_720_480_16_9
        manager.offset = NSPoint(x: 4, y: -2)
        manager.captureWriterDiagnosticHandler = handler

        let config = manager.testingWriterConfig(movieURL: movieURL, prefix: manager.prefix)

        XCTAssertEqual(config.movieURL, movieURL)
        XCTAssertEqual(config.prefix, "Test-")
        XCTAssertGreaterThan(config.sampleTimescale, 0)
        XCTAssertTrue(config.encodeAudio)
        XCTAssertEqual(config.encodeAudioBitrate, 192_000)
        XCTAssertFalse(config.encodeVideo)
        XCTAssertEqual(config.encodeVideoBitrate, 4_000_000)
        XCTAssertFalse(config.encodeProRes422)
        XCTAssertEqual(config.videoStyle.encodedSize(), NSSize(width: 720, height: 480))
        XCTAssertEqual(config.clapHOffset, 4)
        XCTAssertEqual(config.clapVOffset, -2)
        XCTAssertFalse(config.useTimecode)
        XCTAssertNotNil(config.diagnosticHandler)
        XCTAssertNil(config.sourceVideoFormatDescription)
        XCTAssertNil(config.sourceAudioFormatDescription)
    }

    func testCaptureWriterOpenSessionReportsInitializationError() async throws {
        let writer = CaptureWriter()
        var config = CaptureWriter.CaptureWriterConfig()
        config.useAudio = false
        config.useVideo = false
        config.useTimecode = false
        config.movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("capture-writer-error.mov")

        await writer.setConfig(config)
        await writer.testingSetAssetWriterFactory { _, _ in
            throw NSError(domain: "DLABCaptureTests", code: 42, userInfo: [
                NSLocalizedDescriptionKey: "Injected writer init failure"
            ])
        }
        await writer.openSession()

        let isRecording = await writer.isRecording
        XCTAssertFalse(isRecording)

        guard let internalError = await writer.internalError else {
            return XCTFail("Expected openSession() to store an initialization error")
        }
        guard case let CaptureWriterError.assetWriterIsNotAvailable(reason) = internalError else {
            return XCTFail("Expected assetWriterIsNotAvailable error, got \(internalError)")
        }
        XCTAssertTrue(reason.contains("AVAssetWriter initialization failed"))
        XCTAssertTrue(reason.contains("Injected writer init failure"))
    }

    func testCaptureWriterConfigRetainsDiagnosticHandler() async throws {
        let writer = CaptureWriter()
        var config = CaptureWriter.CaptureWriterConfig()
        let handler: CaptureWriter.DiagnosticHandler = { _ in }

        config.diagnosticHandler = handler
        await writer.setConfig(config)

        let appliedConfig = await writer.getConfig()
        XCTAssertNotNil(appliedConfig.diagnosticHandler)
    }

    func testCaptureWriterConfigRetainsFinishWritingTimeout() async throws {
        let writer = CaptureWriter()
        var config = CaptureWriter.CaptureWriterConfig()

        config.finishWritingTimeoutSeconds = 1.25
        await writer.setConfig(config)

        let appliedConfig = await writer.getConfig()
        XCTAssertEqual(appliedConfig.finishWritingTimeoutSeconds, 1.25, accuracy: 0.0001)
    }

    func testCaptureWriterConfigClampsZeroFinishWritingTimeout() async throws {
        let writer = CaptureWriter()
        var config = CaptureWriter.CaptureWriterConfig()

        config.finishWritingTimeoutSeconds = 0.0
        await writer.setConfig(config)

        let appliedConfig = await writer.getConfig()
        XCTAssertGreaterThan(appliedConfig.finishWritingTimeoutSeconds, 0.0)
    }

    func testCaptureWriterDeinitCleanupReportsDiagnostics() async {
        let startExpectation = expectation(description: "deinit cleanup diagnostic emitted")
        let timeoutExpectation = expectation(description: "deinit timeout diagnostic emitted")
        let writer = CaptureWriter()

        var config = CaptureWriter.CaptureWriterConfig()
        config.finishWritingTimeoutSeconds = 1.5
        await writer.setConfig(config)
        await writer.testingSetDiagnosticHandler { diagnostic in
            if diagnostic == .deinitWhileRecording {
                startExpectation.fulfill()
            }
            if diagnostic == .finishWritingTimedOut(timeoutSeconds: 1.5) {
                timeoutExpectation.fulfill()
            }
        }
        writer.testingInvokeDeinitTimeoutPath()

        await fulfillment(of: [startExpectation, timeoutExpectation], timeout: 1.0)
    }
}
