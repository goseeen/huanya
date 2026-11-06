using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Huanya.Core;

namespace Huanya.Desktop;

public static class UI
{
    public static TextBlock Text(string text, double size = 13, IBrush? color = null, bool bold = false) => new() { Text = text, FontSize = size, Foreground = color ?? Colors.Ink, FontWeight = bold ? FontWeight.SemiBold : FontWeight.Normal, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
    public static StackPanel Stack(params Control[] children)
    {
        var s = new StackPanel { Spacing = 14 };
        foreach (var c in children)
            s.Children.Add(c);
        return s;
    }
    public static StackPanel Row(params Control[] children)
    {
        var s = Stack(children);
        s.Orientation = Orientation.Horizontal;
        s.Spacing = 12;
        return s;
    }
    public static Grid Columns(params Control[] children)
    {
        var g = new Grid { ColumnDefinitions = new ColumnDefinitions(string.Join(',', children.Select(_ => "*"))), ColumnSpacing = 16 };
        for (int i = 0; i < children.Length; i++)
        {
            Grid.SetColumn(children[i], i);
            g.Children.Add(children[i]);
        }
        return g;
    }
    public static Grid Apart(Control left, Control right)
    {
        var g = new Grid { ColumnDefinitions = new("*,Auto"), ColumnSpacing = 14 };
        g.Children.Add(left);
        Grid.SetColumn(right, 1);
        g.Children.Add(right);
        return g;
    }
    public static Border Card(Control child, IBrush? background = null, double padding = 22, double radius = 16) => new() { Child = child, Background = background ?? Brushes.White, Padding = new Thickness(padding), CornerRadius = new CornerRadius(radius), BorderBrush = Colors.Line, BorderThickness = new Thickness(background == null ? 1 : 0) };
    public static Button Button(string text, Action action, string style = "")
    {
        var b = new Button { Content = text };
        if (style.Length > 0)
        foreach (var c in style.Split(' '))
            b.Classes.Add(c);
        b.Click += (_, _) => action();
        return b;
    }
    public static NumericUpDown Number(int value, int min, int max, Action<int>? changed = null)
    {
        var n = new NumericUpDown { Value = value, Minimum = min, Maximum = max, Increment = 1, FormatString = "0", Width = 110 };
        if (changed != null)
            n.ValueChanged += (_, _) => { if (n.Value is { } v) changed((int)v); };
        return n;
    }
    public static ToggleSwitch Toggle(bool value, Action<bool> action)
    {
        var t = new ToggleSwitch { IsChecked = value, OnContent = "", OffContent = "", VerticalAlignment = VerticalAlignment.Center };
        t.IsCheckedChanged += (_, _) => action(t.IsChecked == true);
        return t;
    }
    public static Control Setting(string title, string detail, Control action)
    {
        var text = Stack(Text(title, 14, bold: true), Text(detail, 11, Colors.Muted));
        text.Spacing = 5;
        return Apart(text, action);
    }
    public static TextBlock Serif(string text, double size, IBrush? color = null)
    {
        var t = Text(text, size, color);
        t.FontFamily = new FontFamily("SimSun, Songti SC, serif");
        return t;
    }
    public static Control Icon(string name, IBrush? color = null, double size = 22) => new Artwork { Drawing = name, Color = color ?? Colors.Green, Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
    public static Image Logo(double size = 40) => new() { Source = new Bitmap(AssetLoader.Open(new Uri("avares://Huanya/Assets/huanya.png"))), Width = size, Height = size };
    public static Border Line() => new() { Background = Colors.Line, Height = 1, Margin = new Thickness(0, 4) };
    public static async Task Message(Window owner, string title, string message)
    {
        var w = new Window { Title = title, Width = 460, SizeToContent = SizeToContent.Height, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        w.Content = new Border { Padding = new Thickness(26), Child = Stack(Text(title, 20, bold: true), Text(message), Button("知道了", w.Close, "primary")) };
        await w.ShowDialog(owner);
    }
}
public sealed partial class MainWindow : Window
{
    readonly Controller app;
    Session S => app.Session;
    string page = "今日概览";
    readonly StackPanel content = new() { Spacing = 22, Margin = new Thickness(32, 5, 32, 28) };
    readonly TextBlock heading = UI.Text("今日概览", 23, bold: true), subtitle = UI.Text("小习惯，让好状态发生。", 11, Colors.Muted), status = UI.Text("", 10, Colors.Muted), dateLabel = UI.Text("", 11, Colors.Muted);
    readonly Button pause;
    readonly Border notice = UI.Card(UI.Text(""), Colors.Lime, 12, 10);
    readonly List<Action> live = [];
    readonly Dictionary<string, Button> navigation = [];
    bool reviewMonth; int reviewOffset;
    public MainWindow(Controller app)
    {
        this.app = app;
        Title = "缓芽 · huǎn yá" + (app.Preview ? " · Windows 界面预览" : "");
        Width = 1120;
        Height = 800;
        MinWidth = 1020;
        MinHeight = 650;
        Icon = new WindowIcon(AssetLoader.Open(new Uri("avares://Huanya/Assets/huanya.ico")));
        pause = UI.Button("暂停提醒", () => app.Act(() => S.Pause()));
        var root = new Grid { ColumnDefinitions = new("190,1,*") };
        root.Children.Add(Sidebar());
        var divider = new Border { Background = Colors.Line };
        Grid.SetColumn(divider, 1);
        root.Children.Add(divider);
        var main = new Grid { RowDefinitions = new("Auto,*") };
        Grid.SetColumn(main, 2);
        root.Children.Add(main);
        var labels = UI.Stack(heading, subtitle);
        labels.Spacing = 6;
        var header = UI.Apart(labels, UI.Row(dateLabel, pause));
        header.Margin = new Thickness(32, 29, 32, 25);
        main.Children.Add(header);
        var scroll = new ScrollViewer { Content = content, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        Grid.SetRow(scroll, 1);
        main.Children.Add(scroll);
        Content = root;
        RenderPage();
        Closing += (_, e) => { if (app.HideInsteadOfClose) { e.Cancel = true; Hide(); } else if (!app.IsExiting) { e.Cancel = true; app.Quit(); } };
    }
    Control Sidebar()
    {
        var grid = new Grid { RowDefinitions = new("Auto,*,Auto"), Background = Colors.Sidebar };
        var top = UI.Stack();
        top.Spacing = 5;
        var brandName = UI.Stack(UI.Text("缓芽", 25, Colors.Green, true), UI.Text("huǎn yá", 9, Colors.Muted));
        brandName.Spacing = 2;
        var brand = UI.Row(UI.Logo(43), brandName);
        brand.Margin = new Thickness(23, 31, 20, 40);
        top.Children.Add(brand);
        var caption = UI.Text("为自己，留一点时间", 10, Colors.Muted);
        caption.Margin = new Thickness(25, 0, 10, 13);
        top.Children.Add(caption);
        foreach (var (name, icon) in new[] { ("今日概览", "dashboard"), ("提醒计划", "bell"), ("健康统计", "stats"), ("设置", "settings") })
        {
            var b = UI.Button(name, () => SelectPage(name), "nav");
            b.Margin = new Thickness(13, 0);
            b.Content = UI.Row(UI.Icon(icon, Colors.Muted, 18), UI.Text(name, 13));
            navigation[name] = b;
            top.Children.Add(b);
        }
        grid.Children.Add(top);
        var bottom = UI.Stack(UI.Card(UI.Stack(UI.Icon("leaf", Colors.Green, 29), UI.Serif("工作很重要，\n你也是。", 18, Colors.Green), UI.Text("TAKE A LITTLE BREATH", 8, Colors.Muted)), Brush.Parse("#E4E9D8"), 20, 14), status);
        bottom.Margin = new Thickness(16, 0, 16, 23);
        Grid.SetRow(bottom, 2);
        grid.Children.Add(bottom);
        return grid;
    }
    public void SelectPage(string name)
    {
        page = name;
        RenderPage();
    }
    public void RenderPage()
    {
        live.Clear();
        content.Children.Clear();
        heading.Text = page;
        subtitle.Text = page switch
        {
            "提醒计划" => "找到适合你的节奏，让休息自然发生。",
            "健康统计" => "每一次小小的休息，都值得被看见。",
            "设置" => "让缓芽，更合你的习惯。",
            _ => "小习惯，让好状态发生。"
        };
        foreach (var (name, b) in navigation)
        {
            b.Classes.Set("selected", name == page);
            if (b.Content is StackPanel row)
            {
                ((Artwork)row.Children[0]).Color = name == page ? Colors.Green : Colors.Muted;
                ((TextBlock)row.Children[1]).Foreground = name == page ? Colors.Green : Colors.Muted;
                ((TextBlock)row.Children[1]).FontWeight = name == page ? FontWeight.SemiBold : FontWeight.Normal;
            }
        }
        content.Children.Add(notice);
        ShowNotice();
        content.Children.Add(page switch
        {
            "提醒计划" => Plans(),
            "健康统计" => Statistics(),
            "设置" => Settings(),
            _ => Dashboard()
        });
        UpdateLive();
    }
    public void ShowNotice()
    {
        notice.IsVisible = app.Notice != null;
        notice.Child = UI.Apart(UI.Text(app.Notice ?? "", 12, Colors.Green), UI.Button("关闭", () => { app.Notice = null; ShowNotice(); }, "link"));
    }
    public void UpdateLive()
    {
        status.Text = "●  " + S.Status;
        dateLabel.Text = S.Now.LocalDateTime.ToString("MM/dd dddd", System.Globalization.CultureInfo.GetCultureInfo("zh-CN"));
        pause.Content = S.Engine.Paused || S.Engine.BusyUntil != null ? "继续提醒" : "暂停提醒";
        foreach (var action in live)
            action();
    }
    TextBlock Live(Func<string> value, double size = 13, IBrush? color = null)
    {
        var t = UI.Text(value(), size, color);
        live.Add(() => t.Text = value());
        return t;
    }
    Control Dashboard()
    {
        var next = Live(() => S.Active != null ? "休息剩余" : S.Engine.Batches(S.Now).FirstOrDefault() is { } b ? "下次 · " + b.Title : S.Status, 11, Brush.Parse("#B3FFFFFF"));
        next.HorizontalAlignment = HorizontalAlignment.Center;
        var countdown = Live(() => S.Active != null ? Labels.Clock(S.Remaining) : S.Countdown, 32, Colors.Lime);
        countdown.HorizontalAlignment = HorizontalAlignment.Center;
        var progress = new ProgressRing();
        var ring = new Grid { Width = 140, Height = 140, Children = { progress, new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Children = { countdown, UI.Text("慢慢来，不着急", 9, Brush.Parse("#80FFFFFF")) } } } };
        live.Add(() => { var batch = S.Engine.Batches(S.Now).FirstOrDefault(); progress.Progress = S.Active is { } rest ? 1 - (double)S.Remaining / Math.Max(1, rest.Duration) : batch is null ? 0 : 1 - (batch.DueAt - S.Now).TotalSeconds / (batch.Planned is null ? S.Prefs[batch.Kinds[0]].IntervalMinutes * 60 : Math.Max(60, (batch.DueAt - batch.DueAt.LocalDateTime.Date).TotalSeconds)); });
        var hero = new Grid { ColumnDefinitions = new("*,160,157"), ColumnSpacing = 10 };
        var intro = UI.Stack(UI.Text("● A MOMENT FOR YOURSELF", 9, Colors.Lime, true), UI.Serif("坐久了，\n就起身走走。", 30, Brush.Parse("#FAFBEF")), UI.Text("从一杯水、一次远眺、一个伸展开始。", 11, Brush.Parse("#99FFFFFF")), UI.Button("现在休息一下  ↗", () => app.Act(() => S.Offer([Kind.Stretch])), "primary lime"));
        intro.Spacing = 17;
        hero.Children.Add(intro);
        var illustration = new Artwork { Drawing = "plant", Width = 160, Height = 200 };
        Grid.SetColumn(illustration, 1);
        hero.Children.Add(illustration);
        var clock = UI.Stack(next, ring);
        clock.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(clock, 2);
        hero.Children.Add(clock);
        var cards = Labels.Kinds.Select(k => Ritual(k)).ToArray();
        var usage = UI.Card(UI.Stack(UI.Text("本轮使用时长（估算）", 14, bold: true), UI.Apart(Live(() => $"{(int)(S.Engine.SittingSeconds / 60)} 分钟", 27, Colors.Green), UI.Button("我已起身 ✓", () => app.Act(() => S.Engine.StoodUp(S.Now)))), UI.Text("连续使用估算，不代表实际坐姿。", 10, Colors.Muted), Live(() => $"今日累计工作 {(int)(Today.WorkSeconds / 60)} 分钟", 11, Colors.Muted)));
        var events = S.Engine.Saved.Events.Where(e => e.VoidedAt == null && (e.RecordDay ?? Labels.Day(e.Date)) == Labels.Day(S.Now)).Take(4).ToArray();
        var activity = UI.Stack(UI.Text("今天的小小进步", 14, bold: true));
        if (events.Length == 0)
            activity.Children.Add(UI.Text("好习惯，从这一次开始。\n喝一杯水，或完成一次休息。", 12, Colors.Muted));
        foreach (var e in events)
            activity.Children.Add(UI.Apart(UI.Text($"{e.Date.LocalDateTime:HH:mm}  {e.Kind.Short()}", 12), UI.Text(e.Kind == Kind.Water ? $"{e.Amount} ml" : Labels.Duration(e.Amount), 12, Colors.Muted)));
        if (S.Engine.WaterUndoId != null)
            activity.Children.Add(UI.Button("撤销最近一杯饮水", () => app.Act(() => S.Engine.UndoWater(S.Now)), "link"));
        return UI.Stack(UI.Card(hero, Colors.Green, 27, 20), UI.Apart(UI.Text("给身体的三个小约定", 15, bold: true), UI.Button("调整计划 ↗", () => SelectPage("提醒计划"), "link")), UI.Columns(cards), UI.Columns(usage, UI.Card(activity)), UI.Text("只在本机记录 · 无需登录 · 关闭窗口后，在系统托盘继续运行", 10, Colors.Muted));
    }
    DayRecord Today => S.Engine.Saved.Days.GetValueOrDefault(Labels.Day(S.Now)) ?? new();
    Control Ritual(Kind k)
    {
        var icon = UI.Card(UI.Icon(k.ToString().ToLowerInvariant(), Colors.Accent(k), 25), Colors.Wash(k), 9, 12);
        icon.HorizontalAlignment = HorizontalAlignment.Left;
        icon.Width = 43;
        icon.Height = 43;
        var count = UI.Row(Live(() => k == Kind.Water ? $"{Today.WaterML}" : $"{(k == Kind.Eyes ? Today.EyeBreaks : Today.Stretches)}", 26), UI.Text(k == Kind.Water ? $"/ {S.Prefs.WaterGoalML} ml" : "次 · 今日完成", 10, Colors.Muted));
        var track = new ProgressTrack { Height = 4, Track = Colors.Wash(k), Fill = Colors.Accent(k) };
        live.Add(() => track.Fraction = k == Kind.Water ? (double)Today.WaterML / S.Prefs.WaterGoalML : (double)(k == Kind.Eyes ? Today.EyeBreaks : Today.Stretches) / S.Prefs.BreakGoal);
        return UI.Card(UI.Stack(UI.Apart(icon, UI.Text(S.Prefs[k].Enabled ? $"每 {S.Prefs[k].IntervalMinutes} 分钟" : "已关闭", 10, Colors.Muted)), UI.Text(k.Title(), 14, bold: true), count, track, UI.Button(k == Kind.Water ? "+ 记一杯水" : "开始一次休息", () => app.Act(() => { if (k == Kind.Water) S.Water(); else S.Offer([k]); }), "link")), padding: 16);
    }
    Control Plans()
    {
        var body = UI.Stack(UI.Card(UI.Stack(UI.Text("休息，是工作节奏的一部分。", 24, Colors.Green), UI.Text("分别调整间隔，按你的习惯来。修改后，该项会重新开始计时。", 11, Colors.Muted)), Colors.Sidebar));
        foreach (var kind in Labels.Kinds)
        {
            var k = kind;
            var p = S.Prefs[k];
            var fields = UI.Row(UI.Text("提醒间隔", 12), UI.Number(p.IntervalMinutes, 1, 180, v => app.Edit(x => x[k].IntervalMinutes = v)), UI.Text("分钟", 12, Colors.Muted));
            if (k != Kind.Water)
            {
                var mins = UI.Number(p.DurationSeconds / 60, 0, 10);
                var seconds = UI.Number(p.DurationSeconds % 60, 0, 59);
                fields.Children.Add(UI.Text("休息时长", 12));
                fields.Children.Add(mins);
                fields.Children.Add(UI.Text("分"));
                fields.Children.Add(seconds);
                fields.Children.Add(UI.Text("秒"));
                fields.Children.Add(UI.Button("保存", () => { int total = (int)(mins.Value ?? 0) * 60 + (int)(seconds.Value ?? 0); if (total is < 10 or > 600) { app.Notice = "休息时长请设置为 10 秒至 10 分钟。"; ShowNotice(); return; } app.Edit(x => x[k].DurationSeconds = total); app.Notice = "休息时长已保存。"; ShowNotice(); }));
            }
            body.Children.Add(UI.Card(UI.Stack(UI.Apart(UI.Row(UI.Icon(k.ToString().ToLowerInvariant(), Colors.Accent(k), 28), UI.Stack(UI.Text(k.Title(), 16, bold: true), UI.Text(k.Message(), 11, Colors.Muted))), UI.Toggle(p.Enabled, v => app.Edit(x => x[k].Enabled = v))), fields)));
        }
        body.Children.Add(UI.Card(UI.Stack(UI.Text("每周作息", 16, bold: true), UI.Setting("按星期安排提醒时段", "每天可设置 1–4 个时段，支持午间停歇。", UI.Toggle(S.Prefs.WeeklyRoutineEnabled, v => app.Edit(p => p.WeeklyRoutineEnabled = v))), UI.Button("编辑每周作息", () => OpenRoutine()), UI.Line(), UI.Setting("仅工作日提醒", "关闭每周作息后使用：周一至周五。", UI.Toggle(S.Prefs.WeekdaysOnly, v => app.Edit(p => p.WeekdaysOnly = v))), UI.Setting("仅在每日时段提醒", "关闭每周作息后使用；开始、结束相同时为全天。", UI.Toggle(S.Prefs.WorkHoursOnly, v => app.Edit(p => p.WorkHoursOnly = v))), UI.Row(UI.Text("开始（时）"), UI.Number(S.Prefs.StartHour, 0, 23, v => app.Edit(p => p.StartHour = v)), UI.Text("结束（时）"), UI.Number(S.Prefs.EndHour, 0, 23, v => app.Edit(p => p.EndHour = v))))));
        body.Children.Add(UI.Card(UI.Stack(UI.Setting("长休息", "完成指定次数的起身拉伸后，安排一次长休息。", UI.Toggle(S.Prefs.LongBreak.Enabled, v => app.Edit(p => p.LongBreak.Enabled = v))), UI.Row(UI.Text("每"), UI.Number(S.Prefs.LongBreak.Every, 2, 12, v => app.Edit(p => p.LongBreak.Every = v)), UI.Text("次，休息"), UI.Number(S.Prefs.LongBreak.DurationSeconds / 60, 1, 30, v => app.Edit(p => p.LongBreak.DurationSeconds = v * 60)), UI.Text("分钟")))));
        var planned = UI.Stack(UI.Apart(UI.Text("固定提醒", 16, bold: true), UI.Button("+ 添加提醒", () => OpenPlanned(null))));
        foreach (var item in S.Prefs.PlannedBreaks)
        {
            var p = item;
            planned.Children.Add(UI.Apart(UI.Stack(UI.Text($"{p.Name} · {p.Minute / 60:00}:{p.Minute % 60:00}", 13, bold: true), UI.Text($"{p.Kind.Short()} · {Labels.Duration(p.DurationSeconds)} · {string.Join('、', p.Weekdays.Select(d => new[] { "日", "一", "二", "三", "四", "五", "六" }[d - 1]))}", 11, Colors.Muted)), UI.Row(UI.Toggle(p.Enabled, v => app.Edit(x => x.PlannedBreaks.First(i => i.Id == p.Id).Enabled = v)), UI.Button("编辑", () => OpenPlanned(p)))));
        }
        body.Children.Add(UI.Card(planned));
        return body;
    }
    Control Settings()
    {
        var body = UI.Stack(UI.Card(UI.Stack(UI.Setting("浮窗提醒", "到时间显示休息窗口；关闭后通过 Windows 通知提醒。", UI.Toggle(S.Prefs.FloatingReminder, v => app.Edit(p => p.FloatingReminder = v))), UI.Line(), UI.Setting("提醒声音", "到期时播放系统提示音。", UI.Toggle(S.Prefs.Sound, v => app.Edit(p => p.Sound = v))), UI.Line(), UI.Setting("提前提醒", "临近提醒时提示收尾，点击即可开始休息。", UI.Toggle(S.Prefs.PrewarningEnabled, v => app.Edit(p => p.PrewarningEnabled = v))), UI.Row(UI.Text("提前秒数"), UI.Number(S.Prefs.PrewarningSeconds, 10, 60, v => app.Edit(p => p.PrewarningSeconds = v))), UI.Line(), UI.Setting("合并接近的提醒", "合并显示，每项分别记录完成情况。", UI.Toggle(S.Prefs.MergeReminders, v => app.Edit(p => p.MergeReminders = v))), UI.Row(UI.Text("合并范围（秒）"), UI.Number(S.Prefs.MergeWindowSeconds, 0, 300, v => app.Edit(p => p.MergeWindowSeconds = v))), UI.Line(), UI.Setting("拉伸动作卡片", "每 20 秒自动切换，也可以手动切换。", UI.Toggle(S.Prefs.StretchCardsEnabled, v => app.Edit(p => p.StretchCardsEnabled = v))))));
        var busy = UI.Stack(UI.Setting("空闲时暂停", "没有键盘鼠标操作时暂停提醒；锁屏始终暂停。", UI.Toggle(S.Prefs.IdlePauseEnabled, v => app.Edit(p => p.IdlePauseEnabled = v))), UI.Row(UI.Text("空闲分钟"), UI.Number(S.Prefs.IdlePauseMinutes, 1, 30, v => app.Edit(p => p.IdlePauseMinutes = v))), UI.Line(), UI.Text("指定应用在前台时暂停", 14, bold: true), UI.Text("切回其他应用后继续剩余倒计时。这不代表自动识别会议。", 11, Colors.Muted));
        foreach (var a in S.Prefs.BusyApplications)
            busy.Children.Add(UI.Apart(UI.Text(a.Name), UI.Button("移除", () => { app.Edit(p => p.BusyApplications.RemoveAll(i => i.Path == a.Path)); RenderPage(); })));
        busy.Children.Add(UI.Button("选择应用 .exe", async () => await ChooseApp()));
        busy.Children.Add(UI.Line());
        busy.Children.Add(UI.Row(UI.Button("忙碌 30 分钟", () => app.Act(() => S.Busy(30))), UI.Button("忙碌 60 分钟", () => app.Act(() => S.Busy(60))), UI.Button("结束忙碌", () => app.Act(() => S.Busy(null)))));
        body.Children.Add(UI.Card(busy));
        var startup = UI.Toggle(WindowsServices.StartupEnabled, v => { try { WindowsServices.SetStartup(v); } catch (Exception e) { app.Notice = e.Message; ShowNotice(); } });
        startup.IsEnabled = !app.Preview;
        body.Children.Add(UI.Card(UI.Stack(UI.Setting("开机启动", "登录 Windows 后在托盘运行。移动程序后需重新设置。", startup), UI.Line(), UI.Setting("全局快捷键", "Ctrl + Alt + Shift + W 记水；Ctrl + Alt + Shift + R 起身休息。", UI.Toggle(S.Prefs.GlobalShortcutsEnabled, v => app.Edit(p => p.GlobalShortcutsEnabled = v))), UI.Line(), UI.Setting("托盘倒计时", "鼠标悬停托盘图标时显示剩余时间。", UI.Toggle(S.Prefs.ShowMenuCountdown, v => app.Edit(p => p.ShowMenuCountdown = v))))));
        body.Children.Add(UI.Card(UI.Stack(UI.Text("饮水与休息目标", 16, bold: true), UI.Row(UI.Text("默认杯量 ml"), UI.Number(S.Prefs.WaterML, 50, 1000, v => app.Edit(p => p.WaterML = v)), UI.Text("每日饮水 ml"), UI.Number(S.Prefs.WaterGoalML, 250, 6000, v => app.Edit(p => p.WaterGoalML = v)), UI.Text("休息次数"), UI.Number(S.Prefs.BreakGoal, 1, 30, v => app.Edit(p => p.BreakGoal = v))), UI.Row(Enumerable.Range(0, 3).Select(i => (Control)UI.Stack(UI.Text($"快捷杯量 {i + 1}（ml）", 11), UI.Number(S.Prefs.WaterPresets[i], 50, 1000, v => app.Edit(p => p.WaterPresets[i] = v)))).ToArray()))));
        body.Children.Add(UI.Card(UI.Stack(UI.Text("本机数据", 16, bold: true), UI.Text("所有设置和记录保存在本机，无账号、广告或遥测。重装保留数据目录即可继续使用。", 12, Colors.Muted), UI.Row(UI.Button("导出每日统计 CSV", async () => await ExportCsv()), UI.Button("备份全部记录", async () => await Backup()), UI.Button("打开数据目录", () => { if (!app.Preview) { Directory.CreateDirectory(app.DataDirectory); System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(app.DataDirectory) { UseShellExecute = true }); } })), UI.Line(), UI.Text("缓芽 · huǎn yá 2.0 · Windows 预览版", 13, bold: true), UI.Text("一般健康习惯提醒工具，不是医疗设备。使用时长为估算，不监测实际坐姿。", 11, Colors.Muted), UI.Button("退出缓芽", app.Quit))));
        return body;
    }
    async Task ChooseApp()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new()
        {
            Title = "选择需要暂停提醒的应用",
            AllowMultiple = false,
            FileTypeFilter = [new("Windows 应用") { Patterns = ["*.exe"] }]
        });
        if (files.Count == 0)
            return;
        var path = files[0].TryGetLocalPath();
        if (path == null)
            return;
        if (string.Equals(path, Environment.ProcessPath, StringComparison.OrdinalIgnoreCase))
        {
            app.Notice = "缓芽自身无需加入暂停列表。";
            ShowNotice();
            return;
        }
        app.Edit(p => p.BusyApplications.Add(new() { Path = path, Name = Path.GetFileNameWithoutExtension(path) }));
        RenderPage();
    }
    async Task ExportCsv()
    {
        var file = await StorageProvider.SaveFilePickerAsync(new()
        {
            Title = "导出每日统计",
            SuggestedFileName = "huanya-statistics.csv",
            DefaultExtension = "csv"
        });
        if (file == null)
            return;
        try
        {
            await using var stream = await file.OpenWriteAsync();
            using var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(true));
            await writer.WriteLineAsync("日期,饮水毫升,饮水次数,护眼次数,拉伸次数,工作秒数,休息秒数");
            foreach (var (date, d) in S.Engine.Saved.Days.OrderBy(p => p.Key))
                await writer.WriteLineAsync(FormattableString.Invariant($"{date},{d.WaterML},{d.WaterCount},{d.EyeBreaks},{d.Stretches},{d.WorkSeconds:F0},{d.BreakSeconds}"));
        }
        catch (Exception e) { await UI.Message(this, "导出失败", e.Message); }
    }
    async Task Backup()
    {
        var file = await StorageProvider.SaveFilePickerAsync(new()
        {
            Title = "备份全部记录",
            SuggestedFileName = $"huanya-backup-{DateTime.Now:yyyyMMdd}.json",
            DefaultExtension = "json"
        });
        if (file == null)
            return;
        try
        {
            await using var stream = await file.OpenWriteAsync();
            await System.Text.Json.JsonSerializer.SerializeAsync(stream, S.Engine.Saved, DataJson.Options);
        }
        catch (Exception e) { await UI.Message(this, "备份失败", e.Message); }
    }
}
