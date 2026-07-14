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

    #if DEBUG
    func testDevelopmentOverridePresentsEvenAfterCompletion() {
        OnboardingPreferences.markCompleted(defaults: defaults)
        defaults.set(true, forKey: UserDefaultsKeys.developmentShowOnboarding)

        XCTAssertTrue(OnboardingPreferences.needsPresentation(defaults: defaults))
    }

    func testDisabledDevelopmentOverrideRespectsCompletion() {
        OnboardingPreferences.markCompleted(defaults: defaults)
        defaults.set(false, forKey: UserDefaultsKeys.developmentShowOnboarding)

        XCTAssertFalse(OnboardingPreferences.needsPresentation(defaults: defaults))
    }
    #endif

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

    func testShortcutFeedbackNotificationNameIsStable() {
        XCTAssertEqual(
            Notification.Name.onboardingShortcutDetected.rawValue,
            "onboardingShortcutDetected"
        )
    }
}
