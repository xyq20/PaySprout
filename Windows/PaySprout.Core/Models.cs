using System.Globalization;
namespace PaySprout;

public record Shift(DateTime Start, DateTime End, DateTime Now)
{
    public double Seconds => (End.ToUniversalTime() - Start.ToUniversalTime()).TotalSeconds;
    public double Fraction => Math.Clamp((Now.ToUniversalTime() - Start.ToUniversalTime()).TotalSeconds / Seconds, 0, 1);
    public int Remaining => (int)Math.Max(0, (End.ToUniversalTime() - Now.ToUniversalTime()).TotalSeconds);
    public double Earned(double pay) => pay * Fraction;
    public bool ShouldCelebrate(DateTime? last) => Fraction >= 1 && last != Start;
    public static Shift Make(DateTime now, int start, int end)
    {
        if (!Preferences.Valid(0, start, end)) throw new ArgumentException("Invalid shift times");
        var from = now.Date.AddMinutes(start);
        var until = now.Date.AddMinutes(end);
        if (end <= start) {
            if (now < from) from = from.AddDays(-1);
            else until = until.AddDays(1);
        }
        return new(from, until, now);
    }
}
public static class Money { public static string Text(double value) => value.ToString("F4", CultureInfo.CurrentCulture); }
public static class Preferences {
    public static bool Valid(double pay,int start,int end) => double.IsFinite(pay) && pay >= 0 && pay <= 10000000 && start >= 0 && start < 1440 && end >= 0 && end < 1440 && start != end;
}
public static class Growth { public static int Stage(double progress) => progress <= 0 ? 0 : progress < .5 ? 1 : progress < .85 ? 2 : progress < 1 ? 3 : 4; }
public record BreakSession(DateTime StartedAt, Shift Shift, double Pay)
{
    public static BreakSession Begin(DateTime now,double pay,int start,int end) => new(now,Shift.Make(now,start,end),pay);
    public double Earnings(DateTime now) => Math.Max(0, (Shift with { Now = now }).Earned(Pay) - Shift.Earned(Pay));
    public int Elapsed(DateTime now) => (int)Math.Max(0, (now.ToUniversalTime() - StartedAt.ToUniversalTime()).TotalSeconds);
}
