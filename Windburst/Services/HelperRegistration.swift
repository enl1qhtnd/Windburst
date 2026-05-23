import Foundation
import AppKit
import Security
import ServiceManagement
import WindburstShared

enum HelperRegistrationStatus: Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
    case failed(String)

    var isOperational: Bool {
        switch self {
        case .enabled:
            return true
        default:
            return false
        }
    }

    var userFacingDescription: String {
        switch self {
        case .notRegistered:
            if HelperRegistration.usesManualRegistrationPath() {
                return "Helper is not installed yet. Click Register Helper — macOS will ask for your administrator password."
            }
            return "Helper is not registered yet."
        case .requiresApproval:
            return "Helper is registered but needs approval in System Settings → General → Login Items & Extensions → Background Items."
        case .enabled:
            return "Helper is installed and running."
        case .notFound:
            return "WindburstHelper is missing from the app bundle. Rebuild with ./scripts/build.sh or Xcode."
        case .failed(let message):
            return message
        }
    }
}

enum HelperRegistration {
    private static let plistName = "com.windburst.helper.plist"
    private static let launchDaemonPath = "/Library/LaunchDaemons/com.windburst.helper.plist"

    static func bundledHelperURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "WindburstHelper") {
            return url
        }
        let macOS = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/WindburstHelper")
        if FileManager.default.isExecutableFile(atPath: macOS.path) {
            return macOS
        }
        let resources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/WindburstHelper")
        if FileManager.default.isExecutableFile(atPath: resources.path) {
            return resources
        }
        return nil
    }

    static func bundledDaemonPlistURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(plistName)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// True when SMAppService cannot manage this build (ad-hoc / unsigned) and we install via launchctl instead.
    static func usesManualRegistrationPath() -> Bool {
        guard bundledHelperURL() != nil else { return false }

        if CodeSignature.isAdHocSigned(at: Bundle.main.bundleURL) {
            return true
        }

        if #available(macOS 13.0, *) {
            // SMAppService returns .notFound for builds it cannot manage, even if the plist file exists on disk.
            return SMAppService.daemon(plistName: plistName).status == .notFound
        }

        return true
    }

    static func currentStatus() -> HelperRegistrationStatus {
        if isManualDaemonLoaded() {
            return .enabled
        }

        guard bundledHelperURL() != nil else {
            return .notFound
        }

        if usesManualRegistrationPath() {
            return .notRegistered
        }

        guard bundledDaemonPlistURL() != nil else {
            return .notFound
        }

        if #available(macOS 13.0, *) {
            switch SMAppService.daemon(plistName: plistName).status {
            case .notRegistered:
                return .notRegistered
            case .requiresApproval:
                return .requiresApproval
            case .enabled:
                return .enabled
            case .notFound:
                return .notRegistered
            @unknown default:
                return .failed("Unknown SMAppService status.")
            }
        }

        return .notRegistered
    }

    static func register() async -> HelperRegistrationStatus {
        guard bundledHelperURL() != nil else {
            return .failed("WindburstHelper binary is missing from the app bundle. Rebuild Windburst.")
        }

        if usesManualRegistrationPath() {
            return await registerManually()
        }

        guard bundledDaemonPlistURL() != nil else {
            return .failed("Launch daemon plist is missing from the app bundle. Rebuild Windburst.")
        }

        if #available(macOS 13.0, *) {
            return await registerWithSMAppService()
        }

        return await registerManually()
    }

    @available(macOS 13.0, *)
    private static func registerWithSMAppService() async -> HelperRegistrationStatus {
        let service = SMAppService.daemon(plistName: plistName)

        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return await registerManually()
        case .notRegistered:
            break
        @unknown default:
            break
        }

        do {
            try service.register()
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("not permitted")
                || message.localizedCaseInsensitiveContains("not allowed") {
                return await registerManually()
            }
            return .failed(message)
        }

        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .failed("Registration did not complete. Try opening Background Items in System Settings.")
        case .notFound:
            return await registerManually()
        @unknown default:
            return .failed("Unknown SMAppService status after registration.")
        }
    }

    private static func registerManually() async -> HelperRegistrationStatus {
        guard let helperURL = bundledHelperURL() else {
            return .failed("WindburstHelper binary is missing from the app bundle.")
        }

        let plistBody = manualLaunchDaemonPlist(helperPath: helperURL.path)
        let tempPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.windburst.helper.install.plist")
        do {
            try plistBody.write(to: tempPlist, atomically: true, encoding: .utf8)
        } catch {
            return .failed("Could not prepare helper plist: \(error.localizedDescription)")
        }

        let escapedTemp = shellEscape(tempPlist.path)
        let escapedTarget = shellEscape(launchDaemonPath)
        let label = WindburstXPCConstants.helperLabel

        let shell = """
        cp \(escapedTemp) \(escapedTarget) && \
        chown root:wheel \(escapedTarget) && \
        chmod 644 \(escapedTarget) && \
        launchctl bootout system/\(label) 2>/dev/null || true && \
        launchctl bootstrap system \(escapedTarget)
        """

        let appleScript = """
        do shell script "\(shell.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                let script = NSAppleScript(source: appleScript)
                let result = script?.executeAndReturnError(&errorInfo)
                if result != nil, isManualDaemonLoaded() {
                    continuation.resume(returning: .enabled)
                } else if let errorInfo {
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                        ?? "Administrator authorization failed."
                    continuation.resume(returning: .failed(message))
                } else {
                    continuation.resume(returning: .failed("Helper installation failed."))
                }
            }
        }
    }

    static func unregisterManually() async {
        let label = WindburstXPCConstants.helperLabel
        let shell = """
        launchctl bootout system/\(label) 2>/dev/null || true && \
        rm -f \(shellEscape(launchDaemonPath))
        """
        let appleScript = """
        do shell script "\(shell.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
        """
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                var errorInfo: NSDictionary?
                NSAppleScript(source: appleScript)?.executeAndReturnError(&errorInfo)
                continuation.resume()
            }
        }
    }

    private static func isManualDaemonLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(WindburstXPCConstants.helperLabel)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func manualLaunchDaemonPlist(helperPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(WindburstXPCConstants.helperLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperPath)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(WindburstXPCConstants.machServiceName)</key>
                <true/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum CodeSignature {
    static func isAdHocSigned(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return true
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else {
            return true
        }

        if let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return false
        }

        if let authorities = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate], !authorities.isEmpty {
            return false
        }

        return true
    }
}

enum SystemSettingsOpener {
    static func openBackgroundItems() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?BackgroundItems",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.LoginItems"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
