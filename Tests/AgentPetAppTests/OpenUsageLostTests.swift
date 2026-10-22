import XCTest
@testable import agentpet

/// The Care tab warns only when OpenUsage answered earlier and has now gone
/// quiet. Never having seen it must stay silent (most people don't run it).
final class OpenUsageLostTests: XCTestCase {
    func testNeverSeenStaysSilentWhetherOrNotReached() {
        XCTAssertFalse(OpenUsageClient.isLost(reached: false, everSeen: false))
        XCTAssertFalse(OpenUsageClient.isLost(reached: true, everSeen: false))
    }

    func testSeenThenSilentIsLost() {
        XCTAssertTrue(OpenUsageClient.isLost(reached: false, everSeen: true))
    }

    func testSeenAndReachableIsNotLost() {
        XCTAssertFalse(OpenUsageClient.isLost(reached: true, everSeen: true))
    }
}
