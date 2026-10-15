import Foundation
import Testing
@testable import ClaudeUsage

@Suite("Formatting")
struct FormattingTests {
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: Countdown

    @Test("Countdown picks the largest useful units", arguments: [
        (59, "0 min"),
        (60, "1 min"),
        (3540, "59 min"),
        (3600, "1 h 0 min"),
        (7980, "2 h 13 min"),       // 2 h 13 min
        (86_400, "1 d 0 h"),
        (280_740, "3 d 5 h"),       // 3 d 5 h 59 min: los minutos se descartan
    ] as [(Double, String)])
    func countdown(seconds: Double, expected: String) {
        #expect(formatCountdown(to: now.addingTimeInterval(seconds), now: now) == expected)
    }

    @Test func countdownNeverGoesNegative() {
        #expect(formatCountdown(to: now.addingTimeInterval(-500), now: now) == "0 min")
    }

    // MARK: Reset time

    var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func resetTimeTodayShowsOnlyTheHour() {
        let now = parseISODate("2026-10-13T08:00:00+00:00")!
        let reset = parseISODate("2026-10-13T14:59:00+00:00")!
        #expect(formatResetTime(reset, now: now, calendar: utcCalendar) == "14:59")
    }

    @Test func resetTimeOnAnotherDayIncludesTheWeekday() {
        let now = parseISODate("2026-10-13T08:00:00+00:00")!
        let reset = parseISODate("2026-10-16T16:28:00+00:00")!
        #expect(formatResetTime(reset, now: now, calendar: utcCalendar) == "vie 16, 16:28")
    }

    // MARK: Menu bar

    @Test func menuBarTitleWithCountdown() {
        let reset = now.addingTimeInterval(2 * 3600 + 13 * 60)
        #expect(menuBarTitle(sessionPercent: 41.6, reset: reset, now: now) == " 42% · 2h13m")
    }

    @Test func menuBarTitleOmitsCountdownOnceTheWindowHasReset() {
        #expect(menuBarTitle(sessionPercent: 10, reset: now.addingTimeInterval(-1), now: now) == " 10%")
    }

    @Test func menuBarTitleWithoutData() {
        #expect(menuBarTitle(sessionPercent: nil, reset: nil, now: now) == " –")
    }

    @Test("Menu bar alert thresholds", arguments: [
        (nil, MenuBarAlert.none), (0, .none), (74.9, .none),
        (75, .warning), (89.9, .warning), (90, .critical), (120, .critical),
    ] as [(Double?, MenuBarAlert)])
    func menuBarAlert(percent: Double?, expected: MenuBarAlert) {
        #expect(MenuBarAlert(percent: percent) == expected)
    }

    @Test("Usage level thresholds", arguments: [
        (0, UsageLevel.low), (74.9, .low), (75, .medium), (89.9, .medium), (90, .high), (100, .high),
    ] as [(Double, UsageLevel)])
    func usageLevel(percent: Double, expected: UsageLevel) {
        #expect(UsageLevel(percent: percent) == expected)
    }

    // MARK: ISO dates

    @Test func parsesDatesWithMicroseconds() {
        let date = parseISODate("2026-10-13T12:59:00.456921+00:00")
        #expect(date == parseISODate("2026-10-13T12:59:00+00:00"))
        #expect(date?.timeIntervalSince1970 == 1_791_896_340)
    }

    @Test func parsesDatesWithTimezoneOffset() {
        #expect(parseISODate("2026-10-13T14:59:00+02:00") == parseISODate("2026-10-13T12:59:00Z"))
    }

    @Test func rejectsGarbage() {
        #expect(parseISODate("") == nil)
        #expect(parseISODate("mañana") == nil)
    }
}
