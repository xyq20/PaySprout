using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace PaySprout;
public partial class MainWindow : Window
{
    private readonly Settings preferences = Settings.Load();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(33) };
    private readonly Forms.NotifyIcon tray;
    private BreakSession? pause;
    private bool preview, editing, resizing, night;
    private int quote;
    private DateTime nextStatus = DateTime.MinValue;
    private string? reward;
    private readonly string[] quotes = { "慢慢来，你已经在向前了。", "认真生活的你，值得每一份回报。", "今天的努力，都在为自由攒底气。", "不必时刻满分，尽力就很了不起。", "工作只是生活的一部分，别忘了自己。", "再小的一步，也是在靠近下班。" };
    private readonly string[] titles = { "正在蓄力", "努力发芽", "茁壮成长", "快要开花", "今日开花" };
    private readonly string[] messages = { "先伸个懒腰，等阳光来上班。", "你在赚钱，我在长叶，一起慢慢来。", "已经过半啦，自由又近了一点。", "花苞准备好了，就等下班这一刻。", "今天的小花送给你，辛苦啦。" };

    public MainWindow()
    {
        InitializeComponent();
        using var iconStream = Application.GetResourceStream(new Uri("AppIcon.ico", UriKind.Relative))!.Stream;
        tray = new Forms.NotifyIcon { Text = "薪芽 · 上班鼓励器", Icon = new System.Drawing.Icon(iconStream), Visible = true };
        var trayMenu = new Forms.ContextMenuStrip();
        trayMenu.Items.Add("显示薪芽", null, (_, _) => Restore());
        trayMenu.Items.Add("完整 / 紧凑模式", null, (_, _) => { Restore(); ToggleCompact(); });
        trayMenu.Items.Add("偏好设置", null, (_, _) => { Restore(); OpenSettings(); });
        trayMenu.Items.Add("带薪充电 / 结束充电", null, (_, _) => { Restore(); ToggleBreak(); });
        trayMenu.Items.Add("预览下班彩蛋", null, (_, _) => { Restore(); TogglePreview(); });
        trayMenu.Items.Add("退出", null, (_, _) => Close());
        tray.ContextMenuStrip = trayMenu;
        tray.DoubleClick += (_, _) => Restore();
        timer.Tick += (_, _) => Tick();
        IsVisibleChanged += (_, _) => { if (IsVisible) { nextStatus = DateTime.MinValue; timer.Start(); } else timer.Stop(); UpdateMotion(); };
        StateChanged += (_, _) => { if (WindowState == WindowState.Minimized) Hide(); };
        SizeChanged += (_, _) => RememberSize();
        PreviewKeyDown += OnKey;
        Closed += (_, _) => { timer.Stop(); tray.Dispose(); TrySave(); };
        Loaded += async (_, _) => {
            ApplyMode(); Tick(); timer.Start();
            if (Environment.GetCommandLineArgs().Contains("--smoke-test")) {
                try { await SmokeTest.Run(this); Application.Current.Shutdown(0); }
                catch (Exception ex) { Console.Error.WriteLine(ex); File.WriteAllText("smoke-error.txt",ex.ToString()); Application.Current.Shutdown(1); }
            }
        };
    }

    private void Tick()
    {
        var now = DateTime.Now;
        var shift = Shift.Make(now,preferences.StartMinutes,preferences.EndMinutes);
        Amount.Text = CompactAmount.Text = "¥" + Money.Text(shift.Earned(preferences.DailyPay));
        if (now < nextStatus) return;
        nextStatus = now.AddSeconds(1);
        if (shift.ShouldCelebrate(preferences.LastCelebrated)) {
            preferences.LastCelebrated = shift.Start;
            TrySave(); Fireworks.Play();
        }
        var isNight = preview || shift.Fraction >= 1;
        if (isNight != night) { night = isNight; ApplyPalette(); }
        TargetText.Text = "目标 ¥" + Money.Text(preferences.DailyPay);
        RateText.Text = now < shift.Start ? "小金库等待开工" : shift.Fraction >= 1 ? "今日小金库已攒满" : "每秒 +¥" + Money.Text(preferences.DailyPay / shift.Seconds);
        CountdownTitle.Text = night ? (preview ? "下班彩蛋 · 预览" : "属于你的夜晚") : "下班倒数";
        CountdownText.Text = night ? "下班啦，今天也很棒！" : now < shift.Start ? "上班前，好好充电" : $"{shift.Remaining/3600:00} : {shift.Remaining%3600/60:00} : {shift.Remaining%60:00}";
        CountdownText.FontSize = night ? 21 : 26;
        CompactCountdown.Text = night ? (preview ? "下班彩蛋 · 预览" : "把时间还给自己") : now < shift.Start ? "上班前，好好充电" : $"距下班 {shift.Remaining/3600}时{shift.Remaining%3600/60:00}分";
        Progress.Value = CompactProgress.Value = shift.Fraction;
        ProgressText.Text = night ? "今天的努力已收好，把时间还给自己。" : $"{shift.Fraction:P0} 完成 · {TimeText(preferences.EndMinutes)}{(preferences.EndMinutes < preferences.StartMinutes ? " 次日" : "")} 下班";
        EndPreview.Visibility = preview ? Visibility.Visible : Visibility.Collapsed;
        var stage = Growth.Stage(night ? 1 : shift.Fraction);
        StageText.Text = pause != null && !night ? "金色爆气 · 带薪充电中" : titles[stage];
        QuoteText.Text = reward ?? (quote == 0 ? messages[stage] : quotes[quote]);
        BreakButton.Content = pause == null ? "带薪充电" : $"爆气中 {pause.Elapsed(now)/60:00}:{pause.Elapsed(now)%60:00}";
        BreakButton.Background = Brush(pause == null ? "#E8F2E8" : "#FFDF64");
        Buddy.Progress = CompactBuddy.Progress = night ? 1 : shift.Fraction;
        Buddy.Charging = CompactBuddy.Charging = pause != null && !night;
        Buddy.InvalidateVisual(); CompactBuddy.InvalidateVisual(); UpdateMotion();
    }

    private void ApplyPalette()
    {
        foreach (var (key, light, dark) in new[] {
            ("Ink","#293831","#FFF2FC"), ("Muted","#646E66","#D4BDDA"),
            ("Accent","#3D6E54","#FFB3D4"), ("Surface","#F6F3EB","#2C203B"),
            ("Canvas","#FEFEFA","#1C142D"), ("Line","#DDE3D9","#644766") })
            Resources[key] = Brush(night ? dark : light);
    }
    private static SolidColorBrush Brush(string value) => new((Color)ColorConverter.ConvertFromString(value));
    private static string TimeText(int minutes) => $"{minutes/60:00}:{minutes%60:00}";
    private void UpdateMotion()
    {
        Buddy.Animate = IsVisible && !preferences.Compact && !editing && SystemParameters.ClientAreaAnimation;
        CompactBuddy.Animate = IsVisible && preferences.Compact && !editing && SystemParameters.ClientAreaAnimation;
        Fireworks.Animate = IsVisible && !editing && SystemParameters.ClientAreaAnimation;
    }
    private void Restore() { Show(); WindowState = WindowState.Normal; Activate(); Tick(); }
    private void DragTitle(object sender, MouseButtonEventArgs e) {
        if (e.OriginalSource is DependencyObject source) {
            while (source != null) { if (source is Button || source is SproutView) return; source = VisualTreeHelper.GetParent(source); }
        }
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }
    private void CheerClick(object sender, MouseButtonEventArgs e) { reward = null; quote = (quote + 1) % quotes.Length; nextStatus = DateTime.MinValue; Tick(); e.Handled = true; }
    private void CompactClick(object sender, RoutedEventArgs e) => ToggleCompact();
    private void ToggleCompact() { RememberSize(); editing = false; preferences.Compact = !preferences.Compact; ApplyMode(); TrySave(); }
    private void ApplyMode()
    {
        resizing = true;
        FullBox.Visibility = !preferences.Compact && !editing ? Visibility.Visible : Visibility.Collapsed;
        CompactBox.Visibility = preferences.Compact && !editing ? Visibility.Visible : Visibility.Collapsed;
        SettingsBox.Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
        MinWidth = preferences.Compact ? 345 : 535; MinHeight = preferences.Compact ? 105 : 320;
        var area = SystemParameters.WorkArea;
        Width = Math.Clamp(preferences.Compact ? preferences.CompactWidth : preferences.FullWidth,MinWidth,Math.Max(MinWidth,area.Width));
        Height = Math.Clamp(preferences.Compact ? preferences.CompactHeight : preferences.FullHeight,MinHeight,Math.Max(MinHeight,area.Height));
        Left = Math.Clamp(Left,area.Left,Math.Max(area.Left,area.Right - Width));
        Top = Math.Clamp(Top,area.Top,Math.Max(area.Top,area.Bottom - Height));
        Shell.Padding = new Thickness(preferences.Compact ? 10 : 18);
        resizing = false; nextStatus = DateTime.MinValue; UpdateMotion();
    }
    private void RememberSize() {
        if (resizing || !IsLoaded) return;
        if (preferences.Compact) { preferences.CompactWidth = Width; preferences.CompactHeight = Height; }
        else { preferences.FullWidth = Width; preferences.FullHeight = Height; }
    }
    private void SizeClick(object sender, RoutedEventArgs e) {
        var menu = new ContextMenu();
        foreach (var scale in new[]{.8,1,1.2,1.4}) {
            var item = new MenuItem { Header = $"{scale:P0}", IsCheckable = true, IsChecked = Math.Abs(preferences.Scale - scale) < .01 };
            item.Click += (_, _) => { preferences.Scale = scale; if (preferences.Compact) { preferences.CompactWidth = 404*scale+20; preferences.CompactHeight = 104*scale+20; } else { preferences.FullWidth = 640*scale+20; preferences.FullHeight = 372*scale+20; } ApplyMode(); TrySave(); };
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        var custom = new MenuItem { Header = "自定义大小…" }; custom.Click += (_, _) => CustomSize(); menu.Items.Add(custom);
        menu.PlacementTarget = (UIElement)sender; menu.IsOpen = true;
    }
    private void CustomSize() {
        var dialog = new Window { Title="自定义大小", Width=320, Height=230, Owner=this, WindowStartupLocation=WindowStartupLocation.CenterOwner, ResizeMode=ResizeMode.NoResize, Background=Brush("#FEFEFA"), Foreground=Brush("#293831") };
        var panel = new StackPanel { Margin=new Thickness(20) }; dialog.Content=panel;
        panel.Children.Add(new TextBlock { Text="窗口宽 × 高（也可拖动右下角）" });
        var width = new TextBox { Text=((int)Width).ToString(), Margin=new Thickness(0,10,0,6) }; panel.Children.Add(width);
        var height = new TextBox { Text=((int)Height).ToString() }; panel.Children.Add(height);
        var apply = new Button { Content="应用", IsDefault=true, Margin=new Thickness(0,10,0,0) }; panel.Children.Add(apply);
        apply.Click += (_, _) => { if (!double.TryParse(width.Text,out var w) || !double.TryParse(height.Text,out var h) || !double.IsFinite(w) || !double.IsFinite(h) || w < MinWidth || h < MinHeight) { MessageBox.Show(dialog,$"最小尺寸为 {MinWidth} × {MinHeight}。","检查尺寸"); return; } Width=Math.Min(w,SystemParameters.WorkArea.Width); Height=Math.Min(h,SystemParameters.WorkArea.Height); RememberSize(); TrySave(); dialog.Close(); };
        dialog.ShowDialog();
    }
    private void MoreClick(object sender,RoutedEventArgs e) {
        var menu = new ContextMenu();
        void Item(string title,Action action) { var item = new MenuItem { Header=title }; item.Click += (_,_) => action(); menu.Items.Add(item); }
        Item("展开完整模式",ToggleCompact); Item("偏好设置",OpenSettings); Item("调整大小…",CustomSize); Item(pause == null ? "带薪充电" : "结束充电",ToggleBreak); Item(preview ? "结束预览" : "预览下班彩蛋",TogglePreview); Item("收起到系统托盘",Hide); Item("退出",Close);
        menu.PlacementTarget=(UIElement)sender; menu.IsOpen=true;
    }
    private void SettingsClick(object sender,RoutedEventArgs e) => OpenSettings();
    internal void OpenSettings() {
        RememberSize(); preferences.Compact=false; editing=true;
        PayInput.Text=preferences.DailyPay.ToString("0.####",CultureInfo.CurrentCulture);
        StartInput.Text=TimeText(preferences.StartMinutes); EndInput.Text=TimeText(preferences.EndMinutes);
        SettingsError.Text=""; ApplyMode(); PayInput.Focus(); PayInput.SelectAll();
    }
    private void SaveSettings(object sender,RoutedEventArgs e) => SaveDraft();
    internal bool SaveDraft() {
        bool Time(string text,out int minutes) { minutes=0; if (!DateTime.TryParseExact(text.Trim(),new[]{"H:mm","HH:mm"},CultureInfo.InvariantCulture,DateTimeStyles.None,out var value)) return false; minutes=value.Hour*60+value.Minute; return true; }
        if (!double.TryParse(PayInput.Text,NumberStyles.Float,CultureInfo.CurrentCulture,out var pay) || !Time(StartInput.Text,out var start) || !Time(EndInput.Text,out var end) || !Preferences.Valid(pay,start,end)) {
            SettingsError.Text="请输入 0–10000000 的日薪和有效的 HH:mm 时间，上下班时间不能相同。"; return false;
        }
        var oldPay=preferences.DailyPay; var oldStart=preferences.StartMinutes; var oldEnd=preferences.EndMinutes;
        preferences.DailyPay=pay; preferences.StartMinutes=start; preferences.EndMinutes=end;
        try { preferences.Save(); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { preferences.DailyPay=oldPay; preferences.StartMinutes=oldStart; preferences.EndMinutes=oldEnd; SettingsError.Text="保存失败，请检查用户目录是否可写。"; return false; }
        editing=false; ApplyMode(); Tick(); return true;
    }
    private void CancelSettings(object sender,RoutedEventArgs e) { editing=false; ApplyMode(); }
    private void PreviewClick(object sender,RoutedEventArgs e) => TogglePreview();
    internal void TogglePreview() { preview=!preview; if (preview) Fireworks.Play(); else Fireworks.Stop(); nextStatus=DateTime.MinValue; Tick(); }
    private void BreakClick(object sender,RoutedEventArgs e) => ToggleBreak();
    internal void ToggleBreak() {
        var now=DateTime.Now;
        if (pause == null) { pause=BreakSession.Begin(now,preferences.DailyPay,preferences.StartMinutes,preferences.EndMinutes); reward=null; }
        else { reward=$"充电 {pause.Elapsed(now)/60}分{pause.Elapsed(now)%60}秒，期间估算收入 ¥{Money.Text(pause.Earnings(now))}。"; pause=null; }
        nextStatus=DateTime.MinValue; Tick();
    }
    private void HideClick(object sender,RoutedEventArgs e) { TrySave(); Hide(); }
    private void ExitClick(object sender,RoutedEventArgs e) => Close();
    private void TrySave() { try { preferences.Save(); } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { tray.ShowBalloonTip(3000,"设置未保存","请检查用户目录是否可写。",Forms.ToolTipIcon.Warning); } }
    private void OnKey(object sender,KeyEventArgs e) {
        if (e.Key == Key.OemComma && Keyboard.Modifiers == ModifierKeys.Control) { OpenSettings(); e.Handled=true; }
        else if (editing && e.Key == Key.Escape) { editing=false; ApplyMode(); e.Handled=true; }
        else if (editing && e.Key == Key.Return) { SaveDraft(); e.Handled=true; }
    }

    internal void SmokeCompact() => ToggleCompact();
    internal void Capture(string path) {
        UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);
        bitmap.Render(this); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream=File.Create(path); encoder.Save(stream);
    }
}
