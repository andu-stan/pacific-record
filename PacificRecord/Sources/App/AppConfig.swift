import Foundation

/// App-level build configuration.
enum AppConfig {
    /// iCloud Drive storage: the SQLite file and `Covers/` live in the app's
    /// ubiquity container, visible in Files and synced across devices.
    ///
    /// Requires all three of: this flag, the iCloud keys in
    /// `PacificRecord.entitlements`, and `NSUbiquitousContainers` in
    /// `Info.plist` — plus the iCloud capability on a paid team, since free
    /// provisioning can't create a container. Turning this off falls back to
    /// local storage without losing anything.
    static let iCloudEnabled = true
}
