using System;
using System.IO;
using System.Text.Json;

namespace PaySprout;
public sealed class Settings
{
    public double DailyPay { get; set; } = 500;
    public int StartMinutes { get; set; } = 540;
    public int EndMinutes { get; set; } = 1080;
    public bool Compact { get; set; }
    public double Scale { get; set; } = 1;
    public double FullWidth { get; set; } = 660;
    public double FullHeight { get; set; } = 392;
    public double CompactWidth { get; set; } = 424;
    public double CompactHeight { get; set; } = 124;
    public DateTime? LastCelebrated { get; set; }
    public static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PaySprout");
    public static string FilePath => Path.Combine(Folder,"settings.json");
    public static Settings Load()
    {
        try {
            var settings = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath));
            if (settings != null && Preferences.Valid(settings.DailyPay,settings.StartMinutes,settings.EndMinutes) && settings.Scale >= .8 && settings.Scale <= 1.4) return settings;
        } catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { }
        return new();
    }
    public void Save()
    {
        Directory.CreateDirectory(Folder);
        var temp = FilePath + ".tmp";
        File.WriteAllText(temp,JsonSerializer.Serialize(this,new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp,FilePath,true);
    }
}
