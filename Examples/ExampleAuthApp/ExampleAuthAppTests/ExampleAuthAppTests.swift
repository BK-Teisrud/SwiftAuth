import Auth
import Foundation
import Testing

@testable import ExampleAuthApp

struct ExampleAuthAppTests {
  @Test func configurationRequiresBackendAndPublicClient() {
    var settings = AuthSettings()
    #expect(!settings.isComplete)
    settings.backendURL = "https://api.example.com"
    settings.githubClientID = "public-client"
    #expect(settings.isComplete)
    for invalid in [
      "http://api.example.com", "https://user:password@api.example.com",
      "https://api.example.com?secret=1",
    ] {
      settings.backendURL = invalid
      #expect(!settings.isComplete)
    }
  }

  @Test func internalUserIDIsIndependentOfProviderID() throws {
    let data = Data(
      #"{"subject":"internal-42","name":"Test User","githubLogin":"octocat","githubID":"123456"}"#
        .utf8)
    let user = try JSONDecoder().decode(BackendUser.self, from: data)
    #expect(user.subject == "internal-42")
    #expect(user.githubID == "123456")
    #expect(user.githubLogin == "octocat")
  }

  @Test func appleUserDoesNotRequireGithubFields() throws {
    let user = try JSONDecoder().decode(
      BackendUser.self, from: Data(#"{"subject":"internal-apple"}"#.utf8))
    #expect(user.githubID == nil)
    #expect(user.displayName == "internal-apple")
  }
}
