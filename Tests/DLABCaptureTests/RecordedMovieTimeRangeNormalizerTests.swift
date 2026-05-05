import XCTest
import AVFoundation
import AudioToolbox
import CoreVideo
@testable import DLABCapture

final class RecordedMovieTimeRangeNormalizerTests: XCTestCase {
    func testNormalizerTrimsLeadingVideoPadding() async throws {
        let movieURL = try await TestMovieFactory.makeMovie(
            name: "leading-video-padding",
            videoDuration: TestMovieFactory.videoSpan,
            audioDuration: nil
        )
        defer { TestMovieFactory.cleanup(movieURL) }

        try TestMovieFactory.mutateMovie(at: movieURL) { movie in
            movie.timescale = 600
            movie.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: TestMovieFactory.leadingPad))
        }

        let result = try RecordedMovieTimeRangeNormalizer.normalizeMovie(at: movieURL)
        XCTAssertTrue(result.didRewrite)
        XCTAssertEqual(result.mediaKind, .video)

        let movie = try TestMovieFactory.openMovie(at: movieURL)
        XCTAssertEqual(movie.duration.seconds, TestMovieFactory.videoSpan.seconds, accuracy: 0.001)

        let ranges = try TestMovieFactory.trackPresentationRanges(in: movie, characteristic: .visual)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start.seconds, 0.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeRangeGetEnd(ranges[0]).seconds, TestMovieFactory.videoSpan.seconds, accuracy: 0.001)
    }

    func testCaptureManagerNormalizeRecordedMovieTimeRangeTrimsTrailingAudioOverrunAgainstVideo() async throws {
        let movieURL = try await TestMovieFactory.makeMovie(
            name: "trailing-audio-overrun",
            videoDuration: TestMovieFactory.videoSpan,
            audioDuration: TestMovieFactory.longerAudioSpan
        )
        defer { TestMovieFactory.cleanup(movieURL) }

        let manager = CaptureManager()
        let rewritten = try manager.normalizeRecordedMovieTimeRange(at: movieURL)
        XCTAssertTrue(rewritten)

        let movie = try TestMovieFactory.openMovie(at: movieURL)
        XCTAssertEqual(movie.duration.seconds, TestMovieFactory.videoSpan.seconds, accuracy: 0.001)
    }

    func testNormalizerUsesAudioFallbackForAudioOnlyMovie() async throws {
        let movieURL = try await TestMovieFactory.makeMovie(
            name: "audio-only-fallback",
            videoDuration: nil,
            audioDuration: TestMovieFactory.audioOnlySpan
        )
        defer { TestMovieFactory.cleanup(movieURL) }

        try TestMovieFactory.mutateMovie(at: movieURL) { movie in
            movie.timescale = 600
            movie.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: TestMovieFactory.leadingPad))
        }

        let result = try RecordedMovieTimeRangeNormalizer.normalizeMovie(at: movieURL)
        XCTAssertTrue(result.didRewrite)
        XCTAssertEqual(result.mediaKind, .audio)

        let movie = try TestMovieFactory.openMovie(at: movieURL)
        XCTAssertEqual(movie.duration.seconds, TestMovieFactory.audioOnlySpan.seconds, accuracy: 0.001)

        let ranges = try TestMovieFactory.trackPresentationRanges(in: movie, characteristic: .audible)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start.seconds, 0.0, accuracy: 0.001)
    }

    func testNormalizerReturnsFalseWhenMovieIsAlreadyAligned() async throws {
        let movieURL = try await TestMovieFactory.makeMovie(
            name: "already-aligned",
            videoDuration: TestMovieFactory.videoSpan,
            audioDuration: nil
        )
        defer { TestMovieFactory.cleanup(movieURL) }

        let result = try RecordedMovieTimeRangeNormalizer.normalizeMovie(at: movieURL)
        XCTAssertFalse(result.didRewrite)
        XCTAssertEqual(result.mediaKind, .video)
    }

    func testNormalizerUsesEarliestStartLatestEndAcrossOverlappingVideoTracks() async throws {
        let movieURL = try await TestMovieFactory.makeMovie(
            name: "overlap-video-tracks",
            videoDuration: TestMovieFactory.videoSpan,
            audioDuration: nil
        )
        defer { TestMovieFactory.cleanup(movieURL) }

        try TestMovieFactory.mutateMovie(at: movieURL) { movie in
            movie.timescale = 600
            try TestMovieFactory.addSecondaryVideoTrack(
                to: movie,
                at: TestMovieFactory.overlapStart
            )
            movie.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: TestMovieFactory.leadingPad))
        }

        let result = try RecordedMovieTimeRangeNormalizer.normalizeMovie(at: movieURL)
        XCTAssertTrue(result.didRewrite)

        let movie = try TestMovieFactory.openMovie(at: movieURL)
        XCTAssertEqual(movie.duration.seconds, TestMovieFactory.overlapExpectedDuration.seconds, accuracy: 0.001)

        let ranges = try TestMovieFactory.trackPresentationRanges(in: movie, characteristic: .visual)
            .sorted { CMTimeCompare($0.start, $1.start) < 0 }
        XCTAssertEqual(ranges.count, 2)
        XCTAssertLessThan(ranges[1].start.seconds, CMTimeRangeGetEnd(ranges[0]).seconds)
    }

    func testNormalizerUsesEarliestStartLatestEndAcrossVideoTracksWithGap() async throws {
        let movieURL = try await TestMovieFactory.makeMovie(
            name: "gap-video-tracks",
            videoDuration: TestMovieFactory.videoSpan,
            audioDuration: nil
        )
        defer { TestMovieFactory.cleanup(movieURL) }

        try TestMovieFactory.mutateMovie(at: movieURL) { movie in
            movie.timescale = 600
            try TestMovieFactory.addSecondaryVideoTrack(
                to: movie,
                at: TestMovieFactory.gapStart
            )
            movie.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: TestMovieFactory.leadingPad))
        }

        let result = try RecordedMovieTimeRangeNormalizer.normalizeMovie(at: movieURL)
        XCTAssertTrue(result.didRewrite)

        let movie = try TestMovieFactory.openMovie(at: movieURL)
        XCTAssertEqual(movie.duration.seconds, TestMovieFactory.gapExpectedDuration.seconds, accuracy: 0.001)

        let ranges = try TestMovieFactory.trackPresentationRanges(in: movie, characteristic: .visual)
            .sorted { CMTimeCompare($0.start, $1.start) < 0 }
        XCTAssertEqual(ranges.count, 2)
        XCTAssertGreaterThan(ranges[1].start.seconds, CMTimeRangeGetEnd(ranges[0]).seconds)
    }

    func testCaptureManagerShouldPostProcessRecordedMovieRespectsConditions() throws {
        let manager = CaptureManager()
        let existingFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("post-process-\(UUID().uuidString).tmp")
        try Data().write(to: existingFileURL)
        defer { TestMovieFactory.cleanup(existingFileURL) }

        manager.trimsRecordedMovieTimeRangeAfterRecording = true

        XCTAssertFalse(manager.testingShouldPostProcessRecordedMovie(
            writerError: NSError(domain: "DLABCaptureTests", code: 1),
            outputURL: existingFileURL
        ))
        XCTAssertFalse(manager.testingShouldPostProcessRecordedMovie(
            writerError: nil,
            outputURL: nil
        ))
        XCTAssertTrue(manager.testingShouldPostProcessRecordedMovie(
            writerError: nil,
            outputURL: existingFileURL
        ))
    }

    func testCaptureManagerPostProcessStoresLastErrorAndInvokesCallback() async throws {
        let manager = CaptureManager()
        let movieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).mov")

        let callbackExpectation = expectation(description: "post-process callback")
        manager.recordedMoviePostProcessErrorHandler = { callbackURL, error in
            XCTAssertEqual(callbackURL, movieURL)
            XCTAssertFalse(error.localizedDescription.isEmpty)
            callbackExpectation.fulfill()
        }

        await manager.testingPostProcessRecordedMovieIfNeeded(at: movieURL)

        XCTAssertNotNil(manager.lastRecordedMoviePostProcessError)
        await fulfillment(of: [callbackExpectation], timeout: 1.0)
    }

    func testCaptureWriterResolvedMovieURLReturnsGeneratedURLAfterOpenSession() async throws {
        let writer = CaptureWriter()
        var config = CaptureWriter.CaptureWriterConfig()
        config.useAudio = false
        config.useVideo = false
        config.useTimecode = false
        config.movieURL = nil

        await writer.setConfig(config)
        await writer.openSession()

        let resolvedURL = await writer.resolvedMovieURL()
        XCTAssertNotNil(resolvedURL)
    }
}

private enum TestMovieFactory {
    static let videoFrameRate: CMTimeScale = 30
    static let audioSampleRate: CMTimeScale = 48_000
    static let videoSpan = CMTime(value: 6, timescale: 30)
    static let longerAudioSpan = CMTime(value: 12_000, timescale: 48_000)
    static let audioOnlySpan = CMTime(value: 9_600, timescale: 48_000)
    static let leadingPad = CMTime(value: 3, timescale: 30)
    static let overlapStart = CMTime(value: 3, timescale: 30)
    static let gapStart = CMTime(value: 12, timescale: 30)
    static let overlapExpectedDuration = CMTime(value: 9, timescale: 30)
    static let gapExpectedDuration = CMTime(value: 18, timescale: 30)

    enum FixtureError: Error {
        case missingTrack(String)
        case assetWriterFailure(String)
        case appendFailure(String)
        case formatDescriptionFailure(OSStatus)
        case bufferCreationFailure(OSStatus)
        case sampleBufferCreationFailure(OSStatus)
        case pixelBufferCreationFailure(CVReturn)
    }

    final class AssetWriterBox: @unchecked Sendable {
        let writer: AVAssetWriter

        init(_ writer: AVAssetWriter) {
            self.writer = writer
        }
    }

    static func makeMovie(name: String,
                          videoDuration: CMTime?,
                          audioDuration: CMTime?) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        guard videoDuration != nil || audioDuration != nil else {
            throw FixtureError.assetWriterFailure("No media tracks were requested.")
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var videoInput: AVAssetWriterInput?
        var audioInput: AVAssetWriterInput?
        var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

        if videoDuration != nil {
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16,
                AVVideoHeightKey: 16
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw FixtureError.assetWriterFailure("Cannot add video input.")
            }
            writer.add(input)
            videoInput = input

            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )
        }

        if audioDuration != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: audioSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw FixtureError.assetWriterFailure("Cannot add audio input.")
            }
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw FixtureError.assetWriterFailure(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        if let videoDuration, let videoInput, let pixelBufferAdaptor {
            let frameDuration = CMTime(value: 1, timescale: videoFrameRate)
            let frameCount = max(1, Int(CMTimeConvertScale(videoDuration, timescale: videoFrameRate, method: .default).value))

            for frameIndex in 0..<frameCount {
                while !videoInput.isReadyForMoreMediaData {
                    await Task.yield()
                }

                let pixelBuffer = try makePixelBuffer()
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw FixtureError.appendFailure(writer.error?.localizedDescription ?? "Video append failed.")
                }
            }
        }

        if let audioDuration, let audioInput {
            while !audioInput.isReadyForMoreMediaData {
                await Task.yield()
            }

            let sampleCount = max(1, Int(CMTimeConvertScale(audioDuration, timescale: audioSampleRate, method: .default).value))
            let sampleBuffer = try makeAudioSampleBuffer(sampleCount: sampleCount, presentationTime: .zero)
            guard audioInput.append(sampleBuffer) else {
                throw FixtureError.appendFailure(writer.error?.localizedDescription ?? "Audio append failed.")
            }
        }

        let endTime = [videoDuration, audioDuration]
            .compactMap { $0 }
            .max { CMTimeCompare($0, $1) < 0 } ?? .zero
        writer.endSession(atSourceTime: endTime)

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        try await finishWriting(writer)

        return url
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func openMovie(at url: URL) throws -> AVMutableMovie {
        AVMutableMovie(url: url, options: nil)
    }

    static func mutateMovie(at url: URL, update: (AVMutableMovie) throws -> Void) throws {
        let movie = try openMovie(at: url)
        try update(movie)
        try movie.writeHeader(to: url, fileType: .mov, options: .addMovieHeaderToDestination)
    }

    static func addSecondaryVideoTrack(to movie: AVMutableMovie, at startTime: CMTime) throws {
        guard let sourceTrack = movie.tracks(withMediaCharacteristic: .visual).first else {
            throw FixtureError.missingTrack("No visual track available.")
        }
        guard let sourceRange = presentationRange(for: sourceTrack) else {
            throw FixtureError.missingTrack("No presentation range available for source visual track.")
        }
        guard let newTrack = movie.addMutableTrack(withMediaType: .video, copySettingsFrom: sourceTrack, options: nil) else {
            throw FixtureError.assetWriterFailure("Failed to create secondary video track.")
        }
        try newTrack.insertTimeRange(sourceRange, of: sourceTrack, at: startTime, copySampleData: false)
    }

    static func trackPresentationRanges(in movie: AVMutableMovie,
                                        characteristic: AVMediaCharacteristic) throws -> [CMTimeRange] {
        movie.tracks(withMediaCharacteristic: characteristic).compactMap { track in
            guard let range = presentationRange(for: track) else {
                return nil
            }
            return range
        }
    }

    private static func presentationRange(for track: AVMutableMovieTrack) -> CMTimeRange? {
        var unionRange: CMTimeRange?
        for segment in track.segments where !segment.isEmpty {
            let targetRange = segment.timeMapping.target
            guard targetRange.isValid, !targetRange.isEmpty else { continue }
            if let current = unionRange {
                unionRange = CMTimeRangeGetUnion(current, otherRange: targetRange)
            } else {
                unionRange = targetRange
            }
        }
        return unionRange
    }

    private static func finishWriting(_ writer: AVAssetWriter) async throws {
        let writerBox = AssetWriterBox(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = writerBox.writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func makePixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         16,
                                         16,
                                         kCVPixelFormatType_32ARGB,
                                         attributes as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw FixtureError.pixelBufferCreationFailure(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }

        return pixelBuffer
    }

    private static func makeAudioSampleBuffer(sampleCount: Int,
                                              presentationTime: CMTime) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(audioSampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw FixtureError.formatDescriptionFailure(formatStatus)
        }

        let dataSize = sampleCount * 2
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw FixtureError.bufferCreationFailure(blockStatus)
        }

        let zeroes = [UInt8](repeating: 0, count: dataSize)
        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: zeroes,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw FixtureError.bufferCreationFailure(replaceStatus)
        }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: audioSampleRate),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = 2
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw FixtureError.sampleBufferCreationFailure(sampleStatus)
        }

        return sampleBuffer
    }
}
