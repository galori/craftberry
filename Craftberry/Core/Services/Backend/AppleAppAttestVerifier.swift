import CryptoKit
import Foundation
import Security

public enum AppleAppAttestVerificationError: Error, Equatable {
    case malformedObject
    case unsupportedFormat
    case invalidCertificateChain
    case invalidChallenge
    case invalidKeyIdentifier
    case invalidAppIdentifier
    case invalidAuthenticatorFlags
    case invalidEnvironment
    case invalidCounter
    case invalidExtensions
    case missingReceipt
    case invalidAssertionSignature
    case invalidAssertionChallenge
    case invalidAssertionAppIdentifier
    case invalidAssertionCounter
    case invalidAssertionExtensions
}

/// Verifies Apple App Attest key-attestation objects using the Apple App Attestation
/// root CA and the concrete application identity configured by the service host.
public struct AppleAppAttestVerifier: AppAttestVerifying, Sendable {
    private let rootCertificateDER: Data
    private let allowedBundleVersions: Set<String>?

    public init(rootCertificateDER: Data, allowedBundleVersions: Set<String>? = nil) {
        self.rootCertificateDER = rootCertificateDER
        self.allowedBundleVersions = allowedBundleVersions
    }

    public func verifyAttestation(
        object: Data,
        keyID: String,
        challenge: Data,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestKey {
        let root = try CBORReader(data: object).decodeComplete()
        guard let rootMap = root.stringKeyedMap,
              rootMap["fmt"]?.text == "apple-appattest",
              let statement = rootMap["attStmt"]?.stringKeyedMap,
              let chain = statement["x5c"]?.array?.compactMap(\.bytes),
              chain.count >= 2,
              let authenticatorData = rootMap["authData"]?.bytes else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        guard let receipt = statement["receipt"]?.bytes, !receipt.isEmpty else {
            throw AppleAppAttestVerificationError.missingReceipt
        }

        let publicPoint = try verifyCertificateChain(chain)
        let keyBytes = try decodeKeyIdentifier(keyID)
        let publicKeyDigest = Data(SHA256.hash(data: publicPoint))
        guard publicKeyDigest == keyBytes else { throw AppleAppAttestVerificationError.invalidKeyIdentifier }

        let authenticator = try parseAuthenticatorData(authenticatorData)
        guard authenticator.credentialID == keyBytes else {
            throw AppleAppAttestVerificationError.invalidKeyIdentifier
        }
        guard authenticator.rpIDHash == Data(SHA256.hash(data: Data(expectedAppIdentifier.utf8))) else {
            throw AppleAppAttestVerificationError.invalidAppIdentifier
        }
        guard authenticator.counter == 0 else { throw AppleAppAttestVerificationError.invalidCounter }
        guard authenticator.aaguidMatches(expectedEnvironment) else {
            throw AppleAppAttestVerificationError.invalidEnvironment
        }

        let clientDataHash = Data(SHA256.hash(data: challenge))
        let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
        guard let leafCertificate = chain.first,
              try certificateExtension(oid: "1.2.840.113635.100.8.2", in: leafCertificate) == nonce else {
            throw AppleAppAttestVerificationError.invalidChallenge
        }
        guard authenticator.validationCategoryIsAllowed(expectedEnvironment),
              !authenticator.bundleVersion.isEmpty,
              allowedBundleVersions.map({ $0.contains(authenticator.bundleVersion) }) ?? true else {
            throw AppleAppAttestVerificationError.invalidExtensions
        }

        return VerifiedAppAttestKey(
            keyID: keyID,
            publicKey: publicPoint,
            appIdentifier: expectedAppIdentifier,
            environment: expectedEnvironment,
            bundleVersion: authenticator.bundleVersion,
            receipt: receipt
        )
    }

    public func verifyAssertion(
        object: Data,
        clientData: Data,
        credential: StoredAppAttestCredential,
        expectedAppIdentifier: String,
        expectedEnvironment: AppAttestEnvironment
    ) async throws -> VerifiedAppAttestAssertion {
        guard credential.appIdentifier == expectedAppIdentifier,
              credential.environment == expectedEnvironment else {
            throw AppleAppAttestVerificationError.invalidAssertionAppIdentifier
        }
        let root = try CBORReader(data: object).decodeComplete()
        guard let values = root.stringKeyedMap,
              let signatureData = values["signature"]?.bytes,
              let authenticatorData = values["authenticatorData"]?.bytes,
              authenticatorData.count >= 37 else {
            throw AppleAppAttestVerificationError.malformedObject
        }

        let rpIDHash = Data(authenticatorData.prefix(32))
        guard rpIDHash == Data(SHA256.hash(data: Data(expectedAppIdentifier.utf8))) else {
            throw AppleAppAttestVerificationError.invalidAssertionAppIdentifier
        }
        let flags = authenticatorData[32]
        guard flags & 0x40 == 0, flags & 0x80 != 0 else {
            throw AppleAppAttestVerificationError.invalidAuthenticatorFlags
        }
        let counter = authenticatorData[33..<37].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard counter > credential.assertionCounter else {
            throw AppleAppAttestVerificationError.invalidAssertionCounter
        }
        let extensionBytes = Data(authenticatorData.dropFirst(37))
        guard let extensions = try? CBORReader(data: extensionBytes).decodeComplete().stringKeyedMap,
              let validationCategory = extensions["apple_validation_category_01"].flatMap(Self.uint32),
              let bundleVersion = extensions["apple_bundle_version_01"]?.text,
              bundleVersion == credential.bundleVersion,
              allowedBundleVersions.map({ $0.contains(bundleVersion) }) ?? true,
              Self.validationCategory(validationCategory, isAllowedIn: expectedEnvironment) else {
            throw AppleAppAttestVerificationError.invalidAssertionExtensions
        }

        let clientDataHash = Data(SHA256.hash(data: clientData))
        let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
        let publicKeyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ]
        var keyError: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(
            credential.publicKey as CFData,
            publicKeyAttributes as CFDictionary,
            &keyError
        ) else {
            if let keyError { _ = keyError.takeRetainedValue() }
            throw AppleAppAttestVerificationError.invalidAssertionSignature
        }
        var signatureError: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureDigestX962SHA256,
            nonce as CFData,
            signatureData as CFData,
            &signatureError
        ) else {
            if let signatureError { _ = signatureError.takeRetainedValue() }
            throw AppleAppAttestVerificationError.invalidAssertionSignature
        }
        return VerifiedAppAttestAssertion(counter: counter)
    }

    private func verifyCertificateChain(_ chain: [Data]) throws -> Data {
        guard let root = SecCertificateCreateWithData(nil, rootCertificateDER as CFData) else {
            throw AppleAppAttestVerificationError.invalidCertificateChain
        }
        let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard certificates.count == chain.count else {
            throw AppleAppAttestVerificationError.invalidCertificateChain
        }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else {
            throw AppleAppAttestVerificationError.invalidCertificateChain
        }
        guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
            throw AppleAppAttestVerificationError.invalidCertificateChain
        }
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            throw AppleAppAttestVerificationError.invalidCertificateChain
        }
        guard let leaf = chain.first else { throw AppleAppAttestVerificationError.invalidCertificateChain }
        return try publicPoint(inCertificate: leaf)
    }

    private func decodeKeyIdentifier(_ keyID: String) throws -> Data {
        if let value = Data(base64Encoded: keyID), value.count == 32 { return value }
        var normalized = keyID.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized.append(String(repeating: "=", count: (4 - normalized.count % 4) % 4))
        guard let value = Data(base64Encoded: normalized), value.count == 32 else {
            throw AppleAppAttestVerificationError.invalidKeyIdentifier
        }
        return value
    }

    private func publicPoint(inCertificate certificate: Data) throws -> Data {
        let certificateSequence = try DERReader(data: certificate).read(at: 0)
        let certificateFields = try DERReader(data: certificate).children(of: certificateSequence)
        guard let tbs = certificateFields.first else { throw AppleAppAttestVerificationError.malformedObject }
        let tbsFields = try DERReader(data: certificate).children(of: tbs)
        let fields = tbsFields.first?.tag == 0xA0 ? Array(tbsFields.dropFirst()) : tbsFields
        guard fields.count > 5 else { throw AppleAppAttestVerificationError.malformedObject }
        let subjectPublicKeyInfo = fields[5]
        let spkiFields = try DERReader(data: certificate).children(of: subjectPublicKeyInfo)
        guard spkiFields.count == 2 else { throw AppleAppAttestVerificationError.malformedObject }
        let bitString = try DERReader(data: certificate).content(of: spkiFields[1])
        guard bitString.count == 66, bitString.first == 0, bitString[1] == 4 else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        return Data(bitString.dropFirst())
    }

    private func certificateExtension(oid: String, in certificate: Data) throws -> Data? {
        let reader = DERReader(data: certificate)
        let certificateFields = try reader.children(of: reader.read(at: 0))
        guard let tbs = certificateFields.first else { throw AppleAppAttestVerificationError.malformedObject }
        let fields = try reader.children(of: tbs)
        guard let extensions = fields.first(where: { $0.tag == 0xA3 }) else { return nil }
        let explicitFields = try reader.children(of: extensions)
        guard let extensionSequence = explicitFields.first else { return nil }
        for item in try reader.children(of: extensionSequence) where item.tag == 0x30 {
            let components = try reader.children(of: item)
            guard components.count >= 2, try reader.oid(components[0]) == oid else { continue }
            guard let octet = components.first(where: { $0.tag == 0x04 }) else { continue }
            let extensionContents = try reader.content(of: octet)
            let nested = DERReader(data: extensionContents)
            let sequence = try nested.read(at: 0)
            guard sequence.tag == 0x30,
                  let value = try nested.children(of: sequence).first,
                  value.tag == 0x04 else { continue }
            return try nested.content(of: value)
        }
        return nil
    }

    private func parseAuthenticatorData(_ data: Data) throws -> ParsedAuthenticatorData {
        guard data.count >= 55 else { throw AppleAppAttestVerificationError.malformedObject }
        let rpIDHash = Data(data[0..<32])
        let flags = data[32]
        guard flags & 0x40 != 0, flags & 0x80 != 0 else {
            throw AppleAppAttestVerificationError.invalidAuthenticatorFlags
        }
        let counter = data[33..<37].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let aaguid = Data(data[37..<53])
        let credentialLength = Int(data[53..<55].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) })
        let credentialStart = 55
        let credentialEnd = credentialStart + credentialLength
        guard credentialLength == 32, credentialEnd <= data.count else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        let credentialID = Data(data[credentialStart..<credentialEnd])
        let coseReader = CBORReader(data: Data(data[credentialEnd...]))
        let (coseKey, coseBytesUsed) = try coseReader.decodeOne()
        guard coseKey.map != nil else { throw AppleAppAttestVerificationError.malformedObject }
        let extensionData = Data(data[(credentialEnd + coseBytesUsed)...])
        let extensions = try CBORReader(data: extensionData).decodeComplete()
        guard let values = extensions.stringKeyedMap,
              let category = values["apple_validation_category_01"].flatMap(Self.uint32),
              let bundleVersion = values["apple_bundle_version_01"]?.text else {
            throw AppleAppAttestVerificationError.invalidExtensions
        }
        return ParsedAuthenticatorData(
            rpIDHash: rpIDHash,
            counter: counter,
            aaguid: aaguid,
            credentialID: credentialID,
            validationCategory: category,
            bundleVersion: bundleVersion
        )
    }

    private static func uint32(_ value: CBORValue) -> UInt32? {
        if let unsigned = value.unsigned, unsigned <= UInt64(UInt32.max) { return UInt32(unsigned) }
        guard let bytes = value.bytes, bytes.count == 4 else { return nil }
        let bigEndian = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let littleEndian = bytes.enumerated().reduce(UInt32(0)) { partial, element in
            partial | (UInt32(element.element) << UInt32(element.offset * 8))
        }
        return [bigEndian, littleEndian].first(where: { $0 < 7 })
    }

    private static func validationCategory(_ category: UInt32, isAllowedIn environment: AppAttestEnvironment) -> Bool {
        switch environment {
        case .development: category == 3
        case .production: [2, 4, 5].contains(category)
        }
    }
}

private struct ParsedAuthenticatorData {
    let rpIDHash: Data
    let counter: UInt32
    let aaguid: Data
    let credentialID: Data
    let validationCategory: UInt32
    let bundleVersion: String

    func aaguidMatches(_ environment: AppAttestEnvironment) -> Bool {
        switch environment {
        case .development:
            aaguid == Data("appattestdevelop".utf8) || aaguid == Data("appattestsandbox".utf8)
        case .production:
            aaguid == Data("appattest".utf8) + Data(repeating: 0, count: 7)
        }
    }

    func validationCategoryIsAllowed(_ environment: AppAttestEnvironment) -> Bool {
        switch environment {
        case .development:
            validationCategory == 3
        case .production:
            [2, 4, 5].contains(validationCategory)
        }
    }
}

enum CBORValue {
    case unsigned(UInt64)
    case negative(Int64)
    case bytes(Data)
    case text(String)
    case array([CBORValue])
    case map([(CBORValue, CBORValue)])
    case other

    var unsigned: UInt64? { if case .unsigned(let value) = self { value } else { nil } }
    var bytes: Data? { if case .bytes(let value) = self { value } else { nil } }
    var text: String? { if case .text(let value) = self { value } else { nil } }
    var array: [CBORValue]? { if case .array(let value) = self { value } else { nil } }
    var map: [(CBORValue, CBORValue)]? { if case .map(let value) = self { value } else { nil } }
    var stringKeyedMap: [String: CBORValue]? {
        guard let map else { return nil }
        var result: [String: CBORValue] = [:]
        for (key, value) in map {
            guard let key = key.text else { continue }
            result[key] = value
        }
        return result
    }
}

struct CBORReader {
    private static let maximumNestingDepth = 32

    let data: Data
    private var offset = 0

    init(data: Data) { self.data = data }

    func decodeComplete() throws -> CBORValue {
        var reader = self
        let value = try reader.read()
        guard reader.offset == data.count else { throw AppleAppAttestVerificationError.malformedObject }
        return value
    }

    func decodeOne() throws -> (CBORValue, Int) {
        var reader = self
        let value = try reader.read()
        return (value, reader.offset)
    }

    private mutating func read(depth: Int = 0) throws -> CBORValue {
        guard depth <= Self.maximumNestingDepth else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        guard offset < data.count else { throw AppleAppAttestVerificationError.malformedObject }
        let initial = data[offset]
        offset += 1
        let major = initial >> 5
        let additional = initial & 0x1F
        let encodedLength = try readLength(additional)
        switch major {
        case 0: return .unsigned(encodedLength)
        case 1:
            guard encodedLength <= UInt64(Int64.max) else { throw AppleAppAttestVerificationError.malformedObject }
            return .negative(-1 - Int64(encodedLength))
        case 2:
            return .bytes(try readBytes(count: try intLength(encodedLength)))
        case 3:
            guard let text = String(data: try readBytes(count: try intLength(encodedLength)), encoding: .utf8) else {
                throw AppleAppAttestVerificationError.malformedObject
            }
            return .text(text)
        case 4:
            let length = try intLength(encodedLength)
            guard length <= 2_048 else { throw AppleAppAttestVerificationError.malformedObject }
            return .array(try (0..<length).map { _ in try read(depth: depth + 1) })
        case 5:
            let length = try intLength(encodedLength)
            guard length <= 2_048 else { throw AppleAppAttestVerificationError.malformedObject }
            var values: [(CBORValue, CBORValue)] = []
            for _ in 0..<length {
                values.append((try read(depth: depth + 1), try read(depth: depth + 1)))
            }
            return .map(values)
        case 6:
            return try read(depth: depth + 1)
        default:
            return .other
        }
    }

    private mutating func readLength(_ additional: UInt8) throws -> UInt64 {
        switch additional {
        case 0...23: return UInt64(additional)
        case 24: return try readInteger(byteCount: 1)
        case 25: return try readInteger(byteCount: 2)
        case 26: return try readInteger(byteCount: 4)
        case 27: return try readInteger(byteCount: 8)
        default: throw AppleAppAttestVerificationError.malformedObject
        }
    }

    private func intLength(_ value: UInt64) throws -> Int {
        guard value <= UInt64(Int.max) else { throw AppleAppAttestVerificationError.malformedObject }
        return Int(value)
    }

    private mutating func readInteger(byteCount: Int) throws -> UInt64 {
        guard byteCount >= 0, offset <= data.count, byteCount <= data.count - offset else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        var value: UInt64 = 0
        let endOffset = offset + byteCount
        for byte in data[offset..<endOffset] { value = (value << 8) | UInt64(byte) }
        offset += byteCount
        return value
    }

    private mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count, count <= data.count - offset else {
            throw AppleAppAttestVerificationError.malformedObject
        }
        let endOffset = offset + count
        defer { offset += count }
        return Data(data[offset..<endOffset])
    }
}

private struct DERElement {
    let tag: UInt8
    let contentRange: Range<Int>
    let endOffset: Int
}

private struct DERReader {
    let data: Data

    func read(at start: Int) throws -> DERElement {
        guard start + 2 <= data.count else { throw AppleAppAttestVerificationError.malformedObject }
        let tag = data[start]
        var offset = start + 1
        let firstLength = Int(data[offset])
        offset += 1
        let length: Int
        if firstLength & 0x80 == 0 {
            length = firstLength
        } else {
            let lengthBytes = firstLength & 0x7F
            guard lengthBytes > 0, lengthBytes <= 4, offset + lengthBytes <= data.count else {
                throw AppleAppAttestVerificationError.malformedObject
            }
            var decoded = 0
            for byte in data[offset..<(offset + lengthBytes)] { decoded = (decoded << 8) | Int(byte) }
            length = decoded
            offset += lengthBytes
        }
        guard length >= 0, offset + length <= data.count else { throw AppleAppAttestVerificationError.malformedObject }
        return DERElement(tag: tag, contentRange: offset..<(offset + length), endOffset: offset + length)
    }

    func children(of parent: DERElement) throws -> [DERElement] {
        var result: [DERElement] = []
        var offset = parent.contentRange.lowerBound
        while offset < parent.contentRange.upperBound {
            let child = try read(at: offset)
            guard child.endOffset <= parent.contentRange.upperBound else {
                throw AppleAppAttestVerificationError.malformedObject
            }
            result.append(child)
            offset = child.endOffset
        }
        return result
    }

    func content(of element: DERElement) throws -> Data {
        Data(data[element.contentRange])
    }

    func oid(_ element: DERElement) throws -> String {
        guard element.tag == 0x06 else { throw AppleAppAttestVerificationError.malformedObject }
        let bytes = try content(of: element)
        guard let first = bytes.first else { throw AppleAppAttestVerificationError.malformedObject }
        let firstValue = Int(first)
        var components = [min(firstValue / 40, 2), firstValue - min(firstValue / 40, 2) * 40]
        var value = 0
        for byte in bytes.dropFirst() {
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                components.append(value)
                value = 0
            }
        }
        return components.map(String.init).joined(separator: ".")
    }
}
