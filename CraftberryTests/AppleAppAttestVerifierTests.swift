import Foundation
import CryptoKit
import Security
import XCTest
@testable import CraftberryCore

final class AppleAppAttestVerifierTests: XCTestCase {
    func testValidAttestationFixtureValidatesCertificateNonceAppIDKeyAndEnvironment() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(rootCertificateDER: fixture.rootDER, allowedBundleVersions: ["1.0"])

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
        XCTAssertFalse(verified.receipt.isEmpty)
    }

    func testAttestationRejectsWrongChallengeAppIDKeyIDAndEnvironment() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(rootCertificateDER: fixture.rootDER, allowedBundleVersions: ["1.0"])

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
        let verifier = AppleAppAttestVerifier(rootCertificateDER: Data(repeating: 0, count: fixture.rootDER.count))
        await assertInvalid(.invalidCertificateChain) {
            try await verifier.verifyAttestation(
                object: fixture.attestation,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }

        let versionRestricted = AppleAppAttestVerifier(rootCertificateDER: fixture.rootDER, allowedBundleVersions: ["2.0"])
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

    func testAttestationRequiresExtensionFlagAndEnvironmentSpecificValidationCategory() async throws {
        let fixture = try fixture()
        let verifier = AppleAppAttestVerifier(rootCertificateDER: fixture.rootDER)

        await assertInvalid(.invalidExtensions) {
            try await verifier.verifyAttestation(
                object: fixture.wrongValidationCategory,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }
        await assertInvalid(.invalidAuthenticatorFlags) {
            try await verifier.verifyAttestation(
                object: fixture.missingExtensionFlag,
                keyID: fixture.keyID,
                challenge: fixture.challenge,
                expectedAppIdentifier: fixture.appIdentifier,
                expectedEnvironment: .development
            )
        }
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

    private func assertionObject(
        signedBy privateKey: SecKey,
        clientData: Data,
        appIdentifier: String,
        counter: UInt32,
        bundleVersion: String,
        doubleHashNonce: Bool = false
    ) throws -> Data {
        var authenticatorData = Data(SHA256.hash(data: Data(appIdentifier.utf8)))
        authenticatorData.append(0x80)
        authenticatorData.append(contentsOf: [
            UInt8((counter >> 24) & 0xFF),
            UInt8((counter >> 16) & 0xFF),
            UInt8((counter >> 8) & 0xFF),
            UInt8(counter & 0xFF)
        ])
        var extensions = Data([0xA2])
        extensions.append(cborText("apple_validation_category_01"))
        extensions.append(cborUnsigned(3))
        extensions.append(cborText("apple_bundle_version_01"))
        extensions.append(cborText(bundleVersion))
        authenticatorData.append(extensions)
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
            throw signingError?.takeRetainedValue() ?? AppleAppAttestVerificationError.invalidAssertionSignature as CFError
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
            throw error?.takeRetainedValue() ?? AppleAppAttestVerificationError.invalidAssertionSignature as CFError
        }
        return (privateKey, publicKey)
    }

    private func externalRepresentation(of key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
            throw error?.takeRetainedValue() ?? AppleAppAttestVerificationError.invalidAssertionSignature as CFError
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
        return Fixture(
            attestation: try Data(contentsOf: bundleURL.appending(path: "valid-attestation.cbor")),
            wrongValidationCategory: try Data(contentsOf: bundleURL.appending(path: "wrong-validation-category-attestation.cbor")),
            missingExtensionFlag: try Data(contentsOf: bundleURL.appending(path: "missing-extension-flag-attestation.cbor")),
            rootDER: try Data(contentsOf: bundleURL.appending(path: "test-root.der")),
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
    let challenge: Data
    let keyID: String
    let appIdentifier: String
}
