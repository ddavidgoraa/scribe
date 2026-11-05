import MdCore
import XCTest

final class BridgeTests: XCTestCase {
    func testGreetingComesFromRust() {
        let message = greet(name: "Scribe")
        XCTAssertTrue(message.contains("Scribe"))
        XCTAssertTrue(message.contains(coreVersion()))
    }
}
