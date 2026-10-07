import Foundation

// Development installation handoff only. The coordinator supplies the public
// fingerprint from its verified USB enrollment; never discover/import random
// pairing files or overwrite an existing trust pin.
@objc(TKEnrollmentImport) public final class EnrollmentImport: NSObject {
    private static var directory: URL {
        URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/LocalAuthorization",isDirectory:true)
    }
    @objc public static func prepare() -> Bool {
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
                attributes:[.protectionKey:FileProtectionType.complete,.posixPermissions:0o700])
            return true
        } catch { return false }
    }
    // Reinstalling removes preferences while the device-only trust pin can
    // survive. Recover only an exact record named by the trusted USB caller;
    // never enumerate Keychain records or import/replace a pairing identity.
    static func restoreReference(device: String, store: PairingKeychain, defaults: UserDefaults) throws {
        let key = "TKEnrolledDeviceIdentifier"
        if let existing = defaults.object(forKey:key) {
            guard let value = existing as? String, value.isEmpty || value == device else { throw PairingError.authenticationFailed }
        }
        guard try store.load(deviceIdentifier:device) != nil else { throw PairingError.authenticationFailed }
        defaults.set(device,forKey:key)
    }
    @objc public static func restoreReference(device: String) -> String {
        do {
            try restoreReference(device:device,store:PairingKeychain(),defaults:.standard)
            return "Existing authorization reference restored from a verified device-only Keychain record. No trust pin was changed."
        } catch {
            return "Authorization reference recovery rejected; no matching trusted record is available or the current reference conflicts."
        }
    }
    @objc public static func importPending(device: String, fingerprint: String) -> String {
        let file = directory.appendingPathComponent("Enrollment.pending")
        defer { try? FileManager.default.removeItem(at:file) }
        do {
            guard fingerprint.utf8.count == 64,
                  fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw PairingError.malformed }
            let attributes = try FileManager.default.attributesOfItem(atPath:file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0,
                  size.intValue <= PairingEnrollment.maximumSize else { throw PairingError.malformed }
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete,.posixPermissions:0o600],ofItemAtPath:file.path)
            let record = try PairingEnrollment(untrustedData:Data(contentsOf:file))
            let actual = record.fingerprint.map { String(format:"%02x",$0) }.joined()
            guard record.deviceIdentifier == device, actual == fingerprint else { throw PairingError.authenticationFailed }
            try FileManager.default.removeItem(at:file)
            let store = try PairingKeychain()
            try store.insertTrusted(record)
            guard try store.load(deviceIdentifier:device)?.fingerprint == record.fingerprint else { throw PairingError.authenticationFailed }
            UserDefaults.standard.set(device,forKey:"TKEnrolledDeviceIdentifier")
            return "Verified enrollment imported into protected device-only Keychain. Temporary handoff removed. Native authorization is not yet enabled."
        } catch {
            return "Enrollment import rejected; no existing trust pin was replaced."
        }
    }
}
