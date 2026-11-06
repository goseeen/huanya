using System.Text.Json;
using System.Text.Json.Serialization;

namespace Huanya.Core;

public enum Kind
{
    Water, Eyes, Stretch
}
public static class Labels
{
    public static readonly Kind[] Kinds = Enum.GetValues<Kind>();
    public static string Title(this Kind k) => k switch { Kind.Water => "喝水提醒", Kind.Eyes => "护眼休息", _ => "起身拉伸" };
    public static string Short(this Kind k) => k switch { Kind.Water => "喝水", Kind.Eyes => "护眼", _ => "拉伸" };
    public static string Message(this Kind k) => k switch { Kind.Water => "给自己倒杯水，慢慢喝几口。", Kind.Eyes => "把视线从屏幕移开，看看远处，让眼睛歇一会儿。", _ => "站起来，舒展肩颈，走动一小会儿。" };
    public static string Day(DateTimeOffset date) => date.ToLocalTime().ToString("yyyy-MM-dd");
    public static string Clock(double seconds)
    {
        var s = Math.Max(0, (int)Math.Ceiling(seconds));
        return $"{s / 60:00}:{s % 60:00}";
    }
    public static string Duration(int seconds) => seconds % 60 == 0 ? $"{seconds / 60} 分钟" : $"{seconds / 60} 分 {seconds % 60} 秒";
    public static string Reason(string reason) => reason switch
    {
        "foregroundStart" => "指定应用处于前台，保留剩余倒计时",
        "foregroundEnd" => "离开指定应用，继续剩余倒计时",
        "idleStart" => "空闲或锁屏，暂停提醒",
        "idleEnd" => "返回电脑，重新计算间隔",
        "manualPause" => "手动暂停提醒",
        "manualResume" => "恢复提醒，重新计算间隔",
        "busyStart" => "进入忙碌模式",
        "busyEnd" => "结束忙碌，重新计算间隔",
        "sleep" => "电脑进入睡眠",
        "wake" => "电脑唤醒，开始新一轮计时",
        "scheduleEnd" => "提醒时段结束",
        "scheduleStart" => "提醒时段开始，重新计算间隔",
        "clockGap" => "检测到计时中断，重新计算间隔",
        "preferences" => "提醒计划已修改",
        "breakStart" => "开始休息",
        "breakEnd" => "休息结束",
        "naturalAway" => "自然离开电脑（估算）",
        "newDay" => "新的一天，使用估算从零开始",
        "awaySession" => "连续离开满 5 分钟，重置使用估算",
        "stoodUp" => "手动确认已起身",
        _ => reason
    };
}
public sealed class Plan
{
    public bool Enabled { get; set; } = true; public int IntervalMinutes
    {
        get; set;
    }
    public int DurationSeconds
    {
        get; set;
    }
    public Plan()
    {
    }
    public Plan(int interval, int duration)
    {
        IntervalMinutes = interval;
        DurationSeconds = duration;
    }
}
public sealed class WorkWindow
{
    public Guid Id { get; set; } = Guid.NewGuid(); public int Start { get; set; } = 540; public int End { get; set; } = 720;
}
public sealed class Routine
{
    public int Weekday
    {
        get; set;
    }
    public bool Enabled { get; set; } = true;
    public List<WorkWindow> Windows { get; set; } = [new(), new() { Start = 780, End = 1080 }];
    [JsonIgnore] public string Title => new[] { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }[Math.Clamp(Weekday - 1, 0, 6)];
    public static List<Routine> Standard() => new[] { 2, 3, 4, 5, 6, 7, 1 }.Select(d => new Routine { Weekday = d, Enabled = d is >= 2 and <= 6 }).ToList();
    public static string? Error(List<Routine> days)
    {
        if (days.Count != 7 || days.Select(d => d.Weekday).Distinct().Count() != 7 || days.Any(d => d.Weekday is < 1 or > 7))
            return "请设置完整、不重复的七天。";
        foreach (var d in days.Where(d => d.Enabled))
        {
            if (d.Windows.Count is < 1 or > 4)
                return $"{d.Title}需要 1–4 个时段。";
            var ws = d.Windows.OrderBy(w => w.Start).ToArray();
            for (int i = 0; i < ws.Length; i++)
            if (ws[i].Start < 0 || ws[i].End > 1440 || ws[i].Start >= ws[i].End || (i > 0 && ws[i - 1].End > ws[i].Start))
                return $"{d.Title}的时段无效或重叠。跨午夜请分到两天。";
        }
        return null;
    }
}
public sealed class LongBreakRule
{
    public bool Enabled
    {
        get; set;
    }
    public int Every { get; set; } = 4; public int DurationSeconds { get; set; } = 600;
}
public sealed class BusyApp
{
    public string Path { get; set; } = ""; public string Name { get; set; } = "";
}
public sealed class PlannedBreak
{
    public Guid Id { get; set; } = Guid.NewGuid(); public string Name { get; set; } = "午间走走"; public bool Enabled { get; set; } = true;
    public int Minute { get; set; } = 720; public List<int> Weekdays { get; set; } = [2, 3, 4, 5, 6]; public Kind Kind { get; set; } = Kind.Stretch; public int DurationSeconds { get; set; } = 300;
    [JsonIgnore] public string Signature => $"{Name}|{Minute}|{string.Join(',', Weekdays.Order())}|{Kind.ToString().ToLowerInvariant()}|{DurationSeconds}";
    [JsonIgnore] public string? Error => string.IsNullOrWhiteSpace(Name) || Name.Length > 30 ? "名称请填写 1–30 个字。" : Minute is < 0 or >= 1440 || DurationSeconds is < 10 or > 1800 || Kind == Kind.Water ? "请检查时间、类型和时长。" : Weekdays.Count == 0 || Weekdays.Any(d => d is < 1 or > 7) ? "请至少选择一天。" : null;
    public Occurrence? On(DateTime date)
    {
        if (!Enabled || Error != null || !Weekdays.Contains((int)date.DayOfWeek + 1))
            return null;
        var due = DateTime.SpecifyKind(date.Date.AddMinutes(Minute), DateTimeKind.Unspecified);
        while (TimeZoneInfo.Local.IsInvalidTime(due))
            due = due.AddMinutes(1);
        var offset = TimeZoneInfo.Local.GetUtcOffset(due);
        return new()
        {
            Id = $"{Id:D}.{date:yyyy-MM-dd}",
            RuleId = Id,
            Title = Name,
            Kind = Kind,
            Duration = DurationSeconds,
            DueAt = new(due, offset),
            RuleSignature = Signature
        };
    }
}
public sealed class Preferences
{
    public Plan Water { get; set; } = new(30, 0); public Plan Eyes { get; set; } = new(20, 20); public Plan Stretch { get; set; } = new(45, 60);
    public int WaterML { get; set; } = 250; public int WaterGoalML { get; set; } = 2000; public int BreakGoal { get; set; } = 8;
    public bool Sound { get; set; } = true; public bool FloatingReminder { get; set; } = true; public bool WorkHoursOnly
    {
        get; set;
    }
    public bool WeekdaysOnly
    {
        get; set;
    }
    public int StartHour { get; set; } = 9; public int EndHour { get; set; } = 18; public bool IdlePauseEnabled { get; set; } = true; public int IdlePauseMinutes { get; set; } = 3;
    public bool MergeReminders { get; set; } = true; public int MergeWindowSeconds { get; set; } = 120;
    public bool PrewarningEnabled { get; set; } = true; public int PrewarningSeconds { get; set; } = 30;
    public int[] WaterPresets { get; set; } = [150, 250, 350]; public List<BusyApp> BusyApplications { get; set; } = [];
    public bool ShowMenuCountdown
    {
        get; set;
    }
    public bool GlobalShortcutsEnabled
    {
        get; set;
    }
    public bool StretchCardsEnabled { get; set; } = true;
    public bool WeeklyRoutineEnabled
    {
        get; set;
    }
    public List<Routine> WeeklyRoutine { get; set; } = Routine.Standard();
    public LongBreakRule LongBreak { get; set; } = new(); public List<PlannedBreak> PlannedBreaks { get; set; } = [];
    [JsonIgnore] public Plan this[Kind kind] => kind switch { Kind.Water => Water, Kind.Eyes => Eyes, _ => Stretch };
    public bool Allows(DateTimeOffset date)
    {
        var d = date.LocalDateTime;
        int weekday = (int)d.DayOfWeek + 1, minute = d.Hour * 60 + d.Minute;
        if (WeeklyRoutineEnabled)
            return WeeklyRoutine.Any(r => r.Weekday == weekday && r.Enabled && r.Windows.Any(w => minute >= w.Start && minute < w.End));
        if (WeekdaysOnly && weekday is 1 or 7)
            return false;
        return !WorkHoursOnly || StartHour == EndHour || (StartHour < EndHour ? d.Hour >= StartHour && d.Hour < EndHour : d.Hour >= StartHour || d.Hour < EndHour);
    }
    public void Validate()
    {
        if (Routine.Error(WeeklyRoutine) != null)
        {
            WeeklyRoutine = Routine.Standard();
            WeeklyRoutineEnabled = false;
        }
        LongBreak.Every = Math.Clamp(LongBreak.Every, 2, 12);
        LongBreak.DurationSeconds = Math.Clamp(LongBreak.DurationSeconds, 60, 1800);
        PlannedBreaks = PlannedBreaks.Where(p => p.Error == null).DistinctBy(p => p.Id).Take(20).ToList();
        foreach (var k in Labels.Kinds)
        {
            this[k].IntervalMinutes = Math.Clamp(this[k].IntervalMinutes, 1, 180);
            this[k].DurationSeconds = k == Kind.Water ? 0 : Math.Clamp(this[k].DurationSeconds, 10, 600);
        }
        WaterML = Math.Clamp(WaterML, 50, 1000);
        WaterGoalML = Math.Clamp(WaterGoalML, 250, 6000);
        BreakGoal = Math.Clamp(BreakGoal, 1, 30);
        StartHour = Math.Clamp(StartHour, 0, 23);
        EndHour = Math.Clamp(EndHour, 0, 23);
        IdlePauseMinutes = Math.Clamp(IdlePauseMinutes, 1, 30);
        MergeWindowSeconds = Math.Clamp(MergeWindowSeconds, 0, 300);
        PrewarningSeconds = Math.Clamp(PrewarningSeconds, 10, 60);
        WaterPresets = Enumerable.Range(0, 3).Select(i => Math.Clamp(i < WaterPresets.Length ? WaterPresets[i] : new[] { 150, 250, 350 }[i], 50, 1000)).ToArray();
        BusyApplications = BusyApplications.Where(a => !string.IsNullOrWhiteSpace(a.Path)).DistinctBy(a => a.Path.ToUpperInvariant()).Take(30).ToList();
    }
}
public sealed class DayRecord
{
    public int WaterML
    {
        get; set;
    }
    public int WaterCount
    {
        get; set;
    }
    public int EyeBreaks
    {
        get; set;
    }
    public int Stretches
    {
        get; set;
    }
    public double WorkSeconds
    {
        get; set;
    }
    public int BreakSeconds
    {
        get; set;
    }
    public double LongestSittingSeconds
    {
        get; set;
    }
    public int RemindersDue
    {
        get; set;
    }
    public int RemindersSnoozed
    {
        get; set;
    }
    public int RemindersSkipped
    {
        get; set;
    }
    public double[] HourlyWorkSeconds { get; set; } = new double[24]; [JsonIgnore] public int BreakCount => EyeBreaks + Stretches;
}
public sealed class ActivityRevision
{
    public DateTimeOffset ChangedAt
    {
        get; set;
    }
    public int PreviousAmount
    {
        get; set;
    }
    public bool WasVoided
    {
        get; set;
    }
}
public sealed class ActivityEvent
{
    public Guid Id { get; set; } = Guid.NewGuid(); public DateTimeOffset Date
    {
        get; set;
    }
    public Kind Kind
    {
        get; set;
    }
    public int Amount
    {
        get; set;
    }
    public string? RecordDay
    {
        get; set;
    }
    public string? Origin
    {
        get; set;
    }
    public string? Label
    {
        get; set;
    }
    public DateTimeOffset? VoidedAt
    {
        get; set;
    }
    public List<ActivityRevision> Revisions { get; set; } = [];
}
public sealed class TimingEvent
{
    public DateTimeOffset Date
    {
        get; set;
    }
    public string Reason { get; set; } = ""; public double? Seconds
    {
        get; set;
    }
}
public sealed class WorkPeriod
{
    public Guid Id { get; set; } = Guid.NewGuid(); public DateTimeOffset Start
    {
        get; set;
    }
    public DateTimeOffset End
    {
        get; set;
    }
    [JsonIgnore] public double Seconds => Math.Max(0, (End - Start).TotalSeconds);
}
public sealed class Interaction
{
    public DateTimeOffset Date
    {
        get; set;
    }
    public Kind Kind
    {
        get; set;
    }
    public string Action { get; set; } = ""; public string? PlannedDeliveryId
    {
        get; set;
    }
}
public sealed class Occurrence
{
    public string Id { get; set; } = ""; public Guid RuleId
    {
        get; set;
    }
    public string Title { get; set; } = ""; public Kind Kind
    {
        get; set;
    }
    public int Duration
    {
        get; set;
    }
    public DateTimeOffset DueAt
    {
        get; set;
    }
    public string? RuleSignature
    {
        get; set;
    }
    public bool Resolved
    {
        get; set;
    }
}
public sealed record Batch(Kind[] Kinds, DateTimeOffset DueAt, Occurrence? Planned = null)
{
    public string Id => $"{Planned?.Id ?? string.Join('-', Kinds)}.{DueAt.UtcTicks}.{Planned?.RuleSignature}";
    public string Title => Planned?.Title ?? string.Join(" · ", Kinds.Select(k => k.Short()));
}
public sealed class SavedState
{
    public int Version { get; set; } = 2; public Preferences Preferences { get; set; } = new(); public Dictionary<string, DayRecord> Days { get; set; } = [];
    public List<ActivityEvent> Events { get; set; } = []; public List<Interaction> ReminderEvents { get; set; } = []; public List<WorkPeriod> WorkPeriods { get; set; } = []; public List<TimingEvent> TimingEvents { get; set; } = [];
    public int StretchCycle
    {
        get; set;
    }
    public List<Occurrence> PlannedHistory { get; set; } = [];
}
// Keep Swift's JSON date epoch for existing records, rather than interpreting it as Unix time.
public sealed class SwiftDateConverter : JsonConverter<DateTimeOffset>
{
    static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => reader.TokenType == JsonTokenType.Number ? Epoch.AddSeconds(reader.GetDouble()) : reader.GetDateTimeOffset();
    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) => writer.WriteNumberValue((value - Epoch).TotalSeconds);
}
public static class DataJson
{
    public static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true, WriteIndented = true, Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase), new SwiftDateConverter() } };
    public static T Clone<T>(T value) => JsonSerializer.Deserialize<T>(JsonSerializer.Serialize(value, Options), Options)!;
}
public sealed class StateStore(string path)
{
    public string Path { get; } = path;
    public SavedState Load()
    {
        if (!File.Exists(Path))
            return new();
        var state = JsonSerializer.Deserialize<SavedState>(File.ReadAllText(Path), DataJson.Options) ?? throw new InvalidDataException("数据为空。");
        if (state.Version > 2)
            throw new InvalidDataException("数据由较新版本创建，请升级应用后重试。");
        state.Preferences.Validate();
        foreach (var day in state.Days.Values)
            day.HourlyWorkSeconds = Enumerable.Range(0, 24).Select(i => i < day.HourlyWorkSeconds.Length ? Math.Max(0, day.HourlyWorkSeconds[i]) : 0).ToArray();
        foreach (var ev in state.Events)
            ev.Revisions ??= [];
        return state;
    }
    public void Save(SavedState state)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        string tmp = Path + ".tmp";
        using (var file = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(file, state, DataJson.Options);
            file.Flush(true);
        }
        if (File.Exists(Path))
            File.Copy(Path, Path + ".bak", true);
        File.Move(tmp, Path, true);
    }
}
