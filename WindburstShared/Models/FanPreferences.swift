import Foundation

public struct FanIndividualPreferences: Codable, Sendable, Equatable, Identifiable {
    public var fanIndex: Int
    public var isHidden: Bool
    public var displayName: String?
    public var userMinRPM: Int?
    public var userMaxRPM: Int?
    public var assignedCurveID: UUID?

    public var id: Int { fanIndex }

    public init(
        fanIndex: Int,
        isHidden: Bool = false,
        displayName: String? = nil,
        userMinRPM: Int? = nil,
        userMaxRPM: Int? = nil,
        assignedCurveID: UUID? = nil
    ) {
        self.fanIndex = fanIndex
        self.isHidden = isHidden
        self.displayName = displayName
        self.userMinRPM = userMinRPM
        self.userMaxRPM = userMaxRPM
        self.assignedCurveID = assignedCurveID
    }
}

public struct FanPreferencesCollection: Codable, Sendable, Equatable {
    public var entries: [FanIndividualPreferences]

    public init(entries: [FanIndividualPreferences] = []) {
        self.entries = entries
    }

    public func preferences(for index: Int) -> FanIndividualPreferences {
        entries.first { $0.fanIndex == index } ?? FanIndividualPreferences(fanIndex: index)
    }

    public mutating func setPreferences(_ preferences: FanIndividualPreferences) {
        if let entryIndex = entries.firstIndex(where: { $0.fanIndex == preferences.fanIndex }) {
            entries[entryIndex] = preferences
        } else {
            entries.append(preferences)
        }
    }
}
