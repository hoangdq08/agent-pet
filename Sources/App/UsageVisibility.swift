import Foundation
import SwiftUI

/// Which subscription providers the user wants to see. Hidden providers are
/// left out of the Limits rows and of the pet's "limit low" mood, so an AI
/// you never use can't clutter the HUD or make the pet anxious.
@MainActor
final class UsageVisibility: ObservableObject {
    static let shared = UsageVisibility()

    private static let key = "agentpet.usage.hiddenProviders"
    private let defaults: UserDefaults

    @Published private(set) var hidden: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hidden = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func isVisible(_ id: String) -> Bool { !hidden.contains(id) }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        defaults.set(hidden.sorted(), forKey: Self.key)
    }

    func binding(for id: String) -> Binding<Bool> {
        Binding(get: { self.isVisible(id) }, set: { self.setVisible(id, $0) })
    }

    func visible(_ providers: [OpenUsageClient.Provider]) -> [OpenUsageClient.Provider] {
        providers.filter { isVisible($0.id) }
    }
}

/// Text for one limit window: short label ("5h", "7d") and reset time.
enum LimitFormat {
    /// "5h" / "7d" / "30d" from the window length, else the provider's label.
    static func shortLabel(_ w: OpenUsageClient.Window) -> String {
        guard let p = w.period, p > 0 else { return w.label }
        let hours = Int((p / 3600).rounded())
        if hours < 24 { return "\(hours)h" }
        return "\(Int((p / 86400).rounded()))d"
    }

    /// "Session" + "5h" -> "Session · 5h"; drops the length when it adds nothing.
    static func title(_ w: OpenUsageClient.Window) -> String {
        let short = shortLabel(w)
        if w.label.isEmpty { return short }
        if short == w.label { return w.label }
        return "\(w.label) · \(short)"
    }

    /// Wall-clock reset time: "14:30" today, "Mon 14:30" within a week,
    /// "Nov 1" further out.
    static func clock(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                      locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        let secs = date.timeIntervalSince(now)
        if calendar.isDate(date, inSameDayAs: now) {
            f.setLocalizedDateFormatFromTemplate("jmm")
        } else if secs < 6 * 86400 {
            f.setLocalizedDateFormatFromTemplate("EEEjmm")
        } else {
            f.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return f.string(from: date)
    }

    /// "resets in 3h · 14:30". Nil when the time is unknown or already past.
    static func reset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date, let relative = PetStatsView.resetText(date, now: now) else { return nil }
        return "\(relative) · \(clock(date, now: now))"
    }

    /// "↻ 14:30" for tight spaces. Nil when unknown or already past.
    static func compactReset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date, date > now else { return nil }
        return "↻ \(clock(date, now: now))"
    }
}
