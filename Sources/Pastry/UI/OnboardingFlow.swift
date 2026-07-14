import Foundation

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case shortcut
    case copy
    case permission

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    func canContinue(copyComplete: Bool) -> Bool {
        self != .copy || copyComplete
    }
}

enum OnboardingPreferences {
    static let currentVersion = 1

    static func needsPresentation(defaults: UserDefaults = .standard) -> Bool {
        return defaults.integer(forKey: UserDefaultsKeys.onboardingCompletedVersion) < currentVersion
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: UserDefaultsKeys.onboardingCompletedVersion)
    }
}

struct OnboardingCopyDetection {
    private let baselineItemIDs: Set<UUID>
    private(set) var isComplete = false

    init(baselineItemIDs: Set<UUID>) {
        self.baselineItemIDs = baselineItemIDs
    }

    @discardableResult
    mutating func observe(itemIDs: Set<UUID>) -> Bool {
        guard !isComplete else { return true }
        guard !itemIDs.subtracting(baselineItemIDs).isEmpty else { return false }
        isComplete = true
        return true
    }
}
