using System;
using System.IO;
using System.Threading.Tasks;

namespace PaySprout;
internal static class SmokeTest
{
    internal static async Task Run(MainWindow window)
    {
        Directory.CreateDirectory("smoke");
        await Task.Delay(600);
        if (string.IsNullOrWhiteSpace(window.Amount.Text) || !window.Amount.Text.StartsWith("¥")) throw new Exception("Income is not rendered");
        window.Capture("smoke/windows-full.png");
        window.OpenSettings();
        window.PayInput.Text="-1";
        if (window.SaveDraft() || string.IsNullOrEmpty(window.SettingsError.Text)) throw new Exception("Invalid settings accepted");
        window.PayInput.Text="500"; window.StartInput.Text="09:00"; window.EndInput.Text="18:00";
        if (!window.SaveDraft()) throw new Exception("Valid settings rejected");
        var persisted=Settings.Load();
        if (persisted.DailyPay != 500 || persisted.StartMinutes != 540 || persisted.EndMinutes != 1080) throw new Exception("Settings not persisted");
        window.ToggleBreak(); await Task.Delay(300); window.Capture("smoke/windows-charging.png");
        if (!window.Buddy.Charging && window.Progress.Value < 1) throw new Exception("Break state missing");
        window.ToggleBreak();
        window.TogglePreview(); await Task.Delay(900); window.Capture("smoke/windows-celebration.png");
        if (!window.CountdownTitle.Text.Contains("预览")) throw new Exception("Preview not marked");
        window.TogglePreview();
        window.SmokeCompact(); await Task.Delay(300); window.Capture("smoke/windows-compact.png");
        if (window.CompactBox.Visibility != System.Windows.Visibility.Visible) throw new Exception("Compact mode not displayed");
        window.Hide(); await Task.Delay(100); window.Show();
        if (!window.IsVisible) throw new Exception("Cannot restore hidden window");
        File.WriteAllText("smoke/passed.txt","Passed: real WPF window, salary rendering, input validation, saved settings, charging, celebration preview, compact mode, hide and restore.");
    }
}
