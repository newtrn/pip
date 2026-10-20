import Foundation

public enum TimeFormatting {
    /// "2h 14m", "5d 3h", "12m" — the design's `fmtDur`.
    public static func duration(_ interval: TimeInterval) -> String {
        let m = max(0, Int((interval / 60).rounded()))
        if m >= 1440 { return "\(m / 1440)d \((m % 1440) / 60)h" }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Wall-clock reset label: "11:55 AM" when it is within a day, "Thu 9:00 AM" otherwise.
    public static func resetLabel(_ date: Date, now: Date, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = date.timeIntervalSince(now) > 20 * 3600 ? "EEE h:mm a" : "h:mm a"
        return f.string(from: date)
    }
}
