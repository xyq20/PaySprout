using System;
using System.IO;
using System.Linq;

namespace PaySprout;
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if(args.Length==2 && args[0]=="--apply-update") return UpdateInstaller.ApplyAsync(args[1]).GetAwaiter().GetResult();
        if(args.Length==2 && args[0]=="--update-install-smoke") return UpdateInstallSmoke.Run(args[1]).GetAwaiter().GetResult();
        if(args.Length==1 && args[0]=="--update-wait-smoke") { System.Threading.Thread.Sleep(System.Threading.Timeout.Infinite); return 0; }
        if(args.Length==2 && args[0]=="--paysprout-rollback" && Guid.TryParse(args[1],out _)) {
            var path=Path.Combine(InstallPlan.Root,args[1],"plan.json");
            try { if(UpdateInstaller.ReadPlan(path).SmokeTest) { File.WriteAllText(Path.Combine(Path.GetDirectoryName(path)!,"restored.txt"),"restored"); return 0; } } catch { }
        }
        var updated=args.Length==2 && args[0]=="--paysprout-updated";
        if(updated && Environment.GetEnvironmentVariable("PAYSPROUT_SMOKE_FAIL_ACK")=="1") return 1;
        var app=new App(); app.InitializeComponent(); return app.Run();
    }
}
