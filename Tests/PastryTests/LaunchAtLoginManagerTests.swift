import ServiceManagement
import XCTest
@testable import Pastry

final class LaunchAtLoginManagerTests: XCTestCase {
    func testSetEnabledRegistersService() throws {
        let service = FakeLaunchAtLoginService()
        let manager = LaunchAtLoginManager(service: service)

        try manager.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testSetDisabledUnregistersService() throws {
        let service = FakeLaunchAtLoginService()
        let manager = LaunchAtLoginManager(service: service)

        try manager.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    func testIsEnabledReflectsServiceStatus() {
        let service = FakeLaunchAtLoginService()
        let manager = LaunchAtLoginManager(service: service)

        service.status = .enabled
        XCTAssertTrue(manager.isEnabled)

        service.status = .notRegistered
        XCTAssertFalse(manager.isEnabled)
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginManaging {
    var status: SMAppService.Status = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }
}
