import Foundation
import Testing

@Suite struct RepositoryPolicyTests {
  @Test func publishedMarkdownMatchesAllowlistAndExampleAppIsIncluded() throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let expected: Set<String> = [
      ".github/ISSUE_TEMPLATE/bug_report.md",
      ".github/ISSUE_TEMPLATE/feature_request.md",
      ".github/pull_request_template.md",
      "Docs/ProviderSetup.md",
      "Docs/README.md",
      "Examples/ExampleAuthApp/README.md",
      "Examples/ExampleAuthApp/TestBackend/README.md",
      "README.md",
      "SECURITY.md",
      "Sources/Auth/Auth.docc/APIReference.md",
      "Sources/Auth/Auth.docc/Architecture.md",
      "Sources/Auth/Auth.docc/Auth.md",
      "Sources/Auth/Auth.docc/Configuration.md",
      "Sources/Auth/Auth.docc/ErrorsAndRecovery.md",
      "Sources/Auth/Auth.docc/GettingStarted.md",
      "Sources/Auth/Auth.docc/NetworkingIntegration.md",
      "Sources/Auth/Auth.docc/ProvidersAndExtensions.md",
      "Sources/Auth/Auth.docc/Security.md",
      "Sources/Auth/Auth.docc/SessionLifecycle.md",
      "Sources/Auth/Auth.docc/TestingAndRelease.md",
    ]
    let keys: [URLResourceKey] = [.isRegularFileKey]
    let enumerator = try #require(
      FileManager.default.enumerator(
        at: repository, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]))
    var actual: Set<String> = []
    while let file = enumerator.nextObject() as? URL {
      let relative = String(file.path.dropFirst(repository.path.count + 1))
      if relative.hasPrefix(".build/") || relative.hasPrefix(".swiftpm/") { continue }
      if file.pathExtension.lowercased() == "md" { actual.insert(relative) }
    }

    // Hidden files are skipped above, so add the explicitly published GitHub templates.
    for path in expected where path.hasPrefix(".github/") {
      if FileManager.default.fileExists(atPath: repository.appendingPathComponent(path).path) {
        actual.insert(path)
      }
    }

    #expect(actual == expected)
    let examples = repository.appendingPathComponent("Examples").path
    #expect(FileManager.default.fileExists(atPath: examples))
  }
}
