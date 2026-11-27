import Foundation
import XCTest
#if canImport(CraftberryCore)
@testable import CraftberryCore
#else
@testable import Craftberry
#endif

final class OpenAIResponsesClientTests: XCTestCase {
    func testBackendClientPostsVersionedIntentAndAssemblesReadyProjectLocally() async throws {
        let fixture = try generationFixture()
        let (status, body) = try fixtureScenario("ready", in: fixture)
        let fixtureRequest = try XCTUnwrap(fixture["request"] as? [String: Any])
        let prompt = try XCTUnwrap(fixtureRequest["prompt"] as? String)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            _ = recorder.record(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let identity = identity()
        let client = backendClient(identity: identity)
        let generation = try await client.generateProject(from: prompt)

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(generation.project?.displayName, "Harbor")
        XCTAssertEqual(generation.project?.id, identity.projectID)
        XCTAssertEqual(generation.project?.packUUIDs, identity.packUUIDs)
        let request = try XCTUnwrap(recorder.request(at: 0))
        XCTAssertEqual(request.url?.path, fixture["path"] as? String)
        XCTAssertEqual(request.httpMethod, fixture["method"] as? String)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer runtime-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let requestBody = try XCTUnwrap(recorder.body(at: 0))
        let decodedRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual(decodedRequest["intentVersion"] as? Int, fixtureRequest["intentVersion"] as? Int)
        XCTAssertEqual(decodedRequest["profileID"] as? String, fixtureRequest["profileID"] as? String)
        XCTAssertEqual(decodedRequest["prompt"] as? String, fixtureRequest["prompt"] as? String)
    }

    func testBackendClientReturnsUnsupportedFixtureWithoutProject() async throws {
        let (status, body) = try fixtureScenario("unsupported", in: generationFixture())
        URLProtocolStub.store.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        let generation = try await backendClient().generateProject(from: "Build something outside the profile")

        XCTAssertEqual(generation.outcome, .unsupported)
        XCTAssertNil(generation.project)
        XCTAssertEqual(generation.message, "This add-on needs a feature outside the active profile.")
    }

    func testBackendClientMapsUnauthorizedFixture() async throws {
        try await assertBackendFailure(scenario: "unauthorized", expected: .unauthorized)
    }

    func testBackendClientMapsQuotaFixture() async throws {
        try await assertBackendFailure(scenario: "quota", expected: .quotaExceeded)
    }

    func testBackendClientMapsServiceFailureFixture() async throws {
        try await assertBackendFailure(scenario: "serviceFailure", expected: .serviceUnavailable)
    }

    func testBackendClientRejectsUnconfiguredOrNonHTTPSEndpointBeforeFetchingCredential() async throws {
        let provider = CredentialProviderSpy(token: "runtime-test-token")
        let unconfigured = BackendGenerationClient(baseURL: nil, credentialProvider: provider)
        do {
            _ = try await unconfigured.generateProject(from: "prompt")
            XCTFail("Expected an unconfigured endpoint to fail")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .endpointNotConfigured)
        }
        let requestsAfterMissingURL = await provider.requestCount()
        XCTAssertEqual(requestsAfterMissingURL, 0)

        let insecure = BackendGenerationClient(baseURL: URL(string: "http://generation.test"), credentialProvider: provider)
        do {
            _ = try await insecure.generateProject(from: "prompt")
            XCTFail("Expected a non-HTTPS endpoint to fail")
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, .invalidEndpoint)
        }
        let requestsAfterInsecureURL = await provider.requestCount()
        XCTAssertEqual(requestsAfterInsecureURL, 0)
    }

    func testClientAssemblesHostileEntitySetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A hostile creature pack.","materialHostileEntitySet":{"materialName":"Azure","color":"red","sourceItem":"diamond","sourceCount":4,"health":24}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let stableIdentity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { stableIdentity })

        let generation = try await client.generateProject(from: "A hostile Azure creature that attacks players")

        XCTAssertEqual(generation.project?.entities.first?.archetype, .hostile)
        XCTAssertEqual(generation.project?.entities.first?.health, 24)
    }

    func testClientAssemblesMusicRecordSetFromTypedStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A dreamy music record.","musicRecordSet":{"title":"First Light","color":"cyan","style":"dreamy"}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "Make a dreamy cyan record called First Light")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(generation.project?.items.first?.displayName, "First Light")
        XCTAssertEqual(generation.project?.items.first?.traits.musicRecord?.style, .dreamy)
        XCTAssertEqual(generation.project?.recipes.first?.pattern, ["DDD", "DRD", "DDD"])
    }

    func testClientAssemblesMaterialWeaponSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"attackBonus":10,"durability":500}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot and matching weapon set")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Sword", "Azure Dagger", "Azure Spear", "Azure Hammer"])
        XCTAssertEqual(generation.project?.recipes.count, 4)
    }

    func testClientAssemblesMaterialToolSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":null,"materialToolSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"attackBonus":10,"durability":500},"materialWeaponSet":null}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot and matching tool set")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Sword", "Azure Pickaxe", "Azure Axe", "Azure Shovel", "Azure Hoe"])
        XCTAssertEqual(generation.project?.recipes.count, 5)
    }

    func testClientAssemblesMaterialArmorSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":null,"materialArmorSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"protection":15,"durability":500}}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot and matching armor set")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Helmet", "Azure Chestplate", "Azure Leggings", "Azure Boots"])
        XCTAssertEqual(generation.project?.recipes.count, 4)
        XCTAssertEqual(generation.project?.items.compactMap { $0.traits.armor?.protection }, [2, 6, 5, 2])
    }

    func testClientAssemblesMaterialSwordSetFromStructuredIntent() async throws {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":null,"materialSwordSet":{"materialName":"Azure","color":"blue","sourceItem":"diamond","sourceCount":4,"swordDisplayName":null,"attackBonus":10,"durability":500},"materialToolSet":null,"materialWeaponSet":null}
        """
        let responseData = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": structuredText]]]]])
        URLProtocolStub.store.setHandler { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)), responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let identity = identity()
        let client = OpenAIResponsesClient(apiKey: "test-key", session: URLSession(configuration: configuration), identityGenerator: { identity })

        let generation = try await client.generateProject(from: "An Azure ingot from four diamonds and a sword")

        XCTAssertEqual(generation.project?.items.map(\.displayName), ["Azure Ingot", "Azure Sword"])
        XCTAssertEqual(generation.project?.shapelessRecipes.first?.ingredients.count, 4)
    }
    func testClientAssemblesAStableProjectFromStructuredIntent() async throws {
        let identity = AddOnProjectIdentity(
            projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            namespace: "craftberry",
            contentSuffix: "a1b2c3",
            packUUIDs: PackUUIDs(
                behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
            )
        )
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":{"displayName":"Azure Sword","color":"blue","attackBonus":20,"durability":500,"craftingIngredient":"diamond"},"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":null}
        """
        let responseData = try JSONSerialization.data(withJSONObject: [
            "output": [[
                "content": [["type": "output_text", "text": structuredText]]
            ]]
        ])
        URLProtocolStub.store.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, responseData)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenAIResponsesClient(
            apiKey: "test-key",
            session: URLSession(configuration: configuration),
            identityGenerator: { identity }
        )

        let generation = try await client.generateProject(from: "A blue diamond sword")

        XCTAssertEqual(generation.outcome, .ready)
        XCTAssertEqual(generation.message, "Ready to build.")
        XCTAssertEqual(generation.project?.shortDescription, "A compact custom pack overview.")
        XCTAssertEqual(generation.project?.id, identity.projectID)
        XCTAssertEqual(generation.project?.packUUIDs, identity.packUUIDs)
        XCTAssertEqual(generation.project?.items.first?.id, ContentID("azure_sword_a1b2c3"))
    }

    func testClientMakesOneRepairAttemptAfterSemanticValidationFails() async throws {
        let invalidResponse = try responseData(attackBonus: 31)
        let repairedResponse = try responseData(attackBonus: 20)
        let recorder = RequestRecorder()
        URLProtocolStub.store.setHandler { request in
            let requestNumber = recorder.record(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, requestNumber == 1 ? invalidResponse : repairedResponse)
        }
        defer { URLProtocolStub.store.setHandler(nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenAIResponsesClient(
            apiKey: "test-key",
            session: URLSession(configuration: configuration),
            identityGenerator: {
                AddOnProjectIdentity(
                    projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
                    namespace: "craftberry",
                    contentSuffix: "a1b2c3",
                    packUUIDs: PackUUIDs(
                        behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                        behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                        resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
                        resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!
                    )
                )
            }
        )

        let generation = try await client.generateProject(from: "A blue diamond sword")

        XCTAssertEqual(generation.project?.items.first?.traits.combat?.attackBonus, 20)
        XCTAssertEqual(recorder.count, 2)
        let repairBody = try XCTUnwrap(recorder.body(at: 1))
        XCTAssertTrue(String(decoding: repairBody, as: UTF8.self).contains("Attack bonus must be between 1 and 30."))
    }

    private func responseData(attackBonus: Int) throws -> Data {
        let structuredText = """
        {"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A compact custom pack overview.","sword":{"displayName":"Azure Sword","color":"blue","attackBonus":\(attackBonus),"durability":500,"craftingIngredient":"diamond"},"materialSwordSet":null,"materialToolSet":null,"materialWeaponSet":null}
        """
        return try JSONSerialization.data(withJSONObject: [
            "output": [[
                "content": [["type": "output_text", "text": structuredText]]
            ]]
        ])
    }

    private func backendClient(identity: AddOnProjectIdentity = .generate()) -> BackendGenerationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return BackendGenerationClient(
            baseURL: URL(string: "https://generation.test"),
            credentialProvider: CredentialProviderSpy(token: "runtime-test-token"),
            session: URLSession(configuration: configuration),
            identityGenerator: { identity }
        )
    }

    private func assertBackendFailure(
        scenario: String,
        expected: BackendGenerationClientError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let (status, body) = try fixtureScenario(scenario, in: generationFixture())
        URLProtocolStub.store.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, body)
        }
        defer { URLProtocolStub.store.setHandler(nil) }

        do {
            _ = try await backendClient().generateProject(from: "Craft a cyan diamond sword named Harbor.")
            XCTFail("Expected backend error \(expected)", file: file, line: line)
        } catch let error as BackendGenerationClientError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func generationFixture() throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "GenerationV1", withExtension: "json"))
        let data = try Data(contentsOf: fixtureURL)
        #else
        let data = Data(Self.generationFixtureFallback.utf8)
        #endif
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureScenario(_ name: String, in fixture: [String: Any]) throws -> (Int, Data) {
        let responses = try XCTUnwrap(fixture["responses"] as? [String: [String: Any]])
        let scenario = try XCTUnwrap(responses[name])
        let status = try XCTUnwrap(scenario["status"] as? Int)
        let body = try XCTUnwrap(scenario["body"])
        return (status, try JSONSerialization.data(withJSONObject: body))
    }

    #if !SWIFT_PACKAGE
    private static let generationFixtureFallback = #"""
    {
      "method":"POST","path":"/v1/generate",
      "request":{"intentVersion":1,"profileID":"bedrock-stable-1.26.30","prompt":"Craft a cyan diamond sword named Harbor."},
      "responses":{
        "ready":{"status":200,"body":{"schemaVersion":1,"outcome":"ready","message":"Ready to build.","shortDescription":"A cyan sword crafted from diamonds.","sword":{"displayName":"Harbor","color":"cyan","attackBonus":12,"durability":600,"craftingIngredient":"diamond"}}},
        "unsupported":{"status":200,"body":{"schemaVersion":1,"outcome":"unsupported","message":"This add-on needs a feature outside the active profile."}},
        "unauthorized":{"status":401,"body":{"error":"unauthorized"}},
        "quota":{"status":429,"body":{"error":"quota_exceeded"}},
        "serviceFailure":{"status":503,"body":{"error":"service_unavailable"}}
      }
    }
    """#
    #endif

    private func identity() -> AddOnProjectIdentity {
        AddOnProjectIdentity(projectID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, namespace: "craftberry", contentSuffix: "a1b2c3", packUUIDs: PackUUIDs(behaviorHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, behaviorModule: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, resourceHeader: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, resourceModule: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!))
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static let store = URLProtocolStubStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.store.handle(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor CredentialProviderSpy: RuntimeGenerationCredentialProvider {
    private let token: String
    private var requests = 0

    init(token: String) {
        self.token = token
    }

    func requestCount() -> Int {
        requests
    }

    func bearerToken() async throws -> String {
        requests += 1
        return token
    }
}

private final class URLProtocolStubStore: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let handler = handler
        lock.unlock()
        guard let handler else { throw LLMClientError.invalidResponse }
        return try handler(request)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var bodies: [Data?] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func record(_ request: URLRequest) -> Int {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        bodies.append(body)
        return requests.count
    }

    func body(at index: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return bodies[index]
    }

    func request(at index: Int) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
