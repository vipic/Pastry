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

    func shouldPromptForCopy(copyComplete: Bool) -> Bool {
        self == .copy && !copyComplete
    }
}

enum OnboardingActivationSource: Equatable {
    case shortcut
    case menuBar
}

struct OnboardingActivationFeedback: Equatable {
    let titleKey: String
    let subtitleKey: String
    let highlightsShortcut: Bool

    init(source: OnboardingActivationSource?) {
        switch source {
        case .shortcut:
            titleKey = "onboarding.shortcut.detected_title"
            subtitleKey = "onboarding.shortcut.detected_subtitle"
            highlightsShortcut = true
        case .menuBar:
            titleKey = "onboarding.shortcut.menubar_detected_title"
            subtitleKey = "onboarding.shortcut.menubar_detected_subtitle"
            highlightsShortcut = false
        case nil:
            titleKey = "onboarding.shortcut.title"
            subtitleKey = "onboarding.shortcut.subtitle"
            highlightsShortcut = false
        }
    }
}

struct OnboardingCopyActionFeedback: Equatable {
    let iconName: String
    let labelKey: String

    init(isComplete: Bool) {
        iconName = isComplete ? "checkmark" : "doc.on.doc"
        labelKey = isComplete ? "onboarding.copy.copied_action" : "onboarding.copy.action"
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

struct OnboardingCopyItem: Equatable {
    let id: UUID
    let content: String
}

enum OnboardingCopyOutcome: Equatable {
    case pending
    case sampleText
    case otherContent

    var isComplete: Bool { self != .pending }
}

struct OnboardingCopyDetection {
    private let baselineItemIDs: Set<UUID>
    private(set) var outcome: OnboardingCopyOutcome = .pending

    var isComplete: Bool { outcome.isComplete }

    init(baselineItemIDs: Set<UUID>) {
        self.baselineItemIDs = baselineItemIDs
    }

    @discardableResult
    mutating func observe(items: [OnboardingCopyItem], sampleText: String) -> Bool {
        guard !isComplete else { return true }
        guard let newItem = items.first(where: { !baselineItemIDs.contains($0.id) }) else {
            return false
        }
        outcome = newItem.content == sampleText ? .sampleText : .otherContent
        return true
    }
}
