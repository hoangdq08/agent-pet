import XCTest
@testable import agentpet

/// Per-window limits and provider hiding.
@MainActor
final class UsageWindowsTests: XCTestCase {

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    // MARK: - Every window is kept

    func testClaudeKeepsBothWindowsWithResets() throws {
        let body = try json("""
        {"five_hour": {"utilization": 37.0, "resets_at": "2026-10-02T23:59:59.536032+00:00"},
         "seven_day": {"utilization": 79.0, "resets_at": "2026-10-05T03:59:59.536051+00:00"}}
        """)
        let p = try XCTUnwrap(NativeUsageProbe.claudeProvider(from: body))
        XCTAssertEqual(p.windows.map(\.label), ["Session", "Weekly"])
        XCTAssertEqual(p.windows.map { LimitFormat.shortLabel($0) }, ["5h", "7d"])
        XCTAssertEqual(p.windows[0].fractionLeft, 0.63, accuracy: 0.001)
        XCTAssertEqual(p.windows[1].fractionLeft, 0.21, accuracy: 0.001)
        XCTAssertNotNil(p.windows[0].resetsAt)
        XCTAssertNotNil(p.windows[1].resetsAt)
        // The summary fields still describe the tightest window.
        XCTAssertEqual(p.fractionLeft ?? -1, 0.21, accuracy: 0.001)
        XCTAssertEqual(p.windowLabel, "Weekly")
    }

    func testCodexKeepsBothWindowsWithPeriods() throws {
        let body = try json("""
        {"rate_limit": {
          "primary_window": {"used_percent": 16, "limit_window_seconds": 18000, "reset_at": 1790997688},
          "secondary_window": {"used_percent": 3, "limit_window_seconds": 604800, "reset_at": 1791584488}}}
        """)
        let p = try XCTUnwrap(NativeUsageProbe.codexProvider(from: body, now: Date()) { _ in nil })
        XCTAssertEqual(p.windows.map { LimitFormat.shortLabel($0) }, ["5h", "7d"])
        XCTAssertEqual(p.windows.compactMap(\.resetsAt).map(\.timeIntervalSince1970),
                       [1_790_997_688, 1_791_584_488])
    }

    func testOpenUsageKeepsEveryProgressLine() throws {
        let body = try json("""
        {"providerId": "antigravity", "plan": "Ultra", "lines": [
          {"type": "progress", "label": "Session", "used": 0, "limit": 100,
           "resetsAt": "2026-10-03T04:00:08.000Z", "periodDurationMs": 18000000},
          {"type": "progress", "label": "Weekly", "used": 9, "limit": 100,
           "resetsAt": "2026-10-07T02:26:05.000Z", "periodDurationMs": 604800000},
          {"type": "text", "label": "Last 30 Days", "value": "$7.96"}]}
        """)
        let p = try XCTUnwrap(OpenUsageClient.provider(from: body))
        XCTAssertEqual(p.windows.map(\.label), ["Session", "Weekly"])
        XCTAssertEqual(p.windows.map { LimitFormat.shortLabel($0) }, ["5h", "7d"])
        XCTAssertEqual(p.windows.compactMap(\.resetsAt).count, 2)
    }

    // MARK: - Labels

    func testWindowTitle() {
        let session = OpenUsageClient.Window(label: "Session", fractionLeft: 1, period: 18000)
        let weekly = OpenUsageClient.Window(label: "Weekly limit", fractionLeft: 1, period: nil)
        let bare = OpenUsageClient.Window(label: "", fractionLeft: 1, period: 604800)
        XCTAssertEqual(LimitFormat.title(session), "Session · 5h")
        XCTAssertEqual(LimitFormat.title(weekly), "Weekly limit")
        XCTAssertEqual(LimitFormat.title(bare), "7d")
    }

    func testResetClockTodayThisWeekAndLater() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let locale = Locale(identifier: "en_GB")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T06:00:00+07:00"))
        let today = now.addingTimeInterval(3 * 3600)          // Sat 09:00
        let monday = now.addingTimeInterval(2 * 86400 + 3600) // Mon 07:00
        let later = now.addingTimeInterval(29 * 86400)        // Nov 1
        XCTAssertEqual(LimitFormat.clock(today, now: now, calendar: cal, locale: locale), "09:00")
        XCTAssertEqual(LimitFormat.clock(monday, now: now, calendar: cal, locale: locale), "Mon 07:00")
        XCTAssertEqual(LimitFormat.clock(later, now: now, calendar: cal, locale: locale), "1 Nov")
    }

    func testResetTextNilWhenPastOrUnknown() {
        let now = Date()
        XCTAssertNil(LimitFormat.reset(nil, now: now))
        XCTAssertNil(LimitFormat.reset(now.addingTimeInterval(-60), now: now))
        XCTAssertNotNil(LimitFormat.reset(now.addingTimeInterval(3 * 3600 + 60), now: now))
        XCTAssertNil(LimitFormat.compactReset(nil, now: now))
        XCTAssertNil(LimitFormat.compactReset(now.addingTimeInterval(-60), now: now))
        XCTAssertEqual(LimitFormat.compactReset(now.addingTimeInterval(3600), now: now)?.hasPrefix("↻ "), true)
    }

    // MARK: - Hiding providers

    func testHiddenProvidersAreFilteredAndPersisted() throws {
        let suite = "agentpet.tests.usageVisibility"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UsageVisibility(defaults: defaults)
        let providers = ["claude", "codex", "grok"].map {
            OpenUsageClient.Provider(id: $0, displayName: $0, plan: nil, fractionLeft: 0.5, todayLabel: nil)
        }
        XCTAssertEqual(store.visible(providers).map(\.id), ["claude", "codex", "grok"])

        store.setVisible("grok", false)
        XCTAssertEqual(store.visible(providers).map(\.id), ["claude", "codex"])

        // A fresh store reads the same choice back.
        XCTAssertEqual(UsageVisibility(defaults: defaults).visible(providers).map(\.id), ["claude", "codex"])

        store.setVisible("grok", true)
        XCTAssertEqual(UsageVisibility(defaults: defaults).visible(providers).map(\.id), ["claude", "codex", "grok"])
    }
}
