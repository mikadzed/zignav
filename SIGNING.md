# Code Signing ZigNav for Distribution

This document explains how to sign and notarize ZigNav for distribution.

## Why Sign?

- macOS Gatekeeper blocks unsigned apps by default
- Users must right-click and "Open" to run unsigned apps
- Signed apps provide better user experience and security

## Requirements

- Apple Developer Program membership ($99/year)
- Developer ID Application certificate
- macOS with Xcode installed

## Signing Process

### 1. Create Developer ID Certificate

1. Log in to [Apple Developer Portal](https://developer.apple.com/account)
2. Go to Certificates, Identifiers & Profiles
3. Create a new "Developer ID Application" certificate
4. Download and install in Keychain

### 2. Sign the App Bundle

```bash
# Sign the app with your Developer ID
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --timestamp \
  zig-out/ZigNav.app

# Verify signature
codesign --verify --verbose=4 zig-out/ZigNav.app
spctl --assess --type execute --verbose=4 zig-out/ZigNav.app
```

### 3. Notarize with Apple

Starting with macOS 10.15, apps must also be notarized:

```bash
# Create zip for notarization
ditto -c -k --keepParent zig-out/ZigNav.app ZigNav.zip

# Submit for notarization
xcrun notarytool submit ZigNav.zip \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

# Staple the notarization ticket
xcrun stapler staple zig-out/ZigNav.app
```

### 4. Create Distribution Archive

```bash
# Create final distributable zip
ditto -c -k --keepParent zig-out/ZigNav.app ZigNav-signed.zip
```

## Hardened Runtime

For notarization, the app must use hardened runtime. The `--options runtime` flag enables this during signing.

If the app requires specific entitlements, create an `entitlements.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

Then sign with:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --entitlements entitlements.plist \
  --timestamp \
  zig-out/ZigNav.app
```

## Without Signing

Users can run unsigned apps by:

1. **First launch**: Right-click ZigNav.app > "Open" > "Open" in dialog
2. **Command line**: `xattr -cr /path/to/ZigNav.app`
3. **System Settings**: Security & Privacy > "Open Anyway" after blocked launch attempt

## References

- [Apple Developer Documentation: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Apple Developer Documentation: Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
