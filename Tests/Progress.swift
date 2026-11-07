import Foundation
import CoreGraphics

@main
struct ProgressTests {
    static func main() {
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
        check(6, 0, 1320, 360, 1)
        check(14, 0, 1320, 360, 1)
        check(21, 59, 1320, 360, 1)
        check(22, 0, 1320, 360, 0)
        let overnightFinished = WorkState.make(now: date(6), startMinutes: 1320, endMinutes: 360)
        assert(CelebrationGate.shouldCelebrate(work: overnightFinished, lastShift: 0))
        for (progress, stage) in [(0.0, GrowthStage.resting), (0.01, .sprouting), (0.499, .sprouting), (0.5, .growing), (0.849, .growing), (0.85, .budding), (0.999, .budding), (1, .blooming)] {
            assert(GrowthStage(progress: progress) == stage)
        }
        assert(Money.text(12.3).hasSuffix("3000"))
        assert(Money.text(0.00006).hasSuffix("0001"))
        let liveStart = date(13, 30)
        let liveA = WorkState.make(now: liveStart, startMinutes: 540, endMinutes: 1080)
        let liveB = WorkState.make(now: liveStart.addingTimeInterval(1.0 / 60), startMinutes: 540, endMinutes: 1080)
        assert(Money.text(500 * liveA.fraction) != Money.text(500 * liveB.fraction))
        for compact in [false, true] {
            let minimum = WidgetLayout.minimum(compact: compact)
            let maximum = CGSize(width: 1800, height: 1000)
            assert(WidgetLayout.clamped(.zero, compact: compact, maximum: maximum) == minimum)
            assert(WidgetLayout.clamped(CGSize(width: 4000, height: 2000), compact: compact, maximum: maximum) == maximum)
            for size in [minimum, WidgetLayout.preset(compact: compact, scale: 1.4), CGSize(width: 1000, height: 600)] {
                let scale = WidgetLayout.renderScale(size: size, compact: compact, requested: 1.4)
                let base = WidgetLayout.base(compact: compact)
                assert((size.width - 20) / scale >= base.width - 0.0001)
                assert((size.height - 20) / scale >= base.height - 0.0001)
            }
        }
        let finishedShift = WorkState.make(now: date(18), startMinutes: 540, endMinutes: 1080)
        assert(CelebrationGate.shouldCelebrate(work: finishedShift, lastShift: 0))
        assert(!CelebrationGate.shouldCelebrate(work: finishedShift, lastShift: finishedShift.start.timeIntervalSince1970))
        assert(!CelebrationGate.shouldCelebrate(work: WorkState.make(now: date(17), startMinutes: 540, endMinutes: 1080), lastShift: 0))
        let rate = EarningsRate(dailyPay: 500, start: date(9), end: date(18))
        let fixedA = rate.amount(at: date(13, 30))
        let fixedB = rate.amount(at: date(13, 30).addingTimeInterval(0.5))
        let fixedC = rate.amount(at: date(13, 30).addingTimeInterval(1))
        assert(abs((fixedB - fixedA) - (fixedC - fixedB)) < 1e-9)
        assert(rate.amount(at: date(8)) == 0 && rate.amount(at: date(20)) == 500)
        let shiftStart = date(9), shiftEnd = date(18)
        let session = BreakSession(startedAt: date(17, 55), earnedAtStart: 500 * (Double(535) / 540), shiftStart: shiftStart, shiftEnd: shiftEnd, dailyPay: 500)
        assert(session.earnings(at: date(20)) <= 500 * (Double(5) / 540) + 0.0001)
        assert(session.earnings(at: date(17, 54)) == 0)
        assert(session.elapsed(at: date(17, 54)) == 0)
        print("Passed: growth stages, 4-decimal amounts, linear earnings, resize bounds, layout fit, capped break income, one celebration per shift.")
        print("Passed: before shift, start, midpoint, end, after shift, overnight.")

    }
}
