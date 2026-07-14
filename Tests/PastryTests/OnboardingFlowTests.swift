import XCTest
@testable import Pastry

final class OnboardingFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.pastry.onboarding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallNeedsOnboarding() {
        XCTAssertTrue(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testCompletingCurrentVersionStopsAutomaticPresentation() {
        OnboardingPreferences.markCompleted(defaults: defaults)

        XCTAssertFalse(OnboardingPreferences.needsPresentation(defaults: defaults))
        XCTAssertEqual(
            defaults.integer(forKey: UserDefaultsKeys.onboardingCompletedVersion),
            OnboardingPreferences.currentVersion
        )
    }

    func testOlderCompletedVersionPresentsNewOnboarding() {
        defaults.set(
            OnboardingPreferences.currentVersion - 1,
            forKey: UserDefaultsKeys.onboardingCompletedVersion
        )

        XCTAssertTrue(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testLegacyDevelopmentOverrideDoesNotForcePresentation() {
        OnboardingPreferences.markCompleted(defaults: defaults)
        defaults.set(true, forKey: "development_show_onboarding")

        XCTAssertFalse(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testStepsHaveStableForwardAndBackwardOrder() {
        XCTAssertEqual(OnboardingStep.welcome.next, .shortcut)
        XCTAssertEqual(OnboardingStep.shortcut.next, .copy)
        XCTAssertEqual(OnboardingStep.copy.next, .permission)
        XCTAssertNil(OnboardingStep.permission.next)

        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.shortcut.previous, .welcome)
        XCTAssertEqual(OnboardingStep.copy.previous, .shortcut)
        XCTAssertEqual(OnboardingStep.permission.previous, .copy)
    }

    func testIncompleteCopyStepPromptsInsteadOfAdvancing() {
        XCTAssertTrue(OnboardingStep.copy.shouldPromptForCopy(copyComplete: false))
        XCTAssertFalse(OnboardingStep.copy.shouldPromptForCopy(copyComplete: true))
        XCTAssertFalse(OnboardingStep.shortcut.shouldPromptForCopy(copyComplete: false))
    }

    func testCopyDetectionOnlyCompletesForItemAfterBaseline() {
        let baseline = UUID()
        var detection = OnboardingCopyDetection(baselineItemIDs: [baseline])

        XCTAssertFalse(detection.observe(itemIDs: [baseline]))
        XCTAssertTrue(detection.observe(itemIDs: [baseline, UUID()]))
        XCTAssertTrue(detection.isComplete)
    }

    func testCopyDetectionWithoutBaselineAcceptsFirstItem() {
        var detection = OnboardingCopyDetection(baselineItemIDs: [])

        XCTAssertTrue(detection.observe(itemIDs: [UUID()]))
    }

    func testActivationFeedbackDistinguishesShortcutAndMenuBar() {
        XCTAssertNotEqual(OnboardingActivationSource.shortcut, .menuBar)
        XCTAssertNotEqual(
            OnboardingActivationFeedback(source: .shortcut),
            OnboardingActivationFeedback(source: .menuBar)
        )
        XCTAssertNil(OnboardingActivationFeedback(source: nil).badgeKey)
        XCTAssertEqual(
            Notification.Name.onboardingActivationDetected.rawValue,
            "onboardingActivationDetected"
        )
    }
}
