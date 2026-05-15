import Testing
@testable import lnr

@Suite(.serialized)
struct KeychainServiceTests {
    let service = KeychainService(service: "com.lnr.tests")

    init() {
        service.delete()
    }

    @Test func saveAndLoad() throws {
        try service.save("lin_api_test123")
        let loaded = try service.load()
        #expect(loaded == "lin_api_test123")
    }

    @Test func loadWhenEmpty() {
        let loaded = try? service.load()
        #expect(loaded == nil)
    }

    @Test func deleteRemovesKey() throws {
        try service.save("lin_api_test123")
        service.delete()
        let loaded = try? service.load()
        #expect(loaded == nil)
    }

    @Test func saveOverwrites() throws {
        try service.save("lin_api_first")
        try service.save("lin_api_second")
        let loaded = try service.load()
        #expect(loaded == "lin_api_second")
    }
}
