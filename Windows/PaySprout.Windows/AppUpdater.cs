using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

namespace PaySprout;
internal sealed class AppUpdater
{
    private readonly Window owner;
    private Window? window;
    private readonly TextBlock message=new() { TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,14,0,10) };
    private readonly TextBlock notes=new() { TextWrapping=TextWrapping.Wrap,FontSize=11 };
    private readonly ProgressBar progress=new() { Minimum=0,Maximum=1,Height=6,Margin=new Thickness(0,0,0,12),Visibility=Visibility.Collapsed };
    private readonly Button primary=new() { Content="检查更新",MinWidth=100 };
    private readonly Button cancel=new() { Content="取消下载",Visibility=Visibility.Collapsed };
    private UpdateRelease? release;
    private InstallPlan? plan;
    private CancellationTokenSource? cancellation;
    private bool busy,installing;
    private string phase="idle";
    public AppUpdater(Window owner) { this.owner=owner; primary.Click+=async (_,_)=> { if(phase=="ready") Install(); else if(release!=null) await DownloadAsync(); else await CheckAsync(true); }; cancel.Click+=(_,_)=>cancellation?.Cancel(); }
    private void Show() {
        if(window==null) {
            window=new Window { Title="薪芽 · 软件更新",Width=420,Height=390,Owner=owner,WindowStartupLocation=WindowStartupLocation.CenterOwner,ResizeMode=ResizeMode.NoResize,Topmost=true,Background=System.Windows.Media.Brushes.FloralWhite,Foreground=System.Windows.Media.Brushes.DarkSlateGray };
            var panel=new StackPanel { Margin=new Thickness(24) }; window.Content=panel;
            panel.Children.Add(new TextBlock { Text="让小薪芽保持新鲜",FontSize=21,FontWeight=FontWeights.SemiBold });
            panel.Children.Add(new TextBlock { Text="当前版本 v"+UpdateInstaller.CurrentVersion,Margin=new Thickness(0,8,0,0) });
            panel.Children.Add(message); panel.Children.Add(progress);
            panel.Children.Add(new ScrollViewer { Content=notes,MaxHeight=105,VerticalScrollBarVisibility=ScrollBarVisibility.Auto });
            var link=new Button { Content="查看完整发布说明",HorizontalAlignment=HorizontalAlignment.Left,Padding=new Thickness(0,6,0,6) };
            link.Click+=(_,_)=> { if(release!=null) Process.Start(new ProcessStartInfo(release.NotesUrl.ToString()) { UseShellExecute=true }); }; panel.Children.Add(link);
            var actions=new StackPanel { Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,18,0,0) }; actions.Children.Add(cancel); actions.Children.Add(primary); panel.Children.Add(actions);
            window.Closing+=(_,args)=> { if(!installing) { args.Cancel=true; window.Hide(); } };
        }
        window.Show(); window.Activate();
    }
    private void State(string state,string text) {
        phase=state; message.Text=text; busy=state is "checking" or "downloading";
        primary.IsEnabled=!busy; primary.Content=state=="ready" ? "重启更新" : release!=null ? "下载更新" : "检查更新";
        cancel.Visibility=busy ? Visibility.Visible : Visibility.Collapsed;
        progress.Visibility=busy ? Visibility.Visible : Visibility.Collapsed;
        progress.IsIndeterminate=state=="checking"; notes.Text=release?.Notes ?? "";
    }
    public async Task CheckAsync(bool manual) {
        if(manual) Show();
        if(busy || installing) return;
        if(phase is "ready" or "available") return;
        if(!manual) {
            var stamp=Path.Combine(InstallPlan.Root,"last-check.txt");
            try { if(File.Exists(stamp) && DateTime.UtcNow-File.GetLastWriteTimeUtc(stamp)<TimeSpan.FromHours(6)) return; Directory.CreateDirectory(InstallPlan.Root); File.WriteAllText(stamp,DateTime.UtcNow.ToString("O")); } catch(IOException) { } catch(UnauthorizedAccessException) { }
        }
        cancellation?.Dispose(); cancellation=new CancellationTokenSource(TimeSpan.FromSeconds(15)); State("checking","正在检查最新版本…");
        try {
            using var client=new UpdateClient(); release=await client.CheckAsync(UpdateInstaller.CurrentVersion,cancellation.Token);
            State(release==null ? "latest" : "available",release==null ? $"当前 v{UpdateInstaller.CurrentVersion} 已是最新稳定版本。" : $"发现新版本 v{release.Version}");
            if(release!=null) Show();
        } catch(Exception ex) { State("failed","检查更新失败，请检查网络后重试。\n"+ex.Message); }
    }
    private async Task DownloadAsync() {
        if(busy || release==null) return;
        Cleanup(); cancellation?.Dispose(); cancellation=new CancellationTokenSource(TimeSpan.FromMinutes(30));
        var token=cancellation.Token; var id=Guid.NewGuid().ToString("D"); var workspace=Path.Combine(InstallPlan.Root,id);
        State("downloading","正在下载并校验更新…"); progress.Value=0;
        try {
            Directory.CreateDirectory(workspace); var zip=Path.Combine(workspace,"update.zip");
            using var client=new UpdateClient();
            await client.DownloadAsync(release,zip,new Progress<double>(value => { progress.Value=value; message.Text=$"正在下载更新… {value:P0}"; }),token);
            message.Text="正在校验并准备更新…";
            var payload=await Task.Run(()=>UpdateClient.ExtractExe(zip,workspace),token);
            plan=await Task.Run(()=>UpdateInstaller.Prepare(payload,Environment.ProcessPath!,release.Version,id),token);
            token.ThrowIfCancellationRequested();
            State("ready",$"v{release.Version} 已准备好。重启后完成更新，设置会保留；本次临时充电计时将结束。"); Show();
        } catch(OperationCanceledException) { Cleanup(); State("available","下载已取消，可重新下载。"); }
        catch(Exception ex) { Cleanup(); State("failed","更新准备失败："+ex.Message+"\n请确认应用目录有写入权限。"); }
        finally { if(plan==null) { try { Directory.Delete(workspace,true); } catch { } } }
    }
    private void Install() {
        if(plan==null || installing) return;
        try { using var helper=UpdateInstaller.Start(plan); installing=true; Application.Current.Shutdown(); }
        catch(Exception ex) { State("failed","无法启动更新助手："+ex.Message); }
    }
    private void Cleanup() {
        if(plan!=null && !installing) {
            try { UpdateInstaller.Discard(plan); Directory.Delete(plan.Workspace,true); } catch(IOException) { } catch(UnauthorizedAccessException) { }
            plan=null;
        }
    }
    public void Close() { cancellation?.Cancel(); Cleanup(); installing=true; window?.Close(); }
    public static async Task<bool> HandleLaunchAsync() {
        var args=Environment.GetCommandLineArgs();
        if(args.Length!=3 || !Guid.TryParseExact(args[2],"D",out _)) return false;
        if(args[1]=="--paysprout-updated") {
            await Task.Delay(300);
            var plan=UpdateInstaller.Acknowledge(args[2]);
            if(plan?.SmokeTest==true) { await Task.Delay(1200); Application.Current.Shutdown(); return true; }
        } else if(args[1]=="--paysprout-rollback") MessageBox.Show("更新未完成，已恢复旧版。薪资与窗口设置已保留，请稍后重试。","薪芽 · 软件更新");
        return false;
    }
}
