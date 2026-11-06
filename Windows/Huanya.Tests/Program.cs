using Huanya.Core;
using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Huanya.Desktop;

static class Tests
{
    static int passed;
    static readonly DateTimeOffset T = new(new DateTime(2026, 11, 2, 9, 0, 0), TimeZoneInfo.Local.GetUtcOffset(new DateTime(2026, 11, 2)));
    static void Equal<TValue>(TValue expected, TValue actual, string label = "")
    {
        if (!Equals(expected, actual))
            throw new Exception($"{label}: expected {expected}, got {actual}");
    }
    static void Near(double expected, double actual, string label = "")
    {
        if (Math.Abs(expected - actual) > .01)
            throw new Exception($"{label}: expected {expected}, got {actual}");
    }
    static void True(bool value, string label = "")
    {
        if (!value)
            throw new Exception(label);
    }
    static void Test(string name, Action action)
    {
        action();
        passed++;
        Console.WriteLine("PASS " + name);
    }
    static ReminderEngine Engine()
    {
        var state = new SavedState();
        state.Preferences.MergeReminders = false;
        return new(state, T);
    }
    static void Tick(ReminderEngine e, int start, int end)
    {
        for (int i = start; i <= end; i++)
            e.Advance(T.AddSeconds(i));
    }
    static int Main(string[] args)
    {
        try
        {
            Test("foreground switch preserves remaining seconds", () => { var e = Engine(); Tick(e, 1, 100); var left = (e.Deadlines[Kind.Eyes] - T.AddSeconds(100)).TotalSeconds; e.SetForegroundBlocked(true, T.AddSeconds(100)); Tick(e, 101, 200); e.SetForegroundBlocked(false, T.AddSeconds(200)); Near(left, (e.Deadlines[Kind.Eyes] - T.AddSeconds(200)).TotalSeconds); e.Advance(T.AddSeconds(201)); Near(left - 1, (e.Deadlines[Kind.Eyes] - T.AddSeconds(201)).TotalSeconds); });
            Test("foreground with overlapping idle does not reset", () => { var e = Engine(); Tick(e, 1, 100); e.SetForegroundBlocked(true, T.AddSeconds(100)); for (int i = 101; i <= 500; i++) { e.UpdateIdle(i - 100, false, T.AddSeconds(i)); e.Advance(T.AddSeconds(i)); } e.SetForegroundBlocked(false, T.AddSeconds(500)); e.UpdateIdle(0, false, T.AddSeconds(500)); Near(1100, (e.Deadlines[Kind.Eyes] - T.AddSeconds(500)).TotalSeconds); });
            Test("idle remains after foreground exit then preserves on input", () => { var e = Engine(); Tick(e, 1, 100); e.SetForegroundBlocked(true, T.AddSeconds(100)); for (int i = 101; i <= 400; i++) { e.UpdateIdle(i, false, T.AddSeconds(i)); e.Advance(T.AddSeconds(i)); } e.SetForegroundBlocked(false, T.AddSeconds(400)); Tick(e, 401, 410); e.UpdateIdle(0, false, T.AddSeconds(410)); Near(1100, (e.Deadlines[Kind.Eyes] - T.AddSeconds(410)).TotalSeconds); });
            Test("lock supersedes foreground preservation", () => { var e = Engine(); Tick(e, 1, 100); e.SetForegroundBlocked(true, T.AddSeconds(100)); Tick(e, 101, 120); e.UpdateIdle(0, true, T.AddSeconds(120)); Tick(e, 121, 130); e.SetForegroundBlocked(false, T.AddSeconds(130)); e.UpdateIdle(0, false, T.AddSeconds(130)); Near(1200, (e.Deadlines[Kind.Eyes] - T.AddSeconds(130)).TotalSeconds); });
            Test("ordinary idle resumes with fresh interval", () => { var e = Engine(); Tick(e, 1, 100); e.UpdateIdle(200, false, T.AddSeconds(100)); Tick(e, 101, 110); e.UpdateIdle(0, false, T.AddSeconds(110)); Near(1200, (e.Deadlines[Kind.Eyes] - T.AddSeconds(110)).TotalSeconds); });
            Test("sleep gap excluded from work", () => { var e = Engine(); Tick(e, 1, 10); e.Advance(T.AddHours(1)); Near(10, e.Saved.Days[Labels.Day(T)].WorkSeconds); Near(0, e.SittingSeconds); Near(1200, (e.Deadlines[Kind.Eyes] - T.AddHours(1)).TotalSeconds); });
            Test("negative clock gap resets safely", () => { var e = Engine(); e.Advance(T.AddSeconds(-10)); Near(1200, (e.Deadlines[Kind.Eyes] - T.AddSeconds(-10)).TotalSeconds); Equal(0, e.Saved.Days.Count); });
            Test("pause expiry starts fresh interval", () => { var e = Engine(); Tick(e, 1, 10); e.SetPaused(true, T.AddSeconds(10), T.AddSeconds(20)); Tick(e, 11, 20); True(!e.Paused); Near(1200, (e.Deadlines[Kind.Eyes] - T.AddSeconds(20)).TotalSeconds); });
            Test("snooze protected against merging", () => { var e = Engine(); e.Prefs.MergeReminders = true; e.Prefs.MergeWindowSeconds = 300; e.Snooze(Kind.Eyes, T); var first = e.Batches(T).First(); Equal(Kind.Eyes, first.Kinds[0]); Equal(T.AddMinutes(5), first.DueAt); e.SetForegroundBlocked(true, T); Tick(e, 1, 100); e.SetForegroundBlocked(false, T.AddSeconds(100)); Equal(T.AddSeconds(400), e.Deadlines[Kind.Eyes]); });
            Test("manual completion required", () => { var s = new Session(new(), T); s.Offer([Kind.Eyes]); s.Start(Kind.Eyes); s.Finish(); Equal(0, s.Engine.Saved.Events.Count); for (int i = 1; i <= 25; i++) s.Tick(T.AddSeconds(i)); Equal(0, s.Engine.Saved.Events.Count); s.Finish(); Equal(1, s.Engine.Saved.Events.Count); Equal(20, s.Engine.Saved.Events[0].Amount); s.Finish(); Equal(1, s.Engine.Saved.Events.Count); });
            Test("prewarning click starts rest once", () => { var state = new SavedState(); state.Preferences.Eyes.IntervalMinutes = 1; var s = new Session(state, T); for (int i = 1; i <= 35; i++) s.Tick(T.AddSeconds(i)); True(s.Prewarning != null); s.TakePrewarning(); True(s.Active != null); Equal(Kind.Eyes, s.Active!.Kind); var end = s.Active.EndsAt; s.TakePrewarning(); Equal(end, s.Active.EndsAt); });
            Test("water prewarning does not fabricate intake", () => { var state = new SavedState(); state.Preferences.Water.IntervalMinutes = 1; var s = new Session(state, T); for (int i = 1; i <= 35; i++) s.Tick(T.AddSeconds(i)); s.TakePrewarning(); True(s.Active == null); Equal(0, s.Engine.Saved.Events.Count); True(s.Pending.Contains(Kind.Water)); });
            Test("combined reminders complete individually", () => { var s = new Session(new(), T); s.Offer([Kind.Water, Kind.Eyes, Kind.Stretch]); s.Water(150); s.Start(Kind.Eyes); s.Start(Kind.Stretch); Equal(Kind.Eyes, s.Active!.Kind); for (int i = 1; i <= 20; i++) s.Tick(T.AddSeconds(i)); s.Finish(); Equal(1, s.Pending.Count); Equal(Kind.Stretch, s.Pending[0]); Equal(2, s.Engine.Saved.Events.Count); });
            Test("skip does not complete", () => { var s = new Session(new(), T); s.Offer([Kind.Stretch]); s.Start(Kind.Stretch); s.Skip(); Equal(0, s.Engine.Saved.Events.Count); True(!s.Engine.OnBreak); Equal(1, s.Engine.Day(T).RemindersSkipped); });
            Test("long break advances only confirmed normal stretches", () => { var e = Engine(); e.Prefs.LongBreak.Enabled = true; e.Prefs.LongBreak.Every = 2; e.Complete(Kind.Eyes, T); True(!e.IsLongBreak(Kind.Stretch)); e.Complete(Kind.Stretch, T, 60, advancesCycle: false); True(!e.IsLongBreak(Kind.Stretch)); e.Complete(Kind.Stretch, T, 60); True(e.IsLongBreak(Kind.Stretch)); Equal(600, e.RestDuration(Kind.Stretch)); e.Complete(Kind.Stretch, T, 600); True(!e.IsLongBreak(Kind.Stretch)); });
            Test("routine validation rejects overlap", () => { var days = Routine.Standard(); days[0].Windows = [new() { Start = 540, End = 780 }, new() { Start = 720, End = 900 }]; True(Routine.Error(days) != null); days[0].Windows[1].Start = 780; Equal<string?>(null, Routine.Error(days)); });
            Test("routine boundaries and legacy overnight", () => { var p = new Preferences { WeeklyRoutineEnabled = true }; True(p.Allows(T)); True(!p.Allows(T.AddHours(3))); True(p.Allows(T.AddHours(4))); p.WeeklyRoutineEnabled = false; p.WorkHoursOnly = true; p.StartHour = 22; p.EndHour = 6; True(p.Allows(T.AddHours(14))); True(!p.Allows(T)); });
            Test("fixed reminder outside work hours", () => { var e = Engine(); e.Prefs.WorkHoursOnly = true; e.Prefs.StartHour = 13; e.Prefs.PlannedBreaks.Add(new() { Minute = 9 * 60 }); var o = e.PlannedOccurrences(T).First(); Equal(T, o.DueAt); True(e.Batches(T).First().Planned != null); e.Claim(o, T); True(e.PlannedOccurrences(T).All(x => x.Id != o.Id)); });
            Test("stale planned reminders not replayed", () => { var e = Engine(); e.Prefs.PlannedBreaks.Add(new() { Minute = 9 * 60 }); True(e.PlannedOccurrences(T.AddMinutes(2)).All(x => x.DueAt > T)); });
            Test("planned snooze persists and invalidates on rule edit", () => { var e = Engine(); var rule = new PlannedBreak { Minute = 9 * 60 }; e.Prefs.PlannedBreaks.Add(rule); var o = e.PlannedOccurrences(T).First(); e.SnoozePlanned(o, T); var reloaded = new ReminderEngine(DataJson.Clone(e.Saved), T.AddMinutes(1)); Equal(T.AddMinutes(5), reloaded.PlannedOccurrences(T.AddMinutes(1)).First().DueAt); reloaded.Prefs.PlannedBreaks[0].Name = "改变"; True(reloaded.PlannedOccurrences(T.AddMinutes(2)).All(x => x.DueAt != T.AddMinutes(5))); });
            Test("planned delivery deduplicated", () => { var e = Engine(); e.RecordInteraction("due", Kind.Stretch, T, "once"); e.RecordInteraction("due", Kind.Stretch, T, "once"); Equal(1, e.Day(T).RemindersDue); });
            Test("correction preserves historical aggregates and deadlines", () => { var e = Engine(); e.Day(T).WaterML = 10000; e.Day(T).WaterCount = 40; e.Complete(Kind.Water, T, 250); var id = e.Saved.Events[0].Id; var deadline = e.Deadlines[Kind.Water]; True(e.Correct(id, 350, T)); Equal(10350, e.Day(T).WaterML); Equal(41, e.Day(T).WaterCount); Equal(deadline, e.Deadlines[Kind.Water]); True(e.Correct(id, null, T)); Equal(10000, e.Day(T).WaterML); True(e.Correct(id, 250, T)); Equal(10250, e.Day(T).WaterML); Equal(3, e.Saved.Events[0].Revisions.Count); });
            Test("inconsistent correction rejected without mutation", () => { var e = Engine(); e.Complete(Kind.Eyes, T, 20); e.Day(T).BreakSeconds = 0; True(!e.Correct(e.Saved.Events[0].Id, 30, T)); Equal(1, e.Day(T).EyeBreaks); Equal(20, e.Saved.Events[0].Amount); });
            Test("water undo restores previous deadline", () => { var e = Engine(); var original = e.Deadlines[Kind.Water]; e.Complete(Kind.Water, T.AddSeconds(10), 350); True(e.UndoWater(T.AddSeconds(15))); Equal(original, e.Deadlines[Kind.Water]); Equal(0, e.Day(T).WaterML); True(!e.UndoWater(T)); });
            Test("midnight work splits between days", () => { var midnight = new DateTimeOffset(T.LocalDateTime.Date.AddDays(1), T.Offset); var e = new ReminderEngine(new(), midnight.AddSeconds(-2)); e.Advance(midnight.AddSeconds(2)); Near(2, e.Saved.Days[Labels.Day(midnight.AddSeconds(-1))].WorkSeconds); Near(2, e.Saved.Days[Labels.Day(midnight)].WorkSeconds); });
            Test("Swift date epoch and missing legacy fields", () => { var state = JsonSerializer.Deserialize<SavedState>("{\"version\":1,\"events\":[{\"date\":0,\"kind\":\"water\",\"amount\":250}]}", DataJson.Options)!; Equal(new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero), state.Events[0].Date); Equal(20, state.Preferences.Eyes.DurationSeconds); var copy = DataJson.Clone(state); Equal(state.Events[0].Date, copy.Events[0].Date); });
            Test("atomic persistence and backup", () => { string dir = Path.Combine(Path.GetTempPath(), "huanya-tests-" + Guid.NewGuid()); try { var store = new StateStore(Path.Combine(dir, "state.json")); var state = new SavedState(); state.StretchCycle = 3; store.Save(state); state.StretchCycle = 4; store.Save(state); Equal(4, store.Load().StretchCycle); True(File.Exists(store.Path + ".bak")); File.WriteAllText(store.Path, "broken"); bool failed = false; try { store.Load(); } catch (JsonException) { failed = true; } True(failed); Equal("broken", File.ReadAllText(store.Path)); } finally { Directory.Delete(dir, true); } });
            Test("review pairs only recorded complete dates", () => { var days = new Dictionary<string, DayRecord> { { "2026-11-02", new() { WaterML = 100 } }, { "2026-10-26", new() { WaterML = 200 } }, { "2026-11-03", new() { WaterML = 300 } }, { "2026-10-27", new() { WaterML = 900 } } }; var r = new PeriodReview(false, 0, T.AddDays(1), days); Equal(1, r.Pairs.Count); Equal(100, PeriodReview.Sum(r.Pairs.Select(p => p.Current)).WaterML); });
            Test("month comparisons omit extra days", () => { var now = new DateTimeOffset(2026, 3, 31, 12, 0, 0, T.Offset); var days = new Dictionary<string, DayRecord>(); for (int i = 1; i <= 31; i++) days[$"2026-03-{i:00}"] = new(); for (int i = 1; i <= 28; i++) days[$"2026-02-{i:00}"] = new(); var r = new PeriodReview(true, 0, now, days); Equal(28, r.Pairs.Count); });
            Test("natural away does not add a completed rest", () => { var e = Engine(); for (int i = 1; i <= 250; i++) { e.UpdateIdle(i, false, T.AddSeconds(i)); e.Advance(T.AddSeconds(i)); } e.UpdateIdle(0, false, T.AddSeconds(251)); True(e.Saved.TimingEvents.Any(t => t.Reason == "naturalAway")); Equal(0, e.Day(T).BreakCount); });
            Test("Win32 notification structure uses Unicode layout", () => { var type = typeof(WindowsServices).GetNestedType("NOTIFYICONDATA",System.Reflection.BindingFlags.NonPublic)!; Equal(IntPtr.Size==8?976:956,System.Runtime.InteropServices.Marshal.SizeOf(type)); });
            Test("sleep postpones without counting a user snooze", () => { var session = new Session(new(), T); session.Offer([Kind.Stretch]); session.Start(Kind.Stretch); session.Sleep(true, T.AddSeconds(1)); Equal(0, session.Engine.Day(T).RemindersSnoozed); Equal(0, session.Engine.Saved.Events.Count); True(session.Active == null); });
            Test("notification prewarning starts with one click", () => { var state = new SavedState(); state.Preferences.FloatingReminder = false; state.Preferences.Eyes.IntervalMinutes = 1; var session = new Session(state,T); Batch? delivered = null; bool start = false; session.Notification += (batch, immediate) => { delivered = batch; start = immediate; }; for (int i = 1; i <= 35; i++) session.Tick(T.AddSeconds(i)); True(delivered != null && start); session.OpenNotification(delivered!, start); True(session.Active?.Kind == Kind.Eyes); });
            Test("fractional midnight work is split exactly", () => { var midnight = new DateTimeOffset(T.LocalDateTime.Date.AddDays(1),T.Offset); var e = new ReminderEngine(new(),midnight.AddMilliseconds(-500)); e.Advance(midnight.AddMilliseconds(500)); Near(.5,e.Saved.Days[Labels.Day(midnight.AddSeconds(-1))].WorkSeconds); Near(.5,e.Saved.Days[Labels.Day(midnight)].WorkSeconds); });
            if (args.Contains("--ui"))
                UiTests(args);
            Console.WriteLine($"{passed} tests passed.");
            return 0;
        }
        catch (Exception e) { Console.Error.WriteLine(e); return 1; }
    }
    static void UiTests(string[] args)
    {
        AppBuilder.Configure<App>().UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false }).UseSkia().SetupWithoutStarting();
        using var controller = new Controller(true);
        var main = controller.Main;
        main.Show();
        string output = args.SkipWhile(a => a != "--screenshots").Skip(1).FirstOrDefault() ?? Path.Combine(Path.GetTempPath(), "huanya-ui");
        Directory.CreateDirectory(output);
        foreach (var (page, file) in new[] { ("今日概览", "dashboard"), ("提醒计划", "plans"), ("健康统计", "statistics"), ("设置", "settings") })
        {
            Test("renders " + page, () => { main.SelectPage(page); main.UpdateLayout(); Dispatcher.UIThread.RunJobs(); using var bitmap = new RenderTargetBitmap(new PixelSize(1120, 800), new Vector(96, 96)); bitmap.Render(main); bitmap.Save(Path.Combine(output, file + ".png")); True(main.Bounds.Width >= 1020); });
        }
        main.Width = 1020; main.Height = 650;
        foreach (var page in new[] { "今日概览", "提醒计划", "健康统计", "设置" }) {
            Test("minimum-width buttons fit: " + page, () => {
                main.SelectPage(page); main.UpdateLayout(); Dispatcher.UIThread.RunJobs();
                foreach (var button in main.GetVisualDescendants().OfType<Button>().Where(b => b.IsVisible && b.Bounds.Width > 0)) {
                    var origin = button.TranslatePoint(new Point(0, 0), main);
                    if (origin is {} point) True(point.X >= -1 && point.X + button.Bounds.Width <= main.Bounds.Width + 1, "Clipped button: " + button.Content);
                }
            });
        }
        main.SelectPage("今日概览"); main.UpdateLayout();
        using (var image = new RenderTargetBitmap(new PixelSize(1020,650), new Vector(96,96))) { image.Render(main); image.Save(Path.Combine(output,"dashboard-compact.png")); }
        controller.Session.Offer([Kind.Stretch]);
        var popup = new ReminderWindow(controller);
        popup.Show();
        popup.UpdateLayout();
        Dispatcher.UIThread.RunJobs();
        Test("renders break popup", () => { using var bitmap = new RenderTargetBitmap(new PixelSize(430, 650), new Vector(96, 96)); bitmap.Render(popup); bitmap.Save(Path.Combine(output, "break.png")); });
        popup.Hide();
        main.Hide();
    }
}
