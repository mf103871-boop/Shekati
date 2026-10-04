import Foundation
import CryptoKit
import CommonCrypto
import Security

enum EncryptedBackup {
    // File contains a versioned authenticated header, random salt, and AES-GCM ciphertext.
    // The UTF-8 JSON exists in memory only and is never written to a temporary file.
    private static let magic = Data("SHKBAK01".utf8)
    private static let iterations: UInt32 = 600_000
    private static let maximumFileBytes = 256_000_000

    static func encrypt(_ payload: ChequeBackupPayload, password: String) throws -> Data {
        guard password.count >= 10, password.utf8.count <= 1_024 else { throw ChequeTransferError.passwordTooShort }
        try payload.validate()
        try validateEstimatedSize(payload)
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in SecRandomCopyBytes(kSecRandomDefault, 16, bytes.baseAddress!) }
        guard status == errSecSuccess else { throw ChequeTransferError.invalidFile }
        let key = try deriveKey(password: password, salt: salt, rounds: iterations)
        let header = makeHeader(salt: salt, rounds: iterations)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var plaintext = try encoder.encode(payload)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard plaintext.count <= maximumFileBytes - 56 else { throw ChequeTransferError.invalidFile }
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let sealed = box.combined else { throw ChequeTransferError.invalidFile }
        return header + sealed
    }

    static func validateEstimatedSize(_ payload: ChequeBackupPayload) throws {
        // Base64 expands images; reserve space for JSON and encryption before allocation.
        // An oversized photo archive must fail safely rather than allocate a huge JSON buffer.
        var estimate = 1_024
        for entry in payload.records {
            let value = entry.snapshot
            let textBytes = [value.number, value.bank, value.branch, value.party, value.accountReference, value.notes]
                .reduce(0) { $0 + $1.utf8.count }
            let imageBytes = (entry.frontImageData?.count ?? 0) + (entry.backImageData?.count ?? 0)
            let next = estimate.addingReportingOverflow(imageBytes + textBytes + 4_096)
            guard !next.overflow, next.partialValue <= 160_000_000 else { throw ChequeTransferError.invalidFile }
            estimate = next.partialValue
        }
    }

    static func decrypt(_ data: Data, password: String) throws -> ChequeBackupPayload {
        guard data.count >= 56, data.count <= maximumFileBytes, data.prefix(8) == magic else {
            throw ChequeTransferError.invalidFile
        }
        let salt = data.subdata(in: 8..<24)
        let rounds = data[24..<28].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        // Fixed bounds prevent a hostile file from requesting an excessive KDF workload.
        guard rounds == iterations, password.utf8.count <= 1_024 else { throw ChequeTransferError.invalidFile }
        let key = try deriveKey(password: password, salt: salt, rounds: rounds)
        var plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(28))
            plaintext = try AES.GCM.open(box, using: key, authenticating: data.prefix(28))
        } catch { throw ChequeTransferError.incorrectPassword }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let payload: ChequeBackupPayload
        do { payload = try decoder.decode(ChequeBackupPayload.self, from: plaintext) }
        catch { throw ChequeTransferError.invalidRecords }
        try payload.validate()
        return payload
    }

    private static func makeHeader(salt: Data, rounds: UInt32) -> Data {
        magic + salt + Data([UInt8(rounds >> 24), UInt8((rounds >> 16) & 255),
                             UInt8((rounds >> 8) & 255), UInt8(rounds & 255)])
    }

    private static func deriveKey(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        var passwordBytes = Data(password.utf8)
        var derived = Data(count: 32)
        defer {
            passwordBytes.resetBytes(in: 0..<passwordBytes.count)
            derived.resetBytes(in: 0..<derived.count)
        }
        let passwordLength = passwordBytes.count
        let saltLength = salt.count
        let result: Int32 = derived.withUnsafeMutableBytes { output in
            passwordBytes.withUnsafeBytes { passwordPointer in
                salt.withUnsafeBytes { saltPointer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                        passwordPointer.bindMemory(to: Int8.self).baseAddress, passwordLength,
                                        saltPointer.bindMemory(to: UInt8.self).baseAddress, saltLength,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                        output.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        guard result == kCCSuccess else { throw ChequeTransferError.invalidFile }
        return SymmetricKey(data: derived)
    }
}
