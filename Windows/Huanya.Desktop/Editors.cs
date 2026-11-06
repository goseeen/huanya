using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Huanya.Core;

namespace Huanya.Desktop;

public sealed partial class MainWindow
{
    async void OpenRoutine()
    {
        var days = DataJson.Clone(S.Prefs.WeeklyRoutine);
        var w = new Window { Title = "每周作息", Width = 760, Height = 640, MinWidth = 680, MinHeight = 450, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var rows = UI.Stack();
        var error = UI.Text("", 12, Brushes.Firebrick);
        void Render()
        {
            rows.Children.Clear();
            foreach (var day in days)
            {
                var windows = UI.Stack();
                windows.Spacing = 8;
                foreach (var item in day.Windows)
                {
                    var start = new TextBox { Text = $"{item.Start / 60:00}:{item.Start % 60:00}", Width = 90 };
                    var end = new TextBox { Text = $"{item.End / 60:00}:{item.End % 60:00}", Width = 90 };
                    start.TextChanged += (_, _) => item.Start = ParseTime(start.Text, false);
                    end.TextChanged += (_, _) => item.End = ParseTime(end.Text, true);
                    windows.Children.Add(UI.Row(start, UI.Text("至"), end, UI.Button("移除", () => { day.Windows.Remove(item); Render(); })));
                }
                windows.Children.Add(UI.Button("+ 时段", () => { if (day.Windows.Count < 4) { day.Windows.Add(new() { Start = 1080, End = 1200 }); Render(); } }));
                var label = UI.Stack(UI.Text(day.Title, 14, bold: true), UI.Toggle(day.Enabled, v => day.Enabled = v));
                label.Width = 80;
                var row = UI.Row(label, windows);
                if (day.Weekday == 2)
                    row.Children.Add(UI.Button("复制到工作日", () => { foreach (var d in days.Where(d => d.Weekday is >= 3 and <= 6)) { d.Windows = DataJson.Clone(day.Windows); d.Enabled = day.Enabled; } Render(); }));
                rows.Children.Add(UI.Card(row, padding: 15));
            }
        }
        var controls = UI.Row(UI.Button("工作日午休一小时", () => { days = Routine.Standard(); Render(); }), UI.Button("弹性下午", () => { days = Routine.Standard(); foreach (var d in days) d.Windows = [new() { Start = 780, End = 1080 }]; Render(); }));
        var root = new Grid { RowDefinitions = new("Auto,*,Auto"), Margin = new Thickness(24) };
        root.Children.Add(UI.Stack(UI.Text("每周作息", 22, bold: true), UI.Text("使用 HH:mm；结束时间可填写 24:00，跨午夜请分到相邻两天。", 11, Colors.Muted), controls));
        var scroll = new ScrollViewer { Content = rows, Margin = new Thickness(0, 16) };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
        var footer = UI.Apart(error, UI.Row(UI.Button("取消", w.Close), UI.Button("保存", () => { var message = Routine.Error(days); if (message != null) { error.Text = message; return; } app.Edit(p => p.WeeklyRoutine = days); w.Close(); RenderPage(); }, "primary")));
        Grid.SetRow(footer, 2);
        root.Children.Add(footer);
        w.Content = root;
        Render();
        await w.ShowDialog(this);
    }
    static int ParseTime(string? text, bool allow24)
    {
        var parts = (text ?? "").Split(':');
        if (parts.Length != 2 || !int.TryParse(parts[0], out var h) || !int.TryParse(parts[1], out var m) || m is < 0 or > 59 || h < 0 || h > 23 && !(allow24 && h == 24 && m == 0))
            return -1;
        return h * 60 + m;
    }
    async void OpenPlanned(PlannedBreak? original)
    {
        if (original == null && S.Prefs.PlannedBreaks.Count >= 20)
        {
            await UI.Message(this, "固定提醒", "最多可以设置 20 项固定提醒。");
            return;
        }
        var p = original == null ? new PlannedBreak() : DataJson.Clone(original);
        var w = new Window { Title = original == null ? "添加固定提醒" : "编辑固定提醒", Width = 540, SizeToContent = SizeToContent.Height, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var name = new TextBox { Text = p.Name, MaxLength = 30 };
        var time = new TextBox { Text = $"{p.Minute / 60:00}:{p.Minute % 60:00}", Width = 100 };
        var duration = UI.Number(p.DurationSeconds, 10, 1800);
        var type = new ComboBox { ItemsSource = new[] { "护眼休息", "起身拉伸" }, SelectedIndex = p.Kind == Kind.Eyes ? 0 : 1, Width = 140 };
        var weekdays = UI.Row();
        weekdays.Spacing = 9;
        foreach (var d in new[] { 2, 3, 4, 5, 6, 7, 1 })
        {
            var cb = new CheckBox { Content = new[] { "日", "一", "二", "三", "四", "五", "六" }[d - 1], IsChecked = p.Weekdays.Contains(d) };
            cb.IsCheckedChanged += (_, _) => { p.Weekdays.Remove(d); if (cb.IsChecked == true) p.Weekdays.Add(d); };
            weekdays.Children.Add(cb);
        }
        var error = UI.Text("", 12, Brushes.Firebrick);
        var actions = UI.Row(UI.Button("取消", w.Close), UI.Button("保存", () => { p.Name = name.Text?.Trim() ?? ""; p.Minute = ParseTime(time.Text, false); p.DurationSeconds = (int)(duration.Value ?? 0); p.Kind = type.SelectedIndex == 0 ? Kind.Eyes : Kind.Stretch; if (p.Error is { } message) { error.Text = message; return; } app.Edit(x => { x.PlannedBreaks.RemoveAll(i => i.Id == p.Id); x.PlannedBreaks.Add(p); }); w.Close(); RenderPage(); }, "primary"));
        if (original != null)
            actions.Children.Insert(0, UI.Button("删除", () => { app.Edit(x => x.PlannedBreaks.RemoveAll(i => i.Id == p.Id)); w.Close(); RenderPage(); }));
        w.Content = new Border { Padding = new Thickness(26), Child = UI.Stack(UI.Text("固定提醒", 22, bold: true), UI.Text("名称", 12), name, UI.Row(UI.Text("时间"), time, type), UI.Row(UI.Text("休息秒数"), duration), UI.Text("重复日期", 12), weekdays, UI.Text("独立于工作时段，仍遵守暂停、忙碌、空闲及锁屏规则。", 11, Colors.Muted), error, actions) };
        await w.ShowDialog(this);
    }
    Control Statistics()
    {
        var review = new PeriodReview(reviewMonth, reviewOffset, S.Now, S.Engine.Saved.Days);
        var total = PeriodReview.Sum(review.Records.Select(r => r.Record));
        var top = UI.Apart(UI.Text("周月回顾", 18, bold: true), UI.Row(UI.Button("周", () => { reviewMonth = false; reviewOffset = 0; RenderPage(); }), UI.Button("月", () => { reviewMonth = true; reviewOffset = 0; RenderPage(); }), UI.Button("← 上一期", () => { reviewOffset--; RenderPage(); }), UI.Button("下一期 →", () => { reviewOffset = Math.Min(0, reviewOffset + 1); RenderPage(); }), UI.Button("回到本期", () => { reviewOffset = 0; RenderPage(); })));
        var body = UI.Stack(top, UI.Text($"{review.Start:yyyy/MM/dd} — {review.End.AddDays(-1):yyyy/MM/dd}", 12, Colors.Muted), UI.Columns(Metric("饮水", $"{total.WaterML}", "ml", Kind.Water), Metric("休息", $"{total.BreakCount}", "次", Kind.Eyes), Metric("工作估算", $"{(int)(total.WorkSeconds / 60)}", "分钟", Kind.Stretch)));
        var daily = new Grid { ColumnDefinitions = new(string.Join(',', review.Records.Select(_ => "*"))), ColumnSpacing = 4, Height = 150 };
        double maximum = Math.Max(1, review.Records.Max(r => r.Record?.WorkSeconds ?? 0));
        int index = 0;
        foreach (var (date, record) in review.Records)
        {
            var bar = new Border { Height = record == null ? 3 : Math.Max(4, record.WorkSeconds / maximum * 110), Background = record == null ? Colors.Line : Colors.Green, CornerRadius = new(3), VerticalAlignment = VerticalAlignment.Bottom };
            var column = new Grid { RowDefinitions = new("*,Auto") };
            column.Children.Add(bar);
            var label = UI.Text(date.Day.ToString(), 9, Colors.Muted);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.Margin = new Thickness(0, 7, 0, 0);
            Grid.SetRow(label, 1);
            column.Children.Add(label);
            ToolTip.SetTip(column, record == null ? $"{date:MM/dd} · 无记录" : $"{date:MM/dd} · 饮水 {record.WaterML} ml · 休息 {record.BreakCount} 次 · 工作 {(int)(record.WorkSeconds / 60)} 分钟");
            Grid.SetColumn(column, index++);
            daily.Children.Add(column);
        }
        var nowTotal = PeriodReview.Sum(review.Pairs.Select(p => p.Current));
        var oldTotal = PeriodReview.Sum(review.Pairs.Select(p => p.Previous));
        string comparison = review.Pairs.Count == 0 ? "暂无可比较的同期记录。" : $"与上一期相同日序比较（{review.Pairs.Count} 个有记录的完整日期）：饮水 {nowTotal.WaterML - oldTotal.WaterML:+0;-0;0} ml，休息 {nowTotal.BreakCount - oldTotal.BreakCount:+0;-0;0} 次。";
        body.Children.Add(UI.Card(UI.Stack(UI.Text("每日工作时长（估算）", 14, bold: true), daily, UI.Text("无记录与已记录为零分别显示；今天不参与同期比较。", 11, Colors.Muted), UI.Text(comparison, 12))));
        var hours = new Grid { ColumnDefinitions = new(string.Join(',', Enumerable.Repeat("*", 24))), ColumnSpacing = 5, Height = 115 };
        for (int h = 0; h < 24; h++)
        {
            int hour = h;
            double seconds = Today.HourlyWorkSeconds[h];
            var bar = new Border { Height = Math.Max(3, seconds / 3600 * 100), Background = h == S.Now.LocalDateTime.Hour ? Colors.Green : Brush.Parse("#B6C3BC"), CornerRadius = new(3), VerticalAlignment = VerticalAlignment.Bottom };
            var region = new Grid { Background = Brushes.Transparent, Children = { bar } };
            ToolTip.SetTip(region, $"{h:00}:00–{h + 1:00}:00\n" + (h > S.Now.LocalDateTime.Hour && seconds == 0 ? "尚未到该时段" : seconds is > 0 and < 60 ? "累计工作不足 1 分钟" : $"累计工作 {(int)(seconds / 60)} 分钟"));
            var normal = bar.Background;
            region.PointerEntered += (_, _) => bar.Background = Colors.Green;
            region.PointerExited += (_, _) => bar.Background = normal;
            Grid.SetColumn(region, h);
            hours.Children.Add(region);
        }
        var periods = UI.Stack();
        foreach (var p in S.Engine.Saved.WorkPeriods.Where(p => Labels.Day(p.Start) == Labels.Day(S.Now) && p.Seconds >= 1200).OrderByDescending(p => p.Seconds).Take(5))
            periods.Children.Add(UI.Apart(UI.Text($"{p.Start.LocalDateTime:HH:mm} — {p.End.LocalDateTime:HH:mm}"), UI.Text($"{(int)(p.Seconds / 60)} 分钟", 13, Colors.Green)));
        if (periods.Children.Count == 0)
            periods.Children.Add(UI.Text("暂无连续 20 分钟以上的工作时段。", 12, Colors.Muted));
        body.Children.Add(UI.Card(UI.Stack(UI.Apart(UI.Text("今天的节奏", 16, bold: true), UI.Text($"到期 {Today.RemindersDue} · 延后 {Today.RemindersSnoozed} · 跳过 {Today.RemindersSkipped}", 11, Colors.Muted)), UI.Line(), UI.Apart(UI.Text("各时段工作量", 14, bold: true), UI.Text("每格 1 小时 · 悬停查看", 11, Colors.Muted)), hours, UI.Apart(UI.Text("00:00      06:00", 10, Colors.Muted), UI.Text("12:00       18:00       24:00", 10, Colors.Muted)), UI.Text("连续工作较久的时段 · 20 分钟起", 14, bold: true), periods)));
        var source = S.Engine.Saved.Events.Count(e => e.Origin == "confirmed" && e.VoidedAt == null);
        var away = S.Engine.Saved.TimingEvents.Where(t => t.Reason == "naturalAway").Sum(t => t.Seconds ?? 0);
        body.Children.Add(UI.Card(UI.Stack(UI.Text("记录与来源", 16, bold: true), UI.Text($"最近保留的明细中，手动确认 {source} 条；自然离开估算 {(int)(away / 60)} 分钟。自然离开不计为完成休息。", 12, Colors.Muted), UI.Row(UI.Button("管理活动记录", () => OpenRecords()), UI.Button("查看计时原因", () => OpenTiming()), UI.Button("导出每日统计", async () => await ExportCsv())))));
        return body;
    }
    static Control Metric(string title, string value, string unit, Kind kind) => UI.Card(UI.Stack(UI.Text(title, 12, Colors.Muted), UI.Row(UI.Text(value, 28, Colors.Accent(kind)), UI.Text(unit, 12, Colors.Muted))));
    async void OpenRecords()
    {
        var w = new Window { Title = "活动记录", Width = 730, Height = 600, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        int page = 0;
        var rows = UI.Stack();
        void Render()
        {
            rows.Children.Clear();
            foreach (var e in S.Engine.Saved.Events.Skip(page * 20).Take(20))
            {
                var item = e;
                var row = UI.Apart(UI.Stack(UI.Text($"{e.Date.LocalDateTime:yyyy/MM/dd HH:mm} · {e.Label ?? e.Kind.Title()}"), UI.Text($"{e.Amount} {(e.Kind == Kind.Water ? "ml" : "秒")} · {(e.VoidedAt != null ? "已撤销" : e.Origin == "confirmed" ? "手动确认" : "历史来源未记录")} · 更正 {e.Revisions.Count} 次", 11, Colors.Muted)), UI.Button("更正", async () => await CorrectRecord(w, item)));
                rows.Children.Add(UI.Card(row, padding: 14));
            }
            if (rows.Children.Count == 0)
                rows.Children.Add(UI.Text("暂无记录。", 13, Colors.Muted));
        }
        var panel = new Grid { RowDefinitions = new("Auto,*,Auto"), Margin = new Thickness(24) };
        panel.Children.Add(UI.Text("活动记录 · 最近 1000 条", 20, bold: true));
        var sc = new ScrollViewer { Content = rows, Margin = new Thickness(0, 16) };
        Grid.SetRow(sc, 1);
        panel.Children.Add(sc);
        var footer = UI.Apart(UI.Row(UI.Button("上一页", () => { page = Math.Max(0, page - 1); Render(); }), UI.Button("下一页", () => { if ((page + 1) * 20 < S.Engine.Saved.Events.Count) page++; Render(); })), UI.Button("完成", w.Close));
        Grid.SetRow(footer, 2);
        panel.Children.Add(footer);
        w.Content = panel;
        w.Activated += (_, _) => Render();
        Render();
        await w.ShowDialog(this);
        RenderPage();
    }
    async Task CorrectRecord(Window owner, ActivityEvent e)
    {
        var w = new Window { Title = "更正记录", Width = 430, SizeToContent = SizeToContent.Height, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var number = UI.Number(e.Amount, e.Kind == Kind.Water ? 50 : 10, e.Kind == Kind.Water ? 1000 : 1800);
        var error = UI.Text("", 12, Brushes.Firebrick);
        void Save(int? value)
        {
            if (!S.Engine.Correct(e.Id, value, S.Now))
            {
                error.Text = "数值或原始统计不一致，未修改。";
                return;
            }
            app.Save();
            w.Close();
        }
        var actions = UI.Row(UI.Button("取消", w.Close), UI.Button(e.VoidedAt == null ? "保存" : "恢复记录", () => Save((int)(number.Value ?? 0)), "primary"));
        if (e.VoidedAt == null)
            actions.Children.Insert(0, UI.Button("撤销记录", () => Save(null)));
        w.Content = new Border { Padding = new Thickness(24), Child = UI.Stack(UI.Text(e.Kind.Title(), 20, bold: true), UI.Text("更正只调整这条记录的贡献，不影响当前计时。", 11, Colors.Muted), UI.Row(number, UI.Text(e.Kind == Kind.Water ? "ml" : "秒")), error, actions) };
        await w.ShowDialog(owner);
    }
    async void OpenTiming()
    {
        var w = new Window { Title = "计时记录", Width = 700, Height = 580, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var rows = UI.Stack();
        int page = 0;
        void Render()
        {
            rows.Children.Clear();
            foreach (var e in S.Engine.Saved.TimingEvents.Skip(page * 30).Take(30))
                rows.Children.Add(UI.Apart(UI.Text($"{e.Date.LocalDateTime:MM/dd HH:mm:ss}", 11, Colors.Muted), UI.Text(Labels.Reason(e.Reason) + (e.Seconds == null ? "" : $" · {(int)(e.Seconds / 60)} 分钟"), 12)));
            if (rows.Children.Count == 0)
                rows.Children.Add(UI.Text("暂无计时变化。"));
        }
        var panel = new Grid { RowDefinitions = new("Auto,*,Auto"), Margin = new Thickness(24) };
        panel.Children.Add(UI.Stack(UI.Text("计时为什么变化了", 20, bold: true), UI.Text("仅记录时间与通用原因，不保存应用名称或窗口标题。", 11, Colors.Muted)));
        var scroll = new ScrollViewer { Content = rows, Margin = new Thickness(0, 20) };
        Grid.SetRow(scroll, 1);
        panel.Children.Add(scroll);
        var footer = UI.Apart(UI.Row(UI.Button("上一页", () => { page = Math.Max(0, page - 1); Render(); }), UI.Button("下一页", () => { if ((page + 1) * 30 < S.Engine.Saved.TimingEvents.Count) page++; Render(); })), UI.Button("完成", w.Close));
        Grid.SetRow(footer, 2);
        panel.Children.Add(footer);
        w.Content = panel;
        Render();
        await w.ShowDialog(this);
    }
}
