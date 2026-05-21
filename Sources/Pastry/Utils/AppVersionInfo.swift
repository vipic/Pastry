import Foundation

extension AppVersion {
    static var displayCurrent: String {
        displayCurrent(
            generated: current,
            bundle: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }

    static var displayBuild: String {
        displayBuild(
            generated: build,
            bundle: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    static func displayCurrent(generated: String, bundle: String?) -> String {
        let source = generated == "0.0.0-dev" ? (bundle ?? "1.0") : generated
        return UpdateChecker.displayVersion(source)
    }

    static func displayBuild(generated: String, bundle: String?) -> String {
        generated == "0" ? (bundle ?? "1") : generated
    }
}
