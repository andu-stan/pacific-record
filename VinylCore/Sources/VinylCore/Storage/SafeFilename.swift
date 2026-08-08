import Foundation

/// Builds file names that can only ever land in the directory you meant.
///
/// Record ids and cover paths are *data*, and data can come from a library file
/// somebody else made — an imported backup is free to carry a record id of
/// `../../../Library/Preferences/evil`. Anything used to build a path is
/// therefore reduced to a single harmless component before it reaches the file
/// system, and paths read back out of a database are checked for containment.
public enum SafeFilename {
    /// Deliberately narrow: the ids this app generates are UUIDs, and anything
    /// wider than this is somebody else's data rather than ours.
    private static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    private static let maxLength = 96

    /// Reduces `raw` to one safe path component: no separators, no `.` or `..`,
    /// never empty, bounded in length.
    public static func component(_ raw: String, fallback: String = "unnamed") -> String {
        var kept = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where allowed.contains(scalar) {
            kept.append(scalar)
            if kept.count >= maxLength { break }
        }
        let cleaned = String(kept)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// A file extension reduced to letters and digits. Remote URLs decide this
    /// one, so it gets the same treatment as an id.
    public static func fileExtension(_ raw: String, fallback: String) -> String {
        let cleaned = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty, cleaned.count <= 8 else { return fallback }
        return cleaned
    }

    /// True when `url` genuinely sits inside `directory` once `..` and symlinks
    /// are resolved — the check to run before opening a path that came out of a
    /// database or an archive.
    public static func isContained(_ url: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard target != base else { return false }
        return target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// Resolves a stored relative path against the library folder, or nil if it
    /// would escape. Use this everywhere a `cover_path` becomes a file URL.
    public static func resolve(_ relativePath: String, in directory: URL) -> URL? {
        let url = directory.appendingPathComponent(relativePath)
        return isContained(url, in: directory) ? url : nil
    }
}
