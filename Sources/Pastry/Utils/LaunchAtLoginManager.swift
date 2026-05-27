import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LaunchAtLoginManaging {}

struct LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager(service: SMAppService.mainApp)

    let service: LaunchAtLoginManaging

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    var isEnabled: Bool {
        service.status == .enabled
    }
}
