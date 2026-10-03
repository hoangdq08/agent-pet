import Foundation

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

    /// "resets in 3h" / "in 12m". Nil when the time is unknown or already past.
    static func relative(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = date.timeIntervalSince(now)
        guard secs > 0 else { return nil }
        if secs >= 86400 { return String(format: NSLocalizedString("resets in %dd", comment: ""), Int(secs / 86400)) }
        if secs >= 3600 { return String(format: NSLocalizedString("resets in %dh", comment: ""), Int(secs / 3600)) }
        return String(format: NSLocalizedString("resets in %dm", comment: ""), max(1, Int(secs / 60)))
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
        guard let date, let relative = relative(date, now: now) else { return nil }
        return "\(relative) · \(clock(date, now: now))"
    }

    /// "↻ 14:30" for tight spaces. Nil when unknown or already past.
    static func compactReset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date, date > now else { return nil }
        return "↻ \(clock(date, now: now))"
    }
}
