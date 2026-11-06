using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Huanya.Core;

namespace Huanya.Desktop;

public sealed class ReminderWindow : Window
{
    readonly Controller app;
    string signature = "";
    readonly StackPanel body = UI.Stack();
    readonly List<Action> live = [];
    public ReminderWindow(Controller app)
    {
        this.app = app;
        Title = "缓芽 · 休息提醒";
        Width = 430;
        Height = 650;
        MinHeight = 380;
        CanResize = false;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        SystemDecorations = SystemDecorations.None;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        Content = new Border { Background = Colors.Background, CornerRadius = new CornerRadius(23), BorderBrush = Colors.Line, BorderThickness = new Thickness(1), ClipToBounds = true, Child = new ScrollViewer { Content = new Border { Padding = new Thickness(25), Child = body } } };
        Closing += (_, e) => { if (app.IsExiting) return; e.Cancel = true; app.Act(() => app.Session.Snooze()); Hide(); };
        if (Screens.Primary is { } screen)
            Height = Math.Min(650, screen.WorkingArea.Height / screen.Scaling - 70);
        Update();
    }
    public void Update()
    {
        var s = app.Session;
        var key = string.Join(',', s.Pending) + "|" + s.Active?.Kind + "|" + s.Planned?.Id + "|" + s.Card + "|" + s.Prefs.StretchCardsEnabled;
        if (key != signature)
        {
            signature = key;
            Build();
        }
        foreach (var action in live)
            action();
    }
    void Build()
    {
        var s = app.Session;
        body.Children.Clear();
        live.Clear();
        body.Spacing = 18;
        var brand = UI.Text("缓芽  /  huǎn yá", 10, Colors.Muted);
        brand.PointerPressed += (_, e) => { if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) BeginMoveDrag(e); };
        body.Children.Add(UI.Apart(brand, UI.Button("×", () => app.Act(() => s.Snooze()), "link")));
        bool multiple = s.Pending.Count > 1;
        if (multiple)
        {
            body.Children.Add(UI.Text("一起，休息一下。", 27));
            body.Children.Add(UI.Text("提醒时间接近，放在一起了。每一项分别记录。", 11, Colors.Muted));
        }
        foreach (var k in s.Pending.ToArray())
        {
            var column = UI.Stack();
            column.Spacing = 17;
            if (!multiple)
            {
                var icon = UI.Card(UI.Icon(k.ToString().ToLowerInvariant(), Colors.Accent(k), 40), Colors.Wash(k), 20, 45);
                icon.HorizontalAlignment = HorizontalAlignment.Center;
                column.Children.Add(icon);
            }
            var title = UI.Serif(s.Title(k), multiple ? 16 : 27, multiple ? Colors.Green : Colors.Ink);
            if (!multiple)
                title.HorizontalAlignment = HorizontalAlignment.Center;
            column.Children.Add(title);
            if (!multiple)
            {
                var message = UI.Text(k.Message(), 12, Colors.Muted);
                message.TextAlignment = TextAlignment.Center;
                column.Children.Add(message);
            }
            if (k == Kind.Stretch && s.Prefs.StretchCardsEnabled)
                column.Children.Add(Guide());
            if (k == Kind.Water)
            {
                column.Children.Add(UI.Columns(s.Prefs.WaterPresets.Select(amount => (Control)UI.Button($"+ {amount} ml", () => app.Act(() => s.Water(amount)))).ToArray()));
                column.Children.Add(UI.Button($"喝好了，记 {s.Prefs.WaterML} ml", () => app.Act(() => s.Water()), "primary"));
            }
            else if (s.Active?.Kind == k)
            {
                var clock = UI.Text(Labels.Clock(s.Remaining), multiple ? 30 : 45, Colors.Green);
                clock.HorizontalAlignment = HorizontalAlignment.Center;
                var complete = UI.Button("完成休息 ✓", () => app.Act(s.Finish), "primary");
                complete.HorizontalAlignment = HorizontalAlignment.Center;
                live.Add(() => { clock.Text = Labels.Clock(s.Remaining); complete.IsEnabled = s.Remaining == 0; complete.Opacity = s.Remaining > 0 ? .4 : 1; });
                column.Children.Add(clock);
                column.Children.Add(complete);
            }
            else
            {
                var hint = UI.Text($"给自己 {Labels.Duration(s.Duration(k))}，慢慢来", 11, Colors.Accent(k));
                hint.HorizontalAlignment = HorizontalAlignment.Center;
                column.Children.Add(hint);
                var start = UI.Button("开始休息", () => app.Act(() => s.Start(k)), "primary");
                start.HorizontalAlignment = HorizontalAlignment.Center;
                start.IsEnabled = s.Active == null;
                column.Children.Add(start);
            }
            if (multiple)
                column.Children.Add(UI.Row(UI.Button("稍后 5 分钟", () => app.Act(() => s.Snooze(k)), "link"), UI.Button("跳过", () => app.Act(() => s.Skip(k)), "link")));
            body.Children.Add(multiple ? UI.Card(column, padding: 14) : column);
        }
        var later = UI.Button(s.Active == null ? "全部 5 分钟后提醒" : "结束本次 · 不计入统计", () => app.Act(() => s.Snooze()), "link");
        later.HorizontalAlignment = HorizontalAlignment.Center;
        body.Children.Add(later);
        var skip = UI.Button(s.Planned == null ? "本次跳过 · 下个间隔再提醒" : "本次跳过 · 按原计划再提醒", () => app.Act(() => s.Skip()), "link");
        skip.FontSize = 11;
        skip.HorizontalAlignment = HorizontalAlignment.Center;
        body.Children.Add(skip);
    }
    Control Guide()
    {
        var s = app.Session;
        var titles = new[] { "肩膀放松", "手腕舒展", "站立走动" };
        var messages = new[] { "站直，肩膀轻轻上提，再慢慢放下。自然呼吸，动作保持舒适。", "松开鼠标，放松双手。轻轻张开手指，再缓缓收拢，转动手腕。", "离开座位，在身边慢慢走几步。抬头看看远处，留意周围空间。" };
        var grid = new Grid { ColumnDefinitions = new("80,*"), ColumnSpacing = 15 };
        grid.Children.Add(new Artwork { Drawing = "stretch", Card = s.Card, Width = 80, Height = 110 });
        var text = UI.Stack(UI.Apart(UI.Text(titles[s.Card], 15, Colors.Green, true), UI.Button("→", () => app.Act(s.CycleCard, false), "link")), UI.Text(messages[s.Card], 11, Colors.Muted), UI.Text($"{s.Card + 1} / 3 · 每 20 秒自动切换", 10, Colors.Accent(Kind.Stretch)));
        text.Spacing = 8;
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        return UI.Card(grid, Colors.Wash(Kind.Stretch), 16, 14);
    }
}
public sealed class PrewarningWindow : Window
{
    readonly Controller app; readonly TextBlock title = UI.Text("", 13, bold: true), detail = UI.Text("", 11, Colors.Muted);
    public PrewarningWindow(Controller app)
    {
        this.app = app;
        Title = "缓芽 · 提前提醒";
        Width = 380;
        Height = 124;
        CanResize = false;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;
        SystemDecorations = SystemDecorations.None;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        Content = new Border { Background = Colors.Background, CornerRadius = new CornerRadius(17), BorderBrush = Colors.Line, BorderThickness = new Thickness(1), Padding = new Thickness(18), Child = UI.Stack(UI.Apart(title, UI.Button("×", () => app.Act(app.Session.DismissPrewarning), "link")), UI.Apart(detail, UI.Button("现在休息 ↗", () => app.Act(app.Session.TakePrewarning), "link"))) };
        Opened += (_, _) => { if (Screens.Primary is { } screen) { Position = new PixelPoint(screen.WorkingArea.Right - (int)(Width * screen.Scaling) - 20, screen.WorkingArea.Bottom - (int)(Height * screen.Scaling) - 20); } };
        Closing += (_, e) => { if (app.IsExiting) return; e.Cancel = true; app.Act(app.Session.DismissPrewarning); Hide(); };
    }
    public void Update()
    {
        var batch = app.Session.Prewarning;
        title.Text = $"还有 {(int)Math.Ceiling(((batch?.DueAt ?? app.Session.Now) - app.Session.Now).TotalSeconds)} 秒，休息一下";
        detail.Text = batch?.Title ?? "";
    }
}
