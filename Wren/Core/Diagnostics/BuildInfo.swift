import Foundation

enum BuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Injected by CI via the WREN_GIT_SHA build setting; "local" otherwise.
    static var gitSHA: String {
        let sha = Bundle.main.infoDictionary?["WRENGitSHA"] as? String ?? "unknown"
        return sha.isEmpty ? "unknown" : String(sha.prefix(12))
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "?"
    }

    static var summary: String {
        "\(version) (\(build)) · \(gitSHA)"
    }
}
