using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml.Styling;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using Avalonia.Threading;
using Huanya.Core;

namespace Huanya.Desktop;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // A second process must never write the same state file or double reminders.
        using var single = new Mutex(true, "Huanya.Windows.Desktop.v2", out var first);
        if (!first)
        {
            WindowsServices.ActivateExisting();
            return;
        }
        BuildApp().StartWithClassicDesktopLifetime(args);
    }
    public static AppBuilder BuildApp() => AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}
public sealed class App : Application
{
    public override void Initialize()
    {
        RequestedThemeVariant = ThemeVariant.Light;
        Styles.Add(new FluentTheme());
        Styles.Add(new StyleInclude(new Uri("avares://Huanya/")) { Source = new Uri("avares://Huanya/Styles.axaml") });
    }
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            bool preview = !OperatingSystem.IsWindows() || desktop.Args?.Contains("--preview") == true;
            var controller = new Controller(preview);
            desktop.MainWindow = controller.Main;
            controller.Start();
            desktop.Exit += (_, _) => controller.Dispose();
            if (OperatingSystem.IsWindows() && desktop.Args?.Contains("--background") == true && controller.Notice == null)
                Dispatcher.UIThread.Post(() => controller.Main.Hide());
        }
        base.OnFrameworkInitializationCompleted();
    }
}
public sealed class Controller : IDisposable
{
    public Session Session
    {
        get;
    }
    public MainWindow Main
    {
        get;
    }
    public WindowsServices? Platform
    {
        get;
    }
    public bool Preview
    {
        get;
    }
    public string? Notice
    {
        get; set;
    }
    public string DataDirectory
    {
        get;
    }
    readonly StateStore store;
    bool canSave = true, exiting;
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    ReminderWindow? reminder;
    PrewarningWindow? prewarning;
    Batch? notification;
    bool notificationStartsRest;
    int ticks;
    string? previousForeground;
    public Controller(bool preview)
    {
        Preview = preview;
        DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), preview ? "Huanya.Windows.Preview" : "Huanya");
        store = new(Path.Combine(DataDirectory, "state.json"));
        var saved = new SavedState();
        if (!preview)
        {
            try
            {
                saved = store.Load();
            }
            catch (Exception e) { canSave = false; Notice = "数据读取失败，原文件已保留，本次不会覆盖。" + e.Message; }
        }
        Session = new(saved, DateTimeOffset.Now);
        if (preview)
            FillDemo();
        Main = new(this);
        if (!preview && OperatingSystem.IsWindows())
        {
            Directory.CreateDirectory(DataDirectory);
            string icon = Path.Combine(DataDirectory, "huanya.ico");
            using (var input = Avalonia.Platform.AssetLoader.Open(new Uri("avares://Huanya/Assets/huanya.ico")))
            using (var output = File.Create(icon))
                input.CopyTo(output);
            Platform = new(icon);
            Platform.ActionRequested += action => Dispatcher.UIThread.Post(() => HandleAction(action));
            Platform.PowerChanged += sleep => Dispatcher.UIThread.Post(() => { Session.Sleep(sleep, DateTimeOffset.Now); SyncWindows(); Save(); });
            Platform.ConfigureShortcuts(Session.Prefs.GlobalShortcutsEnabled);
            if (Platform.Error != null)
                Notice = Platform.Error;
        }
        Session.Notification += (batch, start) => { notification = batch; notificationStartsRest = start; Platform?.Notify(start ? "快到休息时间了" : batch.Title, start ? "点击现在开始休息。" : "点击查看提醒。" + string.Join(" ", batch.Kinds.Select(k => k.Message())), Session.Prefs.Sound); };
        timer.Tick += (_, _) =>
        {
            string? path = Platform == null ? null : WindowsServices.ForegroundPath();
            // A null foreground window during activation is transient, not a definite exit from a busy app.
            if (path != null)
                previousForeground = path;
            bool blocked = previousForeground != null && Session.Prefs.BusyApplications.Any(a => string.Equals(a.Path, previousForeground, StringComparison.OrdinalIgnoreCase));
            if (blocked || Platform?.Locked == true)
                notification = null;
            bool hadPending = Session.Pending.Count > 0;
            Session.Tick(DateTimeOffset.Now, Platform == null ? 0 : WindowsServices.IdleSeconds(), Platform?.Locked ?? false, blocked);
            if (!hadPending && Session.Pending.Count > 0 && Session.Prefs.Sound)
                Platform?.PlaySound();
            Main.UpdateLive();
            SyncWindows();
            Platform?.UpdateTooltip(Session.Prefs.ShowMenuCountdown ? "缓芽 · " + Session.Status + " · " + Session.Countdown : "缓芽 · " + Session.Status);
            if (++ticks % 30 == 0)
                Save();
        };
    }
    void FillDemo()
    {
        for (int i = 0; i < 7; i++)
        {
            var date = Session.Now.AddDays(-i);
            var day = Session.Engine.Day(date);
            day.WaterML = 1250 + i * 50;
            day.EyeBreaks = 4;
            day.Stretches = 2;
            day.BreakSeconds = 200;
            day.WorkSeconds = 12600 + i * 200;
            for (int h = 9; h < 16; h++)
                day.HourlyWorkSeconds[h] = h < 12 ? 2400 : 900;
        }
    }
    public void Start() => timer.Start();
    public void Act(Action action, bool rebuild = true)
    {
        action();
        notification = null;
        Save();
        if (rebuild)
            Main.RenderPage();
        Main.UpdateLive();
        SyncWindows();
    }
    public void Edit(Action<Preferences> change)
    {
        var prefs = DataJson.Clone(Session.Prefs);
        change(prefs);
        bool shortcut = prefs.GlobalShortcutsEnabled != Session.Prefs.GlobalShortcutsEnabled;
        Session.Edit(prefs);
        notification = null;
        if (shortcut)
            Platform?.ConfigureShortcuts(prefs.GlobalShortcutsEnabled);
        Save();
        SyncWindows();
    }
    public void Save()
    {
        if (Preview || !canSave)
            return;
        try
        {
            store.Save(Session.Engine.Saved);
        }
        catch (Exception e) { Notice = "记录保存失败：" + e.Message; Main.ShowNotice(); }
    }
    void HandleAction(string action)
    {
        switch (action)
        {
            case "open":
                Main.Show();
                if (Main.WindowState == WindowState.Minimized)
                    Main.WindowState = WindowState.Normal;
                Main.Activate();
                break;
            case "water":
                Act(() => Session.Water());
                break;
            case "rest":
                Act(() => { Session.Offer([Kind.Stretch]); Session.Start(Kind.Stretch); });
                break;
            case "pause":
                Act(() => Session.Pause(15));
                break;
            case "busy":
                Act(() => Session.Busy(30));
                break;
            case "notification":
                if (notification != null)
                    Act(() => Session.OpenNotification(notification, notificationStartsRest));
                notification = null;
                break;
            case "quit":
                Quit();
                break;
            case "error":
                Notice = Platform?.Error;
                Main.ShowNotice();
                break;
        }
    }
    public void SyncWindows()
    {
        if (Session.Visible)
        {
            if (reminder == null)
            {
                reminder = new(this);
                reminder.Closed += (_, _) => reminder = null;
                reminder.Show();
            }
            else if (!reminder.IsVisible)
                reminder.Show();
            reminder.Update();
        }
        else
            reminder?.Hide();
        if (Session.Prewarning != null)
        {
            if (prewarning == null)
            {
                prewarning = new(this);
                prewarning.Show();
            }
            prewarning.Update();
        }
        else
            prewarning?.Hide();
        if (Session.Prewarning != null && prewarning != null && !prewarning.IsVisible)
            prewarning.Show();
    }
    public bool IsExiting => exiting;
    public bool HideInsteadOfClose => !exiting && Platform != null && Platform.Error == null;
    public void Quit()
    {
        exiting = true;
        Save();
        if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime d)
            d.Shutdown();
    }
    public void Dispose()
    {
        timer.Stop();
        Save();
        Platform?.Dispose();
    }
}
