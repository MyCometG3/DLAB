import XCTest
import AVFoundation
import CoreMedia
@testable import DLABCapture

private final class CounterBox: @unchecked Sendable {
    private let lock = UnfairLockBox()
    private var valueStorage = 0

    func increment() {
        lock.withLock {
            valueStorage += 1
        }
    }

    var value: Int {
        lock.withLock { valueStorage }
    }
}

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

    func testVideoStyle8KPresets() throws {
        struct Expectation {
            let style: VideoStyle
            let encodedSize: NSSize
            let visibleSize: NSSize
            let aspectRatio: NSSize
            let cleanApertureSize: NSSize
        }

        let cases: [Expectation] = [
            .init(style: .UHD8k_7680_4320_Full,
                  encodedSize: NSSize(width: 7680, height: 4320),
                  visibleSize: NSSize(width: 7680, height: 4320),
                  aspectRatio: NSSize(width: 1, height: 1),
                  cleanApertureSize: NSSize(width: 7680, height: 4320)),
            .init(style: .DCI8k_8192_4320_Full,
                  encodedSize: NSSize(width: 8192, height: 4320),
                  visibleSize: NSSize(width: 8192, height: 4320),
                  aspectRatio: NSSize(width: 1, height: 1),
                  cleanApertureSize: NSSize(width: 8192, height: 4320)),
            .init(style: .DCI8k_8192_4320_185,
                  encodedSize: NSSize(width: 8192, height: 4320),
                  visibleSize: NSSize(width: 7992, height: 4320),
                  aspectRatio: NSSize(width: 1, height: 1),
                  cleanApertureSize: NSSize(width: 7992, height: 4320)),
            .init(style: .DCI8k_8192_4320_239,
                  encodedSize: NSSize(width: 8192, height: 4320),
                  visibleSize: NSSize(width: 8192, height: 3432),
                  aspectRatio: NSSize(width: 1, height: 1),
                  cleanApertureSize: NSSize(width: 8192, height: 3432))
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.style.encodedSize(), testCase.encodedSize)
            XCTAssertEqual(testCase.style.visibleSize(), testCase.visibleSize)
            XCTAssertEqual(testCase.style.aspectRatio(), testCase.aspectRatio)

            let settings = testCase.style.settings(hOffset: 0, vOffset: 0)
            XCTAssertEqual((settings[AVVideoWidthKey] as? NSNumber)?.doubleValue, testCase.encodedSize.width)
            XCTAssertEqual((settings[AVVideoHeightKey] as? NSNumber)?.doubleValue, testCase.encodedSize.height)

            let cleanAperture = try XCTUnwrap(settings[AVVideoCleanApertureKey] as? [String: Any])
            XCTAssertEqual((cleanAperture[AVVideoCleanApertureWidthKey] as? NSNumber)?.doubleValue, testCase.cleanApertureSize.width)
            XCTAssertEqual((cleanAperture[AVVideoCleanApertureHeightKey] as? NSNumber)?.doubleValue, testCase.cleanApertureSize.height)
            XCTAssertEqual((cleanAperture[AVVideoCleanApertureHorizontalOffsetKey] as? NSNumber)?.doubleValue, 0)
            XCTAssertEqual((cleanAperture[AVVideoCleanApertureVerticalOffsetKey] as? NSNumber)?.doubleValue, 0)

            let pixelAspectRatio = try XCTUnwrap(settings[AVVideoPixelAspectRatioKey] as? [String: Any])
            XCTAssertEqual((pixelAspectRatio[AVVideoPixelAspectRatioHorizontalSpacingKey] as? NSNumber)?.doubleValue, 1)
            XCTAssertEqual((pixelAspectRatio[AVVideoPixelAspectRatioVerticalSpacingKey] as? NSNumber)?.doubleValue, 1)

            let colorProperties = try XCTUnwrap(settings[AVVideoColorPropertiesKey] as? [String: Any])
            XCTAssertEqual(colorProperties[AVVideoColorPrimariesKey] as? String, AVVideoColorPrimaries_ITU_R_2020)
            XCTAssertEqual(colorProperties[AVVideoTransferFunctionKey] as? String, AVVideoTransferFunction_ITU_R_709_2)
            XCTAssertEqual(colorProperties[AVVideoYCbCrMatrixKey] as? String, AVVideoYCbCrMatrix_ITU_R_2020)
        }
    }

    func testCaptureManagerVideoStyleListIncludes8KPresets() throws {
        let manager = CaptureManager()

        XCTAssertEqual(
            manager.videoStyleListOf(NSSize(width: 7680, height: 4320)),
            [.UHD8k_7680_4320_Full]
        )

        XCTAssertEqual(
            manager.videoStyleListOf(NSSize(width: 8192, height: 4320)),
            [.DCI8k_8192_4320_Full, .DCI8k_8192_4320_239, .DCI8k_8192_4320_185]
        )

        XCTAssertEqual(
            manager.videoStyleListOf(NSSize(width: 3840, height: 2160)),
            [.UHD4k_3840_2160_Full]
        )

        XCTAssertNil(manager.videoStyleListOf(NSSize(width: 123, height: 456)))
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

    func testCaptureManagerDisposeAudioPreviewWaitsForInFlightUse() async throws {
        let manager = CaptureManager()
        let preview = CaptureAudioPreview.TestingDouble()
        let started = expectation(description: "audio preview use started")
        let disposeStarted = expectation(description: "audio preview disposal started")
        let release = DispatchSemaphore(value: 0)
        let teardownCallCount = CounterBox()

        manager.testingSetAudioPreview(preview)

        DispatchQueue.global().async {
            _ = manager.testingWithAudioPreview { _ in
                started.fulfill()
                _ = release.wait(timeout: .now() + 2.0)
            }
        }

        await fulfillment(of: [started], timeout: 1.0)

        let disposeTask = Task {
            try await manager.testingDisposeAudioPreview(didTakeAudioPreviewState: {
                disposeStarted.fulfill()
            }) { _ in
                teardownCallCount.increment()
            }
        }

        await fulfillment(of: [disposeStarted], timeout: 1.0)
        XCTAssertNil(manager.testingWithAudioPreview { _ in () })
        XCTAssertEqual(teardownCallCount.value, 0)

        release.signal()
        try await disposeTask.value

        XCTAssertEqual(teardownCallCount.value, 1)
        XCTAssertNil(manager.testingWithAudioPreview { _ in () })
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
