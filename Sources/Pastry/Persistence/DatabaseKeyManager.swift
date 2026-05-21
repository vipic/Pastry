import CryptoKit
import Darwin
import Foundation
import IOKit
import OSLog
import Security

// MARK: - SQLCipher 密钥管理

struct DatabaseKeyManager {
    static let prefersFileKeyStorage = true

    private static let keychainService = "com.nekutai.pastry.dbkey"
    private static let keychainAccount = "clips.db"

    private let dbPath: String
    private let log: Logger

    private var keyFilePath: String { dbPath + ".key" }

    init(dbPath: String, log: Logger) {
        self.dbPath = dbPath
        self.log = log
    }

    /// 获取或创建 256-bit 加密密钥（文件密钥为主，Keychain 仅作为旧版本迁移来源）。
    func getOrCreateKey() -> Data {
        if let fileKey = readKeyFromFile() { return fileKey }

        if let key = readKeyFromKeychain() {
            writeKeyToFile(key)
            return key
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let newKey = Data(keyBytes)
        writeKeyToFile(newKey)
        return newKey
    }

    private func readKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let keyData = result as? Data else { return nil }
        return keyData
    }

    // MARK: 文件密钥存储（设备派生 KEK，AES-256-GCM 加密）

    private func readKeyFromFile() -> Data? {
        guard FileManager.default.fileExists(atPath: keyFilePath),
              let sealed = try? Data(contentsOf: URL(fileURLWithPath: keyFilePath)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let key = try? AES.GCM.open(box, using: Self.deviceKEK())
        else { return nil }
        return Data(key)
    }

    private func writeKeyToFile(_ key: Data) {
        do {
            let box = try AES.GCM.seal(key, using: Self.deviceKEK())
            guard let sealed = box.combined else {
                log.error("AES-GCM seal 失败")
                return
            }
            try sealed.write(to: URL(fileURLWithPath: keyFilePath), options: .atomic)
            chmod(keyFilePath, 0o600)
        } catch {
            log.error("密钥文件写入失败: \(error.localizedDescription)")
        }
    }

    /// 从设备硬件标识派生密钥加密密钥（同一设备永远相同，跨设备无法复现）。
    private static func deviceKEK() -> SymmetricKey {
        guard let salt = "com.nekutai.pastry.kek".data(using: .utf8),
              let material = deviceIdentity().data(using: .utf8),
              let info = "pastry-db-key".data(using: .utf8)
        else {
            return SymmetricKey(data: Data(repeating: 0, count: 32))
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    /// 收集设备唯一标识（IOPlatformUUID，重装系统不变）。
    private static func deviceIdentity() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { if platformExpert != 0 { IOObjectRelease(platformExpert) } }

        guard platformExpert != 0,
              let uuid = IORegistryEntryCreateCFProperty(
                platformExpert, kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault, 0
              )?.takeRetainedValue() as? String
        else { return "pastry-fallback-identity" }

        return uuid
    }
}
