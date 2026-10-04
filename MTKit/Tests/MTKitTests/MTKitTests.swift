import Testing
@testable import MTKit

@Test func versionIsSet() {
    #expect(!MTKit.version.isEmpty)
}
