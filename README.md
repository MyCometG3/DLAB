# DLAB

A Swift Package Manager wrapper for the Blackmagic DeckLink API.

DLAB provides two products that mirror the DLAB framework counterparts with
no API difference.

| SPM Product      | Framework Counterpart        | Language       |
|------------------|------------------------------|----------------|
| `DLABCore`       | DLABridging.framework        | Objective-C++  |
| `DLABCapture`    | DLABCaptureManager.framework | Swift          |

See [DLABSandbox][] for a sample SwiftUI application using this package.

[DLABSandbox]: https://github.com/MyCometG3/DLABSandbox

### Target URL for Swift Package Manager

```
https://github.com/MyCometG3/DLAB.git
```

---

## Requirements

- macOS 26.x, 15.x, 14.x, 13.x, 12.x, 11.x
- Blackmagic DeckLink / UltraStudio devices
- Blackmagic Desktop Video (11.4–16.0)
- Xcode 26.x / Swift 6.x

**Restrictions:** Compressed, Synchronized, and IP captures are not supported.

**Architecture:** Universal binary (x86_64 + arm64).

---

## DLABCore — Low-Level DeckLink Wrapper

DLABCore is a direct Objective-C++ wrapper around the DeckLink C++ API.

### Unsupported Interfaces

```
 : Following interfaces are not supported. (Section # are from SDK 16.0 pdf)
 : 2.5.8 IDeckLinkVideoFrame3DExtensions
 : 2.5.25 IDeckLinkGLScreenPreviewHelper
 : 2.5.26 IDeckLinkCocoaScreenPreviewCallback
 : 2.5.27 IDeckLinkDX9ScreenPreviewHelper
 : 2.5.34 IDeckLinkEncoderInput
 : 2.5.35 IDeckLinkEncoderInputCallback
 : 2.5.36 IDeckLinkEncoderPacket
 : 2.5.37 IDeckLinkEncoderVideoPacket
 : 2.5.38 IDeckLinkEncoderAudioPacket
 : 2.5.39 IDeckLinkH265NALPacket
 : 2.5.40 IDeckLinkEncoderConfiguration
 : 2.5.43 IDeckLinkVideoConversion
 : 2.5.49 IDeskLinkMetalScreenPreviewHelper
 : 2.5.50 IDeckLinkWPFDX9ScreenPreviewHelper
 : 2.5.51 IDeckLinkMacOutput
 : 2.5.52 IDeckLinkMacVideoBuffer
 : 2.5.53 IDeckLinkVideoBuffer
 : 2.5.54 IDeckLinkVideoBufferAllocatorProvider
 : 2.5.55 IDeckLinkVideoBufferAllocator
 : 2.5.57 IDeckLinkIPExtensions
 : 2.5.58 IDeckLinkIPFlowIterator
 : 2.5.59 IDeckLinkIPFlow
 : 2.5.60 IDeckLinkIPFlowAttributes
 : 2.5.61 IDeckLinkIPFlowStatus
 : 2.5.62 IDeckLinkIPFlowSetting
 : 2.6.x Any Streaming Interface APIs
```

### Basic Usage (Capture)

#### 1. Find a device with DLABBrowser

```swift
import Cocoa
import DLABCore

var device: DLABDevice? = nil
var running = false

do {
    let browser = DLABBrowser()
    _ = browser.registerDevicesForInput()
    let deviceList = browser.allDevices
    device = deviceList.first!
}
```

#### 2. Start input stream

```swift
if let device = device {
    try device.setInputScreenPreviewTo(parentView)

    let videoConnection: DLABVideoConnection = .HDMI
    let audioConnection: DLABAudioConnection = .embedded

    // Prepare SD video setting
    let vSetting = try device.createInputVideoSetting(
        of: .modeNTSC,
        pixelFormat: .format8BitYUV,
        inputFlag: []
    )

    // Prepare audio setting
    let audioChannelCount: UInt32 = (videoConnection == .HDMI && audioConnection == .embedded) ? 8 : 2
    let aSetting = try device.createInputAudioSetting(
        of: .type16bitInteger,
        channelCount: audioChannelCount,
        sampleRate: .rate48kHz
    )

    // NTSC-SD CleanAperture and PixelAspectRatio
    try vSetting.addClapExt(
        ofWidthN: 704, widthD: 1,
        heightN: 480, heightD: 1,
        hOffsetN: 4, hOffsetD: 1,
        vOffsetN: 0, vOffsetD: 1
    )
    try vSetting.addPaspExt(ofHSpacing: 40, vSpacing: 33)

    // Preferred CVPixelFormat
    vSetting.cvPixelFormatType = kCVPixelFormatType_32BGRA
    try vSetting.buildVideoFormatDescription()

    // HDMI surround audio layout
    let hdmiAudioChannels: UInt32 = 6  // 5.1ch
    let reverseCh3Ch4 = true           // (ch3, ch4) == (LFE, C)
    if videoConnection == .HDMI, audioConnection == .embedded,
       aSetting.channelCount >= hdmiAudioChannels, hdmiAudioChannels > 0 {
        try aSetting.buildAudioFormatDescription(
            forHDMIAudioChannels: hdmiAudioChannels,
            swap3chAnd4ch: reverseCh3Ch4
        )
    }

    device.inputDelegate = self
    try device.enableVideoInput(with: vSetting, on: videoConnection)
    try device.enableAudioInput(with: aSetting, on: audioConnection)
    try device.startStreams()
    running = true
}
```

#### 3. Handle samples

```swift
func processCapturedVideoSample(_ sampleBuffer: CMSampleBuffer,
                                of sender: DLABDevice) {
    print("video")
}
func processCapturedAudioSample(_ sampleBuffer: CMSampleBuffer,
                                of sender: DLABDevice) {
    print("audio")
}
func processCapturedVideoSample(_ sampleBuffer: CMSampleBuffer,
                                timecodeSetting setting: DLABTimecodeSetting,
                                of sender: DLABDevice) {
    print("video/timecode")
}
```

#### 4. Stop input stream

```swift
running = false
if let device = device {
    try device.stopStreams()
    try device.disableVideoInput()
    try device.disableAudioInput()
    device.inputDelegate = nil
    try device.setInputScreenPreviewTo(nil)
}
device = nil
```

---

## DLABCapture — High-Level Capture & Recording API

DLABCapture provides a simplified Swift API built on top of DLABCore.
It handles sample processing, preview, encoding, and recording.

### Basic Usage

#### 1. Start capture session

```swift
import Cocoa
import DLABCore
import DLABCapture

var manager: CaptureManager? = nil

if manager == nil {
    manager = CaptureManager()
}
if let manager = manager {
    guard manager.findFirstDevice() != nil else { return }

    // Capture settings — HD-1080i or SD-NTSC
    #if true
        manager.displayMode = .modeHD1080i5994
        manager.pixelFormat = .format10BitYUV
        manager.videoStyle = .HD_1920_1080_Full
        manager.videoConnection = .HDMI
        manager.audioConnection = .embedded
        manager.fieldDetail = kCMFormatDescriptionFieldDetail_SpatialFirstLineEarly
    #else
        manager.displayMode = .modeNTSC
        manager.pixelFormat = .format8BitYUV
        manager.videoStyle = .SD_720_486_16_9
        manager.offset = NSPoint(x: 4, y: 0)
        manager.videoConnection = .sVideo
        manager.audioConnection = .analogRCA
        manager.fieldDetail = kCMFormatDescriptionFieldDetail_SpatialFirstLineLate
    #endif

    // Convert pixel format
    manager.cvPixelFormat = kCVPixelFormatType_32BGRA

    // Recording codec
    manager.encodeProRes422 = false
    manager.encodeVideoCodecType = kCMVideoCodecType_H264
    manager.encodeAudio = true

    // Preview — choose one
    // manager.videoPreview = myCaptureVideoPreview      // CALayer
    manager.parentView = myCocoaScreenPreview            // CocoaScreenPreview

    // HDMI audio layout
    if manager.videoConnection == .HDMI,
       manager.audioConnection == .embedded {
        manager.audioChannels = 8
        manager.hdmiAudioChannels = 6
        manager.reverseCh3Ch4 = true
    }

    manager.sampleTimescale = 30000
    manager.captureStart()
}
```

#### 2. Toggle recording

```swift
if let manager = manager, manager.running {
    manager.recordToggle()
}
```

#### 3. Stop capture

```swift
if let manager = manager, manager.running {
    if manager.recording {
        manager.recordToggle()
    }
    manager.captureStop()
}
manager = nil
```

---

## Developer Notice

### App Sandbox Entitlements

See Blackmagic DeckLink SDK PDF Section 2.2, and
[App Sandbox Temporary Exception Entitlements][sandbox-ent] in the
Apple Developer Documentation Archive.

[sandbox-ent]: https://developer.apple.com

### Hardened Runtime Entitlements

Set `com.apple.security.cs.disable-library-validation` to `YES`.
See [Disable Library Validation Entitlement][hardened-dis] in the
Apple Developer Documentation.

[hardened-dis]: https://developer.apple.com

### SDK Verification

Verified with Blackmagic DeckLink SDK **16.0**.

---

## Development Environment

- macOS 26.5.1 Tahoe
- Xcode 26.5
- Swift 6.3.2

## License

The MIT License

Copyright © 2017–2026 MyCometG3. All rights reserved.
