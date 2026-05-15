import Testing
import Foundation
@testable import lnr

struct LinearServiceTests {
    @Test func parseViewerResponse() throws {
        let json = """
        {"data":{"viewer":{"id":"user1","name":"Sam Greene","organization":{"name":"Acme"}}}}
        """.data(using: .utf8)!
        let viewer = try LinearService.parseViewerResponse(json)
        #expect(viewer.name == "Sam Greene")
        #expect(viewer.orgName == "Acme")
    }

    @Test func parseIssuesResponse() throws {
        let json = """
        {"data":{"viewer":{"assignedIssues":{"nodes":[
            {"id":"i1","identifier":"ENG-1","title":"Fix bug","description":"Details","priority":1,
             "state":{"id":"s1","name":"In Progress","type":"started","color":"#f59e0b","position":1.0},
             "team":{"id":"t1","key":"ENG","name":"Engineering","color":"#000"},
             "url":"https://linear.app/acme/issue/ENG-1","updatedAt":"2026-05-15T10:00:00.000Z","createdAt":"2026-05-14T08:00:00.000Z"}
        ]}}}}
        """.data(using: .utf8)!
        let issues = try LinearService.parseIssuesResponse(json)
        #expect(issues.count == 1)
        #expect(issues[0].identifier == "ENG-1")
        #expect(issues[0].priority == 1)
        #expect(issues[0].state.type == .started)
    }

    @Test func parseTeamsResponse() throws {
        let json = """
        {"data":{"teams":{"nodes":[
            {"id":"t1","key":"ENG","name":"Engineering","color":"#000","issues":{"nodes":[{"id":"i1"},{"id":"i2"}]}}
        ]}}}
        """.data(using: .utf8)!
        let teams = try LinearService.parseTeamsResponse(json)
        #expect(teams.count == 1)
        #expect(teams[0].team.key == "ENG")
        #expect(teams[0].issueCount == 2)
    }

    @Test func parseWorkflowStatesResponse() throws {
        let json = """
        {"data":{"team":{"states":{"nodes":[
            {"id":"s1","name":"Backlog","type":"backlog","color":"#ccc","position":0.0},
            {"id":"s2","name":"Todo","type":"unstarted","color":"#aaa","position":1.0}
        ]}}}}
        """.data(using: .utf8)!
        let states = try LinearService.parseWorkflowStatesResponse(json)
        #expect(states.count == 2)
        #expect(states[0].name == "Backlog")
    }

    @Test func buildGraphQLRequest() throws {
        let request = try LinearService.buildRequest(
            query: "{ viewer { id } }",
            variables: nil,
            apiKey: "lin_api_test"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "lin_api_test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
