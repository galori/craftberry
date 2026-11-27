import Foundation
import CryptoKit
import Security
import XCTest
@testable import CraftberryCore

final class AppleAppAttestVerifierTests: XCTestCase {
    func testValidAttestationFixtureValidatesCertificateNonceAppIDKeyAndEnvironment() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(
            rootCertificateDER: fixture.rootDER,
            receiptRootCertificateDER: fixture.receiptRootDER,
            allowedBundleVersions: ["1.0"],
            clock: { fixture.receiptCreationDate }
        )

        let verified = try await verifier.verifyAttestation(
            object: fixture.attestation,
            keyID: fixture.keyID,
            challenge: fixture.challenge,
            expectedAppIdentifier: fixture.appIdentifier,
            expectedEnvironment: .development
        )

        XCTAssertEqual(verified.keyID, fixture.keyID)
        XCTAssertEqual(verified.appIdentifier, fixture.appIdentifier)
        XCTAssertEqual(verified.environment, .development)
        XCTAssertEqual(verified.bundleVersion, "1.0")
        XCTAssertEqual(verified.publicKey.count, 65)
        XCTAssertEqual(verified.receipt, fixture.receipt)
    }

    func testAttestationRejectsWrongChallengeAppIDKeyIDAndEnvironment() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(
            rootCertificateDER: fixture.rootDER,
            receiptRootCertificateDER: fixture.receiptRootDER,
            allowedBundleVersions: ["1.0"],
            clock: { fixture.receiptCreationDate }
        )

        await assertInvalid(.invalidChallenge) {
            try await verifier.verifyAttestation(
                object: fixture.attestation,
                keyID: fixture.keyID,
                challenge: Data("different-challenge".utf8),
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalid(.invalidAppIdentifier) {
            try await verifier.verifyAttestation(
                object: fixture.attestation,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: "OTHERTEAMID.com.craftberry.app",
                expectedEnvironment: .development
            )
        }
        await assertInvalid(.invalidKeyIdentifier) {
            try await verifier.verifyAttestation(
                object: fixture.attestation,
                keyID: Data(repeating: 0, count: 32).base64EncodedString(),
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalid(.invalidEnvironment) {
            try await verifier.verifyAttestation(
                object: fixture.attestation,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .production
            )
        }
    }

    func testAttestationRejectsUntrustedCertificateChainAndBundleVersion() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(
            rootCertificateDER: Data(repeating: 0, count: fixture.rootDER.count),
            receiptRootCertificateDER: fixture.receiptRootDER,
            clock: { fixture.receiptCreationDate }
        )
        await assertInvalid(.invalidCertificateChain) {
            try await verifier.verifyAttestation(
                object: fixture.attestation,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }

        let versionRestricted = AppleAppAttestVerifier(
            rootCertificateDER: fixture.rootDER,
            receiptRootCertificateDER: fixture.receiptRootDER,
            allowedBundleVersions: ["2.0"],
            clock: { fixture.receiptCreationDate }
        )
        await assertInvalid(.invalidExtensions) {
            try await versionRestricted.verifyAttestation(
                object: fixture.attestation,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }
    }

    func testAttestationAcceptsAppleExtensionMapWithoutFlagAndRejectsWrongValidationCategory() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(
            rootCertificateDER: fixture.rootDER,
            receiptRootCertificateDER: fixture.receiptRootDER,
            clock: { fixture.receiptCreationDate }
        )

        await assertInvalid(.invalidExtensions) {
            try await verifier.verifyAttestation(
                object: fixture.wrongValidationCategory,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }
        let verified = try await verifier.verifyAttestation(
            object: fixture.missingExtensionFlag,
            keyID: fixture.keyID,
            challenge: fixture.challenge,
            expectedAppIdentifier: fixture.appIdentifier,
            expectedEnvironment: .development
        )
        XCTAssertEqual(verified.bundleVersion, "1.0")
    }

    func testApplePublishedNonceExtensionUnwrapsExplicitOctetStringWithoutTrustEvaluation() throws {
        // Apple's published leaf expired before this test date; isolate DER parsing from trust evaluation.
        // Source sample: https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide
        let directory = try XCTUnwrap(Bundle.module.resourceURL?.appending(path: "AppAttest", directoryHint: .isDirectory))
        let appleSampleLeaf = try Data(contentsOf: directory.appending(path: "apple-sample-leaf.der"))
        let expectedNonce = Data([
            0x87, 0xB7, 0xD0, 0x6D, 0x93, 0xA4, 0x29, 0x4E,
            0x46, 0xF0, 0x11, 0xE6, 0x6B, 0x6C, 0xC4, 0x00,
            0xF0, 0xBA, 0xB2, 0x07, 0x29, 0x97, 0x6C, 0x61,
            0x95, 0x80, 0xB4, 0x2A, 0xE6, 0x0B, 0xFF, 0x6E
        ])

        XCTAssertEqual(try AppleAppAttestVerifier.appAttestNonceExtension(in: appleSampleLeaf), expectedNonce)
    }

    func testReceiptValidationChecksCmsSignatureTrustAndAttestationBindings() throws {
        let fixture = try fixture()
        let now = fixture.receiptCreationDate
        let verify = { (receipt: Data, root: Data, appID: String, leaf: Data, clientHash: Data, date: Date) in
            try AppleAppAttestVerifier.verifyAttestationReceipt(
                receipt,
                rootCertificateDER: root,
                expectedAppIdentifier: appID,
                expectedCredentialCertificate: leaf,
                expectedClientDataHash: clientHash,
                now: date
            )
        }
        let clientHash = Data(SHA256.hash(data: fixture.challenge))

        XCTAssertNoThrow(try verify(
            fixture.receipt,
            fixture.receiptRootDER,
            fixture.appIdentifier,
            fixture.leafCertificateDER,
            clientHash,
            now
        ))

        var tamperedReceipt = fixture.receipt
        tamperedReceipt[tamperedReceipt.count - 1] ^= 0x01
        assertInvalidReceipt {
            try verify(tamperedReceipt, fixture.receiptRootDER, fixture.appIdentifier, fixture.leafCertificateDER, clientHash, now)
        }
        assertInvalidReceipt {
            try verify(fixture.receipt, Data(repeating: 0, count: fixture.receiptRootDER.count), fixture.appIdentifier, fixture.leafCertificateDER, clientHash, now)
        }
        assertInvalidReceipt {
            try verify(fixture.receipt, fixture.receiptRootDER, "OTHERTEAMID.com.craftberry.app", fixture.leafCertificateDER, clientHash, now)
        }
        assertInvalidReceipt {
            try verify(fixture.receipt, fixture.receiptRootDER, fixture.appIdentifier, Data("another-key".utf8), clientHash, now)
        }
        assertInvalidReceipt {
            try verify(fixture.receipt, fixture.receiptRootDER, fixture.appIdentifier, fixture.leafCertificateDER, Data(repeating: 0, count: 32), now)
        }
        assertInvalidReceipt {
            try verify(fixture.receipt, fixture.receiptRootDER, fixture.appIdentifier, fixture.leafCertificateDER, clientHash, now.addingTimeInterval(301))
        }
    }

    func testLegacyAuthenticatorDataWithoutNewExtensionsRemainsValid() throws {
        var authenticatorData = Data(repeating: 0x11, count: 32)
        authenticatorData.append(0x40)
        authenticatorData.append(contentsOf: [0, 0, 0, 0])
        authenticatorData.append(Data(repeating: 0x22, count: 16))
        authenticatorData.append(contentsOf: [0, 32])
        authenticatorData.append(Data(repeating: 0x33, count: 32))
        authenticatorData.append(0xA0)

        let parsed = try AppleAppAttestVerifier(rootCertificateDER: Data()).parseAuthenticatorData(authenticatorData)

        XCTAssertNil(parsed.validationCategory)
        XCTAssertNil(parsed.bundleVersion)

        var olderOSData = authenticatorData
        olderOSData[32] |= 0x80
        olderOSData.append(Data([0xA1]) + cborText("older_extension") + cborText("legacy"))
        let olderOSParsed = try AppleAppAttestVerifier(rootCertificateDER: Data()).parseAuthenticatorData(olderOSData)
        XCTAssertNil(olderOSParsed.validationCategory)
        XCTAssertNil(olderOSParsed.bundleVersion)

        var trailingMapWithoutExtensionFlag = authenticatorData
        trailingMapWithoutExtensionFlag.append(
            Data([0xA2]) + cborText("apple_validation_category_01") + Data([0x03])
                + cborText("apple_bundle_version_01") + cborText("1.0")
        )
        let trailingMapParsed = try AppleAppAttestVerifier(rootCertificateDER: Data()).parseAuthenticatorData(
            trailingMapWithoutExtensionFlag
        )
        XCTAssertEqual(trailingMapParsed.validationCategory, 3)
        XCTAssertEqual(trailingMapParsed.bundleVersion, "1.0")
    }

    func testCBORReaderAcceptsDataSlicesWithNonzeroStartIndex() throws {
        let encoded = Data([0xFF, 0xA1, 0x61, 0x78, 0x01, 0xEE])
        let slice = encoded[1..<5]

        let decoded = try CBORReader(data: slice).decodeComplete()

        XCTAssertEqual(decoded.stringKeyedMap?["x"]?.unsigned, 1)
    }

    func testCBORRejectsLengthThatWouldOverflowOffsetAddition() {
        let hostileLength = Data([0x5B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertThrowsError(try CBORReader(data: hostileLength).decodeComplete()) {
            XCTAssertEqual($0 as? AppleAppAttestVerificationError, .malformedObject)
        }
    }

    func testCBORRejectsExcessiveRecursiveNesting() {
        let nestedArrays = Data(repeating: 0x81, count: 256) + Data([0x00])
        XCTAssertThrowsError(try CBORReader(data: nestedArrays).decodeComplete()) {
            XCTAssertEqual($0 as? AppleAppAttestVerificationError, .malformedObject)
        }
    }

    func testAssertionCryptographicallyBindsClientDataAndEnforcesCounterAndExtensions() async throws {
        let appIdentifier = "TESTTEAMID.com.craftberry.app"
        let keyPair = try makeKeyPair()
        let credential = StoredAppAttestCredential(
            installationID: UUID(),
            keyID: "fixture-key-id",
            publicKey: try externalRepresentation(of: keyPair.publicKey),
            appIdentifier: appIdentifier,
            environment: .development,
            bundleVersion: "1.0",
            assertionCounter: 0
        )
        let clientData = Data("canonical signed client data".utf8)
        let verifier = AppleAppAttestVerifier(rootCertificateDER: Data(), allowedBundleVersions: ["1.0"])
        let assertion = try assertionObject(
            signedBy: keyPair.privateKey,
            clientData: clientData,
            appIdentifier: appIdentifier,
            counter: 1,
            bundleVersion: "1.0"
        )

        let result = try await verifier.verifyAssertion(
            object: assertion,
            clientData: clientData,
            credential: credential,
            expectedAppIdentifier: appIdentifier,
            expectedEnvironment: .development
        )
        XCTAssertEqual(result.counter, 1)

        let legacyCredential = StoredAppAttestCredential(
            installationID: UUID(),
            keyID: "legacy-fixture-key-id",
            publicKey: try externalRepresentation(of: keyPair.publicKey),
            appIdentifier: appIdentifier,
            environment: .development,
            bundleVersion: "",
            assertionCounter: 0
        )
        let legacyAssertion = try assertionObject(
            signedBy: keyPair.privateKey,
            clientData: clientData,
            appIdentifier: appIdentifier,
            counter: 1,
            bundleVersion: "1.0",
            includeExtensions: false
        )
        let legacyVerifier = AppleAppAttestVerifier(rootCertificateDER: Data())
        let legacyResult = try await legacyVerifier.verifyAssertion(
            object: legacyAssertion,
            clientData: clientData,
            credential: legacyCredential,
            expectedAppIdentifier: appIdentifier,
            expectedEnvironment: .development
        )
        XCTAssertEqual(legacyResult.counter, 1)
        let legacyExtensionsAssertion = try assertionObject(
            signedBy: keyPair.privateKey,
            clientData: clientData,
            appIdentifier: appIdentifier,
            counter: 1,
            bundleVersion: "1.0",
            includeExtensions: false,
            legacyExtensionMap: true
        )
        let legacyExtensionsResult = try await legacyVerifier.verifyAssertion(
            object: legacyExtensionsAssertion,
            clientData: clientData,
            credential: legacyCredential,
            expectedAppIdentifier: appIdentifier,
            expectedEnvironment: .development
        )
        XCTAssertEqual(legacyExtensionsResult.counter, 1)

        await assertInvalidAssertion(.invalidAssertionSignature) {
            return try await verifier.verifyAssertion(
                object: assertion,
                clientData: Data("different client data".utf8),
                credential: credential,
                expectedAppIdentifier: appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalidAssertion(.invalidAssertionSignature) {
            let forged = try self.assertionObject(
                signedBy: try self.makeKeyPair().privateKey,
                clientData: clientData,
                appIdentifier: appIdentifier,
                counter: 2,
                bundleVersion: "1.0"
            )
            return try await verifier.verifyAssertion(
                object: forged,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalidAssertion(.invalidAssertionSignature) {
            let doubleHashed = try self.assertionObject(
                signedBy: keyPair.privateKey,
                clientData: clientData,
                appIdentifier: appIdentifier,
                counter: 2,
                bundleVersion: "1.0",
                doubleHashNonce: true
            )
            return try await verifier.verifyAssertion(
                object: doubleHashed,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalidAssertion(.invalidAssertionCounter) {
            let replayedCounter = try self.assertionObject(
                signedBy: keyPair.privateKey,
                clientData: clientData,
                appIdentifier: appIdentifier,
                counter: 0,
                bundleVersion: "1.0"
            )
            return try await verifier.verifyAssertion(
                object: replayedCounter,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalidAssertion(.invalidAssertionAppIdentifier) {
            return try await verifier.verifyAssertion(
                object: assertion,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: "OTHERTEAMID.com.craftberry.app",
                expectedEnvironment: .development
            )
        }
        await assertInvalidAssertion(.invalidAssertionExtensions) {
            let wrongVersion = try self.assertionObject(
                signedBy: keyPair.privateKey,
                clientData: clientData,
                appIdentifier: appIdentifier,
                counter: 2,
                bundleVersion: "2.0"
            )
            return try await verifier.verifyAssertion(
                object: wrongVersion,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: appIdentifier,
                expectedEnvironment: .development
            )
        }
    }

    func testAssertionAcceptsAnAllowedBundleVersionAfterAppUpdate() async throws {
        let appIdentifier = "TESTTEAMID.com.craftberry.app"
        let keyPair = try makeKeyPair()
        let credential = StoredAppAttestCredential(
            installationID: UUID(),
            keyID: "fixture-key-id",
            publicKey: try externalRepresentation(of: keyPair.publicKey),
            appIdentifier: appIdentifier,
            environment: .development,
            bundleVersion: "1.0",
            assertionCounter: 0
        )
        let clientData = Data("updated app assertion".utf8)
        let assertion = try assertionObject(
            signedBy: keyPair.privateKey,
            clientData: clientData,
            appIdentifier: appIdentifier,
            counter: 1,
            bundleVersion: "2.0"
        )
        let verifier = AppleAppAttestVerifier(rootCertificateDER: Data(), allowedBundleVersions: ["1.0", "2.0"])

        let result = try await verifier.verifyAssertion(
            object: assertion,
            clientData: clientData,
            credential: credential,
            expectedAppIdentifier: appIdentifier,
            expectedEnvironment: .development
        )

        XCTAssertEqual(result.counter, 1)
    }

    func testConfiguredAllowlistRequiresVersionMetadataUnlessLegacyIsExplicitlyAllowed() async throws {
        let appIdentifier = "TESTTEAMID.com.craftberry.app"
        let keyPair = try makeKeyPair()
        let credential = StoredAppAttestCredential(
            installationID: UUID(),
            keyID: "legacy-fixture-key-id",
            publicKey: try externalRepresentation(of: keyPair.publicKey),
            appIdentifier: appIdentifier,
            environment: .development,
            bundleVersion: "",
            assertionCounter: 0
        )
        let clientData = Data("legacy assertion".utf8)
        let assertion = try assertionObject(
            signedBy: keyPair.privateKey,
            clientData: clientData,
            appIdentifier: appIdentifier,
            counter: 1,
            bundleVersion: "1.0",
            includeExtensions: false
        )
        let strictVerifier = AppleAppAttestVerifier(rootCertificateDER: Data(), allowedBundleVersions: ["1.0"])
        await assertInvalidAssertion(.invalidAssertionExtensions) {
            try await strictVerifier.verifyAssertion(
                object: assertion,
                clientData: clientData,
                credential: credential,
                expectedAppIdentifier: appIdentifier,
                expectedEnvironment: .development
            )
        }

        let legacyVerifier = AppleAppAttestVerifier(
            rootCertificateDER: Data(),
            allowedBundleVersions: ["1.0", "legacy-no-bundle-version"]
        )
        let legacyResult = try await legacyVerifier.verifyAssertion(
            object: assertion,
            clientData: clientData,
            credential: credential,
            expectedAppIdentifier: appIdentifier,
            expectedEnvironment: .development
        )
        XCTAssertEqual(legacyResult.counter, 1)
    }

    private func assertInvalidAssertion(
        _ expected: AppleAppAttestVerificationError,
        operation: () async throws -> VerifiedAppAttestAssertion,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected assertion verification to fail with \(expected)", file: file, line: line)
        } catch let error as AppleAppAttestVerificationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected assertion verifier error: \(error)", file: file, line: line)
        }
    }

    private func assertInvalidReceipt(
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? AppleAppAttestVerificationError, .invalidReceipt, file: file, line: line)
        }
    }

    private func assertionObject(
        signedBy privateKey: SecKey,
        clientData: Data,
        appIdentifier: String,
        counter: UInt32,
        bundleVersion: String,
        doubleHashNonce: Bool = false,
        includeExtensions: Bool = true,
        legacyExtensionMap: Bool = false
    ) throws -> Data {
        var authenticatorData = Data(SHA256.hash(data: Data(appIdentifier.utf8)))
        authenticatorData.append(includeExtensions || legacyExtensionMap ? 0x80 : 0)
        authenticatorData.append(contentsOf: [
            UInt8((counter >> 24) & 0xFF),
            UInt8((counter >> 16) & 0xFF),
            UInt8((counter >> 8) & 0xFF),
            UInt8(counter & 0xFF)
        ])
        if legacyExtensionMap {
            authenticatorData.append(Data([0xA1]) + cborText("older_extension") + cborText("legacy"))
        } else if includeExtensions {
            var extensions = Data([0xA2])
            extensions.append(cborText("apple_validation_category_01"))
            extensions.append(cborUnsigned(3))
            extensions.append(cborText("apple_bundle_version_01"))
            extensions.append(cborText(bundleVersion))
            authenticatorData.append(extensions)
        }
        let clientDataHash = Data(SHA256.hash(data: clientData))
        let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
        let signedDigest = doubleHashNonce ? Data(SHA256.hash(data: nonce)) : nonce
        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureDigestX962SHA256,
            signedDigest as CFData,
            &signingError
        ) else {
            if let signingError { throw signingError.takeRetainedValue() }
            throw NSError(domain: "AppleAppAttestVerifierTests", code: 1)
        }
        var encoded = Data([0xA2])
        encoded.append(cborText("signature"))
        encoded.append(cborBytes(signature as Data))
        encoded.append(cborText("authenticatorData"))
        encoded.append(cborBytes(authenticatorData))
        return encoded
    }

    private func makeKeyPair() throws -> (privateKey: SecKey, publicKey: SecKey) {
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256
        ] as CFDictionary, &error), let publicKey = SecKeyCopyPublicKey(privateKey) else {
            if let error { throw error.takeRetainedValue() }
            throw NSError(domain: "AppleAppAttestVerifierTests", code: 2)
        }
        return (privateKey, publicKey)
    }

    private func externalRepresentation(of key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
            if let error { throw error.takeRetainedValue() }
            throw NSError(domain: "AppleAppAttestVerifierTests", code: 3)
        }
        return data as Data
    }

    private func cborText(_ value: String) -> Data { cborBytes(Data(value.utf8), majorType: 3) }
    private func cborBytes(_ value: Data) -> Data { cborBytes(value, majorType: 2) }

    private func cborUnsigned(_ value: UInt8) -> Data {
        guard value >= 24 else { return Data([value]) }
        return Data([0x18, value])
    }

    private func cborBytes(_ value: Data, majorType: UInt8) -> Data {
        var result = Data()
        if value.count < 24 {
            result.append((majorType << 5) | UInt8(value.count))
        } else if value.count <= 255 {
            result.append((majorType << 5) | 24)
            result.append(UInt8(value.count))
        } else {
            result.append((majorType << 5) | 25)
            result.append(UInt8((value.count >> 8) & 0xFF))
            result.append(UInt8(value.count & 0xFF))
        }
        result.append(value)
        return result
    }

    private func assertInvalid(
        _ expected: AppleAppAttestVerificationError,
        operation: () async throws -> VerifiedAppAttestKey,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected App Attest verification to fail with \(expected)", file: file, line: line)
        } catch let error as AppleAppAttestVerificationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected verifier error: \(error)", file: file, line: line)
        }
    }

    private func fixture() throws -> Fixture {
        let bundleURL = try XCTUnwrap(Bundle.module.resourceURL?.appending(path: "AppAttest", directoryHint: .isDirectory))
        let attestation = try Data(contentsOf: bundleURL.appending(path: "valid-attestation.cbor"))
        let attestationMap = try XCTUnwrap(CBORReader(data: attestation).decodeComplete().stringKeyedMap)
        let statement = try XCTUnwrap(attestationMap["attStmt"]?.stringKeyedMap)
        let chain = try XCTUnwrap(statement["x5c"]?.array?.compactMap(\.bytes))
        let receiptDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z"))
        return Fixture(
            attestation: attestation,
            wrongValidationCategory: try Data(contentsOf: bundleURL.appending(path: "wrong-validation-category-attestation.cbor")),
            missingExtensionFlag: try Data(contentsOf: bundleURL.appending(path: "missing-extension-flag-attestation.cbor")),
            rootDER: try Data(contentsOf: bundleURL.appending(path: "test-root.der")),
            receiptRootDER: try Data(contentsOf: bundleURL.appending(path: "receipt-root.der")),
            receipt: try Data(contentsOf: bundleURL.appending(path: "valid-receipt.cms")),
            leafCertificateDER: try XCTUnwrap(chain.first),
            receiptCreationDate: receiptDate,
            challenge: try Data(contentsOf: bundleURL.appending(path: "challenge.bin")),
            keyID: try String(contentsOf: bundleURL.appending(path: "key-id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            appIdentifier: try String(contentsOf: bundleURL.appending(path: "app-id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct Fixture {
    let attestation: Data
    let wrongValidationCategory: Data
    let missingExtensionFlag: Data
    let rootDER: Data
    let receiptRootDER: Data
    let receipt: Data
    let leafCertificateDER: Data
    let receiptCreationDate: Date
    let challenge: Data
    let keyID: String
    let appIdentifier: String
}
