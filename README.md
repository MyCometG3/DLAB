# DLAB

A wrapper swift package for Blackmagic DeckLinkAPI.framework.

###Experimental Alpha version
Package DLAB contains two products.

- Product "DLABCore" substitutes for DLABridging.framework (Objective-C++).
- Product "DLABCapture" substitutes for DLABCaptureManager.framework (Swift). 

###Target URL for Swift Package Manager
URL: https://github.com/MyCometG3/DLAB.git

###Developer Notice
#####1) AppEntitlements for Sandboxing

- See: Blackmagic DeckLink SDK pdf Section 2.2.
- Ref: "Entitlement Key Reference/App Sandbox Temporary Exception Entitlements" from Apple Developer Documentation Archive

#####2) AppEntitlements for Hardened Runtime
- Set com.apple.security.cs.disable-library-validation to YES.
- Ref: "Documentation/Bundle Resources/Entitlements/Hardened Runtime/Disable Library Validation Entitlement" from Apple Developer Documentation.
