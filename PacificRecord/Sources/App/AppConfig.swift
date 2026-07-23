import Foundation

/// App-level build configuration.
enum AppConfig {
    /// iCloud Drive storage. Disabled until the app is signed with a paid Apple
    /// Developer team — the iCloud entitlement requires a provisioned container,
    /// which free provisioning can't create.
    ///
    /// To re-enable:
    ///   1. Set this to `true`.
    ///   2. Restore `CODE_SIGN_ENTITLEMENTS` in `project.yml`.
    ///   3. Uncomment `NSUbiquitousContainers` in `PacificRecord/Info.plist`.
    ///   4. Run `xcodegen generate`, then pick your Team in Signing & Capabilities.
    static let iCloudEnabled = false
}
