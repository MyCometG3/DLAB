# DLAB

A wrapper swift package for Blackmagic DeckLinkAPI.framework.

### DLAB is the SPM version of DLAB frameworks. No API difference.

Package DLAB contains two products. See DLABSandbox - sample SwiftUI application.

- Product "DLABCore" substitutes for DLABridging.framework (Objective-C++).
- Product "DLABCapture" substitutes for DLABCaptureManager.framework (Swift).

### Target URL for Swift Package Manager

URL: https://github.com/MyCometG3/DLAB.git

### Developer Notice
##### 1) AppEntitlements for Sandboxing

- See: Blackmagic DeckLink SDK pdf Section 2.2.
- Ref: "Entitlement Key Reference/App Sandbox Temporary Exception Entitlements" from Apple Developer Documentation Archive

##### 2) AppEntitlements for Hardened Runtime
- Set com.apple.security.cs.disable-library-validation to YES.
- Ref: "Documentation/Bundle Resources/Entitlements/Hardened Runtime/Disable Library Validation Entitlement" from Apple Developer Documentation.

##### 3) SDK verification
- Verified with Blackmagic DeckLink SDK **16.0**.

#### Development environment
- macOS 26.4.1 Tahoe
- Xcode 26.4.1
- Swift 6.3.1

#### License
- The MIT License

Copyright © 2022-2026年 MyCometG3. All rights reserved.
