using PaySprout;

int checks = 0;
void Check(bool condition, string message) { checks++; if (!condition) throw new Exception(message); }
DateTime At(int hour, int minute = 0) => new(2026, 11, 6, hour, minute, 0);
foreach (var (hour, minute, start, end, fraction) in new[] {
    (8,0,540,1080,0d), (9,0,540,1080,0d), (13,30,540,1080,.5),
    (18,0,540,1080,1d), (23,0,540,1080,1d), (2,0,1320,360,.5),
    (23,0,1320,360,.125), (6,0,1320,360,1d), (14,0,1320,360,1d),
    (21,59,1320,360,1d), (22,0,1320,360,0d) }) {
    var shift = Shift.Make(At(hour, minute), start, end);
    Check(Math.Abs(shift.Fraction - fraction) < 1e-9, $"Shift {hour}:{minute}: expected {fraction}, got {shift.Fraction}");
    Check(shift.Remaining >= 0, "Countdown is nonnegative");
}
var midpoint = Shift.Make(At(13,30), 540,1080);
Check(midpoint.Earned(500) == 250, "Halfway earnings");
Check(Math.Abs(Shift.Make(At(13,30).AddSeconds(1),540,1080).Earned(500) - 250 - 500d/32400) < 1e-9, "Linear per-second earnings");
Check(Money.Text(12.3).EndsWith("3000"), "Four decimal places");
Check(Money.Text(.00006).EndsWith("0001"), "Small increment rounding");
Check(Shift.Make(At(8),540,1080).Earned(500) == 0, "No income before shift");
Check(Shift.Make(At(20),540,1080).Earned(500) == 500, "Income capped");
foreach (double badPay in new[]{-1d, double.NaN, double.PositiveInfinity, 10000001})
    Check(!Preferences.Valid(badPay,540,1080), "Reject invalid salary");
Check(!Preferences.Valid(500,540,540), "Reject zero length shift");
Check(!Preferences.Valid(500,-1,1080) && !Preferences.Valid(500,540,1440), "Reject invalid minutes");
Check(Preferences.Valid(0,1320,360) && Preferences.Valid(10000000,540,1080), "Boundary settings");
var pause = BreakSession.Begin(At(17,55),500,540,1080);
Check(Math.Abs(pause.Earnings(At(20)) - 500d*5/540) < 1e-9, "Break earnings cap at shift end");
Check(pause.Earnings(At(17,54)) == 0 && pause.Elapsed(At(17,54)) == 0, "No negative break values");
var done = Shift.Make(At(18),540,1080);
Check(done.ShouldCelebrate(null), "First celebration");
Check(!done.ShouldCelebrate(done.Start) && !midpoint.ShouldCelebrate(null), "No duplicate or early celebration");
foreach (var (fraction, stage) in new[]{(0d,0),(.01,1),(.499,1),(.5,2),(.849,2),(.85,3),(.999,3),(1d,4)})
    Check(Growth.Stage(fraction) == stage, "Growth boundary");
Console.WriteLine($"Passed {checks} Windows model checks.");
