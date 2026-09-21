import XCTest
@testable import Paper

final class PaperThemeTests: XCTestCase {
    func testThemeIsReachableFromTests() {
        XCTAssertNotNil(PaperTheme.nsEditorBackground)
    }
}
