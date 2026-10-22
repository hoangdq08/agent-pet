import Foundation

/// Per-agent token totals for the stats card and the Care tab ("By agent").
/// Pure so it can be tested without the usage store or any UI.
public struct AgentUsageTotal: Equatable, Sendable {
    public var agent: String
    public var today: Int
    public var month: Int
    public var sessions: Int

    public init(agent: String, today: Int, month: Int, sessions: Int) {
        self.agent = agent; self.today = today; self.month = month; self.sessions = sessions
    }
}

public enum AgentUsage {
    /// One (agent, day) usage record. `day` is `yyyy-MM-dd`.
    public struct Record: Sendable {
        public var agent: String
        public var day: String
        public var tokens: Int
        public var sessions: Int

        public init(agent: String, day: String, tokens: Int, sessions: Int) {
            self.agent = agent; self.day = day; self.tokens = tokens; self.sessions = sessions
        }
    }

    /// Tokens and finished sessions per agent for `today` and the calendar month
    /// it falls in, most tokens this month first (ties by name). An agent with
    /// nothing this month is left out.
    public static func totals(_ records: [Record], today: String) -> [AgentUsageTotal] {
        let month = String(today.prefix(7))
        var byAgent: [String: AgentUsageTotal] = [:]
        for r in records where r.day.hasPrefix(month) {
            var t = byAgent[r.agent] ?? AgentUsageTotal(agent: r.agent, today: 0, month: 0, sessions: 0)
            t.month += r.tokens
            t.sessions += r.sessions
            if r.day == today { t.today += r.tokens }
            byAgent[r.agent] = t
        }
        return byAgent.values
            .filter { $0.month > 0 || $0.sessions > 0 }
            .sorted { $0.month != $1.month ? $0.month > $1.month : $0.agent < $1.agent }
    }

    /// Display name for a stored agent id: the catalog label for a known kind,
    /// else the id with its first letter capitalised (custom agents).
    public static func label(for agent: String) -> String {
        if let kind = AgentKind(rawValue: agent), kind != .unknown, kind != .cli {
            return TickerFormatter.agentLabel(for: kind)
        }
        if agent == "cli" { return "Agent" }
        return agent.prefix(1).uppercased() + agent.dropFirst()
    }
}
