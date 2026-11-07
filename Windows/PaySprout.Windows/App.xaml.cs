using System;
using System.IO;
using System.Windows;

namespace PaySprout;
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += (_, args) => {
            try { Directory.CreateDirectory(Settings.Folder); File.AppendAllText(Path.Combine(Settings.Folder,"error.log"), DateTime.Now + " " + args.Exception + Environment.NewLine); } catch { }
            MessageBox.Show("薪芽遇到了问题，请重新打开。错误记录位于：\n" + Settings.Folder,"薪芽");
            args.Handled = true;
            Shutdown(1);
        };
        base.OnStartup(e);
    }
}
