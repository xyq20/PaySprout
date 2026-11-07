using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;

namespace PaySprout;
internal static class UpdateInstallSmoke
{
    internal static async Task<int> Run(string reportFolder) {
        try {
            Directory.CreateDirectory(reportFolder);
            foreach(bool fail in new[]{false,true}) {
                var id=Guid.NewGuid().ToString("D"); var workspace=Path.Combine(InstallPlan.Root,id); Directory.CreateDirectory(workspace);
                var targetFolder=Path.Combine(workspace,"installation with spaces ' 薪芽"); Directory.CreateDirectory(targetFolder);
                var target=Path.Combine(targetFolder,"PaySprout.exe"); File.Copy(Environment.ProcessPath!,target);
                var originalHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(target)));
                var holdInfo=new ProcessStartInfo(target) { UseShellExecute=false,CreateNoWindow=true }; holdInfo.ArgumentList.Add("--update-wait-smoke");
                using var old=Process.Start(holdInfo)!; await Task.Delay(300);
                var plan=UpdateInstaller.Prepare(Environment.ProcessPath!,target,UpdateInstaller.CurrentVersion,id,old,true);
                var helperInfo=new ProcessStartInfo(Path.Combine(workspace,"UpdateHost.exe")) { UseShellExecute=false,CreateNoWindow=true };
                helperInfo.ArgumentList.Add("--apply-update"); helperInfo.ArgumentList.Add(plan.FilePath);
                if(fail) helperInfo.Environment["PAYSPROUT_SMOKE_FAIL_ACK"]="1";
                using var helper=Process.Start(helperInfo)!; old.Kill(); await old.WaitForExitAsync();
                using var timeout=new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(50)); await helper.WaitForExitAsync(timeout.Token);
                var result=File.ReadAllText(Path.Combine(workspace,"result.json"));
                using var doc=JsonDocument.Parse(result);
                if(doc.RootElement.GetProperty("Status").GetString()!=(fail ? "rolled-back" : "installed")) throw new Exception("Unexpected update result: "+result);
                if(fail && originalHash!=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(target)))) throw new Exception("Rollback did not preserve the original executable");
                if(fail) { for(int retry=0;retry<30 && !File.Exists(Path.Combine(workspace,"restored.txt"));retry++) await Task.Delay(200); if(!File.Exists(Path.Combine(workspace,"restored.txt"))) throw new Exception("Restored app was not relaunched"); }
                await Task.Delay(1600);
                File.WriteAllText(Path.Combine(reportFolder,fail ? "update-rollback.json" : "update-installed.json"),result);
                Directory.Delete(workspace,true);
            }
            File.WriteAllText(Path.Combine(reportFolder,"update-passed.txt"),"Passed: published EXE helper, wait for old process, replacement, real WPF launch acknowledgement, failed-launch rollback, original EXE hash preservation and relaunch; isolated paths with spaces, quotes and Chinese.");
            return 0;
        } catch(Exception ex) { File.WriteAllText(Path.Combine(reportFolder,"update-error.txt"),ex.ToString()); return 1; }
    }
}
