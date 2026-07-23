import Foundation
import GRDB

/// A physical place a record can live — a shelf, a room, a house, a country.
public struct Location: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// The location preselected when adding a record.
    public var isDefault: Bool
    /// Manual ordering (creation order by default).
    public var sortIndex: Int

    public static let databaseTableName = "location"

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault = "is_default"
        case sortIndex = "sort_index"
    }

    public init(id: String, name: String, isDefault: Bool = false, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.sortIndex = sortIndex
    }
}
