import XCTest
@testable import HyperForgeKit

final class SnippetTokensTests: XCTestCase {
    func testResolveEnv() {
        let env = ["HOME": "/tmp/home", "EMPTY": "", "NEST": "{{env:HOME}}"]
        XCTAssertEqual(SnippetTokens.resolveEnv("{{env:HOME}}", environment: env), "/tmp/home")
        XCTAssertEqual(SnippetTokens.resolveEnv("{{env:NOPE}}", environment: env), "{{env:NOPE}}")
        XCTAssertEqual(SnippetTokens.resolveEnv("{{env:NOT-A}}", environment: env), "{{env:NOT-A}}")
        XCTAssertEqual(SnippetTokens.resolveEnv("{{env.HOME}}", environment: env), "{{env.HOME}}")
        XCTAssertEqual(SnippetTokens.resolveEnv("a{{env:EMPTY}}b", environment: env), "ab")
        XCTAssertEqual(SnippetTokens.resolveEnv("{{env:NEST}}", environment: env), "{{env:HOME}}")
        XCTAssertEqual(SnippetTokens.resolveEnv("{{env:HOME}}-{{env:EMPTY}}", environment: env), "/tmp/home-")
    }
}
