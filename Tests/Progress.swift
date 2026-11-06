import Foundation
struct WorkState {
    let start: Date
    let end: Date
    let now: Date
    var fraction: Double { min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start))) }
    var remaining: Int { max(0, Int(end.timeIntervalSince(now))) }
    static func make(now: Date, startMinutes: Int, endMinutes: Int) -> WorkState {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        var start = calendar.date(byAdding: .minute, value: startMinutes, to: midnight)!
        var end = calendar.date(byAdding: .minute, value: endMinutes, to: midnight)!
        if endMinutes <= startMinutes {
            if now < end { start = calendar.date(byAdding: .day, value: -1, to: start)! }
            else { end = calendar.date(byAdding: .day, value: 1, to: end)! }
        }
        return WorkState(start: start, end: end, now: now)
    }
}


func date(_ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: hour, minute: minute))!
}
func check(_ hour: Int, _ minute: Int, _ start: Int, _ end: Int, _ expected: Double) {
    let state = WorkState.make(now: date(hour, minute), startMinutes: start, endMinutes: end)
    assert(abs(state.fraction - expected) < 0.00001, "Unexpected fraction: \(state.fraction)")
    assert(state.remaining >= 0)
}
check(8, 0, 540, 1080, 0)
check(9, 0, 540, 1080, 0)
check(13, 30, 540, 1080, 0.5)
check(18, 0, 540, 1080, 1)
check(22, 0, 540, 1080, 1)
check(2, 0, 1320, 360, 0.5)
check(23, 0, 1320, 360, 0.125)
print("Passed: before shift, start, midpoint, end, after shift, overnight.")
