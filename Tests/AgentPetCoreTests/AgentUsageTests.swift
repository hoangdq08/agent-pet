import XCTest
@testable import AgentPetCore

final class AgentUsageTests: XCTestCase {
    private typealias R = AgentUsage.Record

    func testTotalsSumTodayAndMonthPerAgent() {
        let rows = [
            R(agent: "claude", day: "2026-10-20", tokens: 100, sessions: 1),
            R(agent: "claude", day: "2026-10-03", tokens: 400, sessions: 2),
            R(agent: "codex",  day: "2026-10-20", tokens: 50,  sessions: 0),
        ]
        let t = AgentUsage.totals(rows, today: "2026-10-20")
        XCTAssertEqual(t, [
            AgentUsageTotal(agent: "claude", today: 100, month: 500, sessions: 3),
            AgentUsageTotal(agent: "codex",  today: 50,  month: 50,  sessions: 0),
        ])
    }

    func testOtherMonthsAreLeftOut() {
        let rows = [
            R(agent: "claude", day: "2026-09-30", tokens: 999, sessions: 5),
            R(agent: "codex",  day: "2026-10-01", tokens: 10,  sessions: 0),
        ]
        XCTAssertEqual(AgentUsage.totals(rows, today: "2026-10-20").map(\.agent), ["codex"])
    }

    func testSortsByMonthTokensThenName() {
        let rows = [
            R(agent: "b", day: "2026-10-01", tokens: 5, sessions: 0),
            R(agent: "a", day: "2026-10-01", tokens: 5, sessions: 0),
            R(agent: "z", day: "2026-10-01", tokens: 9, sessions: 0),
        ]
        XCTAssertEqual(AgentUsage.totals(rows, today: "2026-10-20").map(\.agent), ["z", "a", "b"])
    }

    /// An agent whose hook carries no token counts still shows its finished sessions.
    func testSessionOnlyAgentIsKeptAndEmptyOneDropped() {
        let rows = [
            R(agent: "grok", day: "2026-10-02", tokens: 0, sessions: 3),
            R(agent: "ghost", day: "2026-10-02", tokens: 0, sessions: 0),
        ]
        let t = AgentUsage.totals(rows, today: "2026-10-20")
        XCTAssertEqual(t.map(\.agent), ["grok"])
        XCTAssertEqual(t.first?.sessions, 3)
    }

    func testLabels() {
        XCTAssertEqual(AgentUsage.label(for: "jcode"), "jcode")
        XCTAssertEqual(AgentUsage.label(for: "claude"), "Claude")
        XCTAssertEqual(AgentUsage.label(for: "kiroCLI"), "Kiro")
        XCTAssertEqual(AgentUsage.label(for: "cli"), "Agent")
        XCTAssertEqual(AgentUsage.label(for: "mybot"), "Mybot")
    }
}
