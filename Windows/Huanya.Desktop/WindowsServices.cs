using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Huanya.Desktop;

// This adapter reads process identity and aggregate idle time only. No keyboard or screen capture.
public sealed class WindowsServices : IDisposable
{
    const uint Callback = 0x8001, CommandMessage = 0x8002, WM_CLOSE = 0x10;
    readonly Thread? thread;
    readonly ManualResetEventSlim ready = new();
    readonly WndProc procedure;
    readonly System.Collections.Concurrent.ConcurrentQueue<Action> queue = new();
    IntPtr hwnd, icon;
    uint taskbarCreated;
    readonly string iconPath;
    string tip = "缓芽 · huǎn yá";
    public volatile bool Locked;
    public string? Error
    {
        get; private set;
    }
    public event Action<string>? ActionRequested;
    public event Action<bool>? PowerChanged;
    public WindowsServices(string iconPath)
    {
        this.iconPath = iconPath;
        procedure = WindowProc;
        if (!OperatingSystem.IsWindows())
        {
            ready.Set();
            return;
        }
        thread = new Thread(Run) { IsBackground = true, Name = "Huanya.WindowsEvents" };
        thread.Start();
        if (!ready.Wait(TimeSpan.FromSeconds(5)))
            Error = "Windows 托盘启动超时，请退出后重试。";
    }
    public static void ActivateExisting()
    {
        if (OperatingSystem.IsWindows())
        {
            var window = FindWindow("Huanya.EventWindow", "Huanya");
            if (window != IntPtr.Zero)
                PostMessage(window, 0x8003, IntPtr.Zero, IntPtr.Zero);
        }
    }
    public static double IdleSeconds()
    {
        if (!OperatingSystem.IsWindows())
            return 0;
        var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        return GetLastInputInfo(ref info) ? unchecked((uint)Environment.TickCount - info.dwTime) / 1000.0 : 0;
    }
    public static string? ForegroundPath()
    {
        if (!OperatingSystem.IsWindows())
            return null;
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero)
            return null;
        GetWindowThreadProcessId(window, out var pid);
        try
        {
            using var p = Process.GetProcessById((int)pid);
            return p.MainModule?.FileName;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or ArgumentException) { return string.Empty; }
    }
    public static bool StartupEnabled
    {
        get
        {
            if (!OperatingSystem.IsWindows())
                return false;
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
            return key?.GetValue("Huanya") != null;
        }
    }
    public static void SetStartup(bool enabled)
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("请在 Windows 上设置开机启动。");
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled)
            key.SetValue("Huanya", $"\"{Environment.ProcessPath}\" --background");
        else
            key.DeleteValue("Huanya", false);
    }
    public void ConfigureShortcuts(bool enabled) => Post(() =>
    {
        UnregisterHotKey(hwnd, 1);
        UnregisterHotKey(hwnd, 2);
        if (enabled && (!RegisterHotKey(hwnd, 1, 0x4000 | 2 | 1 | 4, 0x57) || !RegisterHotKey(hwnd, 2, 0x4000 | 2 | 1 | 4, 0x52)))
        {
            UnregisterHotKey(hwnd, 1);
            UnregisterHotKey(hwnd, 2);
            Error = "快捷键被其他应用占用，请关闭冲突快捷键后重试。";
            ActionRequested?.Invoke("error");
        }
    });
    public void UpdateTooltip(string value)
    {
        if (value == tip)
            return;
        tip = value;
        Post(() => { var data = IconData(); data.uFlags = 4; Shell_NotifyIcon(1, ref data); });
    }
    public void Notify(string title, string body, bool sound) => Post(() => { var data = IconData(); data.uFlags = 0x10; data.szInfoTitle = title[..Math.Min(title.Length, 63)]; data.szInfo = body[..Math.Min(body.Length, 255)]; data.dwInfoFlags = sound ? 1u : 0x11u; Shell_NotifyIcon(1, ref data); });
    public void PlaySound()
    {
        if (OperatingSystem.IsWindows())
            MessageBeep(0x40);
    }
    void Post(Action action)
    {
        if (hwnd == IntPtr.Zero)
            return;
        queue.Enqueue(action);
        PostMessage(hwnd, CommandMessage, IntPtr.Zero, IntPtr.Zero);
    }
    NOTIFYICONDATA IconData() => new() { cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(), hWnd = hwnd, uID = 1, uFlags = 1 | 2 | 4, uCallbackMessage = Callback, hIcon = icon, szTip = tip[..Math.Min(tip.Length, 127)], szInfo = "", szInfoTitle = "" };
    void AddIcon()
    {
        var data = IconData();
        if (!Shell_NotifyIcon(0, ref data))
            Error = "无法创建系统托盘图标，关闭窗口将退出应用。";
    }
    void Run()
    {
        try
        {
            var cls = new WNDCLASS { lpfnWndProc = procedure, lpszClassName = "Huanya.EventWindow", hInstance = GetModuleHandle(null) };
            if (RegisterClass(ref cls) == 0)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            hwnd = CreateWindowEx(0, cls.lpszClassName, "Huanya", 0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, cls.hInstance, IntPtr.Zero);
            if (hwnd == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            icon = LoadImage(IntPtr.Zero, iconPath, 1, 32, 32, 0x10);
            taskbarCreated = RegisterWindowMessage("TaskbarCreated");
            WTSRegisterSessionNotification(hwnd, 0);
            // Query the initial input desktop so launching while locked does not start work counting.
            var desktop = OpenInputDesktop(0, false, 0x0001);
            var desktopName = new System.Text.StringBuilder(256);
            Locked = desktop == IntPtr.Zero || !GetUserObjectInformation(desktop, 2, desktopName, 512, out _) || !string.Equals(desktopName.ToString(), "Default", StringComparison.OrdinalIgnoreCase);
            if (desktop != IntPtr.Zero) CloseDesktop(desktop);
            AddIcon();
            ready.Set();
            while (GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
        }
        catch (Exception e) { Error = "Windows 系统集成未启动：" + e.Message; ready.Set(); }
    }
    IntPtr WindowProc(IntPtr window, uint msg, IntPtr w, IntPtr l)
    {
        if (msg == 0x8003)
        {
            ActionRequested?.Invoke("open");
            return IntPtr.Zero;
        }
        if (msg == CommandMessage)
        {
            while (queue.TryDequeue(out var action))
                action();
            return IntPtr.Zero;
        }
        if (msg == taskbarCreated && taskbarCreated != 0)
        {
            AddIcon();
            return IntPtr.Zero;
        }
        if (msg == 0x2B1)
        {
            if (w.ToInt32() is 7 or 4)
                Locked = true;
            if (w.ToInt32() is 8 or 3)
                Locked = false;
            return IntPtr.Zero;
        }
        if (msg == 0x218)
        {
            if (w.ToInt32() == 4)
                PowerChanged?.Invoke(true);
            if (w.ToInt32() is 7 or 18)
                PowerChanged?.Invoke(false);
            return new(1);
        }
        if (msg == 0x312)
        {
            ActionRequested?.Invoke(w.ToInt32() == 1 ? "water" : "rest");
            return IntPtr.Zero;
        }
        if (msg == Callback)
        {
            int code = l.ToInt32() & 0xFFFF;
            if (code == 0x202)
                ActionRequested?.Invoke("open");
            if (code == 0x405)
                ActionRequested?.Invoke("notification");
            if (code == 0x205)
                Menu();
            return IntPtr.Zero;
        }
        if (msg == WM_CLOSE)
        {
            UnregisterHotKey(window, 1);
            UnregisterHotKey(window, 2);
            WTSUnRegisterSessionNotification(window);
            var data = IconData();
            Shell_NotifyIcon(2, ref data);
            if (icon != IntPtr.Zero)
                DestroyIcon(icon);
            DestroyWindow(window);
            hwnd = IntPtr.Zero;
            PostQuitMessage(0);
            return IntPtr.Zero;
        }
        return DefWindowProc(window, msg, w, l);
    }
    void Menu()
    {
        var menu = CreatePopupMenu();
        var items = new[] { ("open", "打开缓芽"), ("water", "记录默认杯量"), ("rest", "起身休息"), ("pause", "暂停 15 分钟 / 继续提醒"), ("busy", "忙碌 30 分钟"), ("quit", "退出缓芽") };
        for (int i = 0; i < items.Length; i++)
            AppendMenu(menu, 0, (nuint)(i + 1), items[i].Item2);
        GetCursorPos(out var point);
        SetForegroundWindow(hwnd);
        int chosen = TrackPopupMenu(menu, 0x100 | 2, point.X, point.Y, 0, hwnd, IntPtr.Zero);
        DestroyMenu(menu);
        if (chosen > 0 && chosen <= items.Length)
            ActionRequested?.Invoke(items[chosen - 1].Item1);
    }
    public void Dispose()
    {
        if (hwnd != IntPtr.Zero)
            PostMessage(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
        thread?.Join(2000);
        if (thread == null || !thread.IsAlive) ready.Dispose();
    }
    delegate IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO
    {
        public uint cbSize, dwTime;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct POINT
    {
        public int X, Y;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct MSG
    {
        public IntPtr hwnd; public uint message; public nuint wParam; public nint lParam; public uint time; public POINT pt; public uint lPrivate;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASS
    {
        public uint style; public WndProc lpfnWndProc; public int cbClsExtra, cbWndExtra; public IntPtr hInstance, hIcon, hCursor, hbrBackground; public string? lpszMenuName; public string lpszClassName;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NOTIFYICONDATA
    {
        public uint cbSize; public IntPtr hWnd; public uint uID, uFlags, uCallbackMessage; public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState, dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uTimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] static extern bool MessageBeep(uint type);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern ushort RegisterClass(ref WNDCLASS cls);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWindowEx(uint ex, string cls, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr DefWindowProc(IntPtr window, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetMessage(out MSG msg, IntPtr window, uint min, uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr DispatchMessage(ref MSG msg);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool PostMessage(IntPtr window, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern void PostQuitMessage(int code);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern bool Shell_NotifyIcon(uint message, ref NOTIFYICONDATA data);
    [DllImport("wtsapi32.dll")] static extern bool WTSRegisterSessionNotification(IntPtr window, uint flags);
    [DllImport("wtsapi32.dll")] static extern bool WTSUnRegisterSessionNotification(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool AppendMenu(IntPtr menu, uint flags, nuint id, string text);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern int TrackPopupMenu(IntPtr menu, uint flags, int x, int y, int reserved, IntPtr window, IntPtr rect);
    [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr handle, int index, System.Text.StringBuilder value, uint length, out uint needed);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
}
