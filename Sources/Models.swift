import Foundation
import CoreGraphics

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
            // Keep the completed overnight shift until the next start, so its
            // capped income and clock-out celebration remain available by day.
            if now < start { start = calendar.date(byAdding: .day, value: -1, to: start)! }
            else { end = calendar.date(byAdding: .day, value: 1, to: end)! }
        }
        return WorkState(start: start, end: end, now: now)
    }
}

enum Money {
    static func text(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }
}

enum GrowthStage: Int, CaseIterable {
    case resting, sprouting, growing, budding, blooming
    init(progress: Double) {
        switch progress {
        case ...0: self = .resting
        case ..<0.5: self = .sprouting
        case ..<0.85: self = .growing
        case ..<1: self = .budding
        default: self = .blooming
        }
    }
    var title: String {
        switch self {
        case .resting: return "正在蓄力"
        case .sprouting: return "努力发芽"
        case .growing: return "茁壮成长"
        case .budding: return "快要开花"
        case .blooming: return "今日开花"
        }
    }
    var message: String {
        switch self {
        case .resting: return "先伸个懒腰，等阳光来上班。"
        case .sprouting: return "你在赚钱，我在长叶，一起慢慢来。"
        case .growing: return "已经过半啦，自由又近了一点。"
        case .budding: return "花苞准备好了，就等下班这一刻。"
        case .blooming: return "今天的小花送给你，辛苦啦。"
        }
    }
}

struct WidgetLayout {
    static let inset: CGFloat = 20
    static func base(compact: Bool) -> CGSize {
        compact ? CGSize(width: 404, height: 104) : CGSize(width: 640, height: 372)
    }
    static func minimum(compact: Bool) -> CGSize { preset(compact: compact, scale: 0.8) }
    static func preset(compact: Bool, scale: Double) -> CGSize {
        let base = base(compact: compact)
        let scale = min(1.4, max(0.8, scale))
        return CGSize(width: base.width * scale + inset, height: base.height * scale + inset)
    }
    static func clamped(_ size: CGSize, compact: Bool, maximum: CGSize) -> CGSize {
        let minimum = minimum(compact: compact)
        return CGSize(width: min(max(size.width, minimum.width), max(minimum.width, maximum.width)),
                      height: min(max(size.height, minimum.height), max(minimum.height, maximum.height)))
    }
    static func renderScale(size: CGSize, compact: Bool, requested: Double) -> Double {
        let base = base(compact: compact)
        return min(min(1.4, max(0.8, requested)), (size.width - inset) / base.width, (size.height - inset) / base.height)
    }
    static func storageKey(compact: Bool) -> String { compact ? "compactWindow" : "fullWindow" }
}

struct BreakSession {
    let startedAt: Date
    let earnedAtStart: Double
    let shiftStart: Date
    let shiftEnd: Date
    let dailyPay: Double
    func earnings(at now: Date) -> Double {
        let work = WorkState(start: shiftStart, end: shiftEnd, now: now)
        return max(0, dailyPay * work.fraction - earnedAtStart)
    }
    func elapsed(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(startedAt))) }
}

struct EarningsRate {
    let dailyPay: Double
    let start: Date
    let end: Date
    var perSecond: Double { dailyPay / end.timeIntervalSince(start) }
    func amount(at date: Date) -> Double {
        min(dailyPay, max(0, date.timeIntervalSince(start) * perSecond))
    }
}

struct CelebrationGate {
    static func shouldCelebrate(work: WorkState, lastShift: Double) -> Bool {
        work.fraction >= 1 && work.start.timeIntervalSince1970 != lastShift
    }
}
