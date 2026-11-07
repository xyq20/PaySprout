using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace PaySprout;

public sealed record InstallPlan(string Token,string Target,string Incoming,string Backup,string Sha256,string Version,int OldPid,long OldStartTicks,bool SmokeTest=false)
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PaySprout","Updates");
    public string Workspace => Path.Combine(Root,Token);
    public string FilePath => Path.Combine(Workspace,"plan.json");
}

public static class UpdateInstaller
{
    public static string CurrentVersion => string.Join('.',(System.Reflection.Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0,0,0)).ToString().Split('.').Take(3));
    private static string Hash(string file) { using var input=File.OpenRead(file); return Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant(); }
    public static InstallPlan Prepare(string payload,string target,string version,string token,Process? oldProcess=null,bool smokeTest=false)
    {
        if(!Guid.TryParseExact(token,"D",out _) || UpdatePolicy.ParseVersion(version)==null) throw new InvalidDataException("更新参数无效。");
        var fileVersion=FileVersionInfo.GetVersionInfo(payload);
        if($"{fileVersion.FileMajorPart}.{fileVersion.FileMinorPart}.{fileVersion.FileBuildPart}"!=version) throw new InvalidDataException("更新包的程序版本不匹配。");
        target=Path.GetFullPath(target);
        var directory=Path.GetDirectoryName(target)!;
        var incoming=Path.Combine(directory,$".PaySprout-{token}.new.exe");
        var backup=Path.Combine(directory,$".PaySprout-{token}.previous.exe");
        if(File.Exists(incoming) || File.Exists(backup)) throw new IOException("此更新已有安装任务，请重新检查更新。");
        File.Copy(payload,incoming,false); // Check write permission before the running app quits.
        oldProcess ??= Process.GetCurrentProcess();
        var plan=new InstallPlan(token,target,incoming,backup,Hash(incoming),version,oldProcess.Id,oldProcess.StartTime.ToUniversalTime().Ticks,smokeTest);
        try {
            Directory.CreateDirectory(plan.Workspace);
            File.WriteAllText(plan.FilePath,JsonSerializer.Serialize(plan));
            File.Copy(Environment.ProcessPath!,Path.Combine(plan.Workspace,"UpdateHost.exe"),false);
            return plan;
        } catch { File.Delete(incoming); throw; }
    }
    public static Process Start(InstallPlan plan)
    {
        var info=new ProcessStartInfo(Path.Combine(plan.Workspace,"UpdateHost.exe")) { UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=plan.Workspace };
        info.ArgumentList.Add("--apply-update"); info.ArgumentList.Add(plan.FilePath);
        return Process.Start(info) ?? throw new IOException("无法启动更新助手。");
    }
    public static InstallPlan ReadPlan(string path)
    {
        var plan=JsonSerializer.Deserialize<InstallPlan>(File.ReadAllText(path)) ?? throw new InvalidDataException("更新任务无效。");
        var directory=Path.GetDirectoryName(Path.GetFullPath(plan.Target))!;
        if(!Guid.TryParseExact(plan.Token,"D",out _) || !Path.GetFullPath(path).Equals(plan.FilePath,StringComparison.OrdinalIgnoreCase) ||
           plan.Incoming!=Path.Combine(directory,$".PaySprout-{plan.Token}.new.exe") || plan.Backup!=Path.Combine(directory,$".PaySprout-{plan.Token}.previous.exe") ||
           !Regex.IsMatch(plan.Sha256,"^[0-9a-f]{64}$") || UpdatePolicy.ParseVersion(plan.Version)==null || plan.OldPid<=0) throw new InvalidDataException("更新任务路径无效。");
        return plan;
    }
    public static InstallPlan? Acknowledge(string token)
    {
        if(!Guid.TryParseExact(token,"D",out _)) return null;
        var plan=ReadPlan(Path.Combine(InstallPlan.Root,token,"plan.json"));
        if(!plan.Target.Equals(Environment.ProcessPath,StringComparison.OrdinalIgnoreCase) || plan.Version!=CurrentVersion) throw new InvalidDataException("更新启动校验失败。");
        AtomicText(Path.Combine(plan.Workspace,"ready.json"),JsonSerializer.Serialize(new { Version=CurrentVersion,Pid=Environment.ProcessId }));
        return plan;
    }
    private static void AtomicText(string path,string text) { File.WriteAllText(path+".tmp",text); File.Move(path+".tmp",path,true); }
    private static void Result(InstallPlan plan,string status,string? error=null) => AtomicText(Path.Combine(plan.Workspace,"result.json"),JsonSerializer.Serialize(new { Status=status,Error=error }));
    private static Process Launch(InstallPlan plan,bool rollback=false) {
        var info=new ProcessStartInfo(plan.Target) { UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(plan.Target)! };
        info.ArgumentList.Add(rollback ? "--paysprout-rollback" : "--paysprout-updated"); info.ArgumentList.Add(plan.Token);
        return Process.Start(info) ?? throw new IOException("无法启动应用。");
    }
    public static async Task<int> ApplyAsync(string path)
    {
        InstallPlan? plan=null; Process? next=null; bool moved=false;
        try {
            plan=ReadPlan(path);
            if(!Path.GetDirectoryName(Environment.ProcessPath)!.Equals(plan.Workspace,StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("更新助手位置无效。");
            if(Hash(plan.Incoming)!=plan.Sha256) throw new InvalidDataException("待安装程序的校验失败。");
            Process? old=null;
            try { old=Process.GetProcessById(plan.OldPid); } catch(ArgumentException) { }
            if(old!=null) {
                using(old) {
                    if(old.StartTime.ToUniversalTime().Ticks==plan.OldStartTicks) {
                        using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(60));
                        await old.WaitForExitAsync(timeout.Token);
                    }
                }
            }
            File.Move(plan.Target,plan.Backup,false); moved=true;
            File.Move(plan.Incoming,plan.Target,false);
            next=Launch(plan);
            var deadline=DateTime.UtcNow.AddSeconds(30);
            while(DateTime.UtcNow<deadline) {
                var ack=Path.Combine(plan.Workspace,"ready.json");
                if(File.Exists(ack)) {
                    using var doc=JsonDocument.Parse(File.ReadAllText(ack));
                    if(doc.RootElement.GetProperty("Version").GetString()==plan.Version && doc.RootElement.GetProperty("Pid").GetInt32()==next.Id) {
                        Result(plan,"installed");
                        try { File.Delete(plan.Backup); } catch(IOException) { } catch(UnauthorizedAccessException) { }
                        return 0;
                    }
                }
                if(next.HasExited) break;
                await Task.Delay(200);
            }
            throw new IOException("新版未完成启动确认。");
        } catch(Exception ex) {
            if(plan==null) return 1;
            try {
                if(next!=null && !next.HasExited) { next.Kill(); await next.WaitForExitAsync(); }
                if(moved && File.Exists(plan.Backup)) {
                    File.Delete(plan.Target); File.Move(plan.Backup,plan.Target,false);
                    Result(plan,"rolled-back",ex.Message); Launch(plan,true);
                } else Result(plan,"failed",ex.Message);
            } catch(Exception rollbackError) { Result(plan,"needs-recovery",rollbackError.Message+"；旧版备份："+plan.Backup); }
            return 1;
        } finally { next?.Dispose(); }
    }
    public static void Discard(InstallPlan plan) { if(File.Exists(plan.Incoming)) File.Delete(plan.Incoming); }
}
