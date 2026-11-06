namespace Huanya.Core;

public sealed class ReminderEngine
{
    public SavedState Saved
    {
        get;
    }
    public Dictionary<Kind, DateTimeOffset> Deadlines { get; } = [];
    readonly Dictionary<Kind, DateTimeOffset> notBefore = [];
    DateTimeOffset? foregroundUpdated, lastInput, lockBegan, awayStarted;
    bool idlePreserves, usageAway, resetForAbsence, lastAllowed;
    string usageDay;
    WorkPeriod? work;
    public DateTimeOffset LastTick
    {
        get; private set;
    }
    public bool Paused
    {
        get; private set;
    }
    public DateTimeOffset? PausedUntil
    {
        get; private set;
    }
    public DateTimeOffset? BusyUntil
    {
        get; private set;
    }
    public bool Sleeping
    {
        get; private set;
    }
    public bool ForegroundBlocked
    {
        get; private set;
    }
    public bool Idle
    {
        get; private set;
    }
    public bool OnBreak
    {
        get; set;
    }
    public double SittingSeconds
    {
        get; private set;
    }
    public Guid? WaterUndoId => waterUndo?.Id;
    sealed record WaterUndo(Guid Id, string Day, int Amount, DateTimeOffset? Deadline, DateTimeOffset? NotBefore);
    WaterUndo? waterUndo;
    public Preferences Prefs => Saved.Preferences;
    public ReminderEngine(SavedState saved, DateTimeOffset now)
    {
        Saved = saved;
        Prefs.Validate();
        LastTick = now;
        usageDay = Labels.Day(now);
        lastAllowed = Prefs.Allows(now);
        ResetDeadlines(now);
    }
    public bool CanNotify(DateTimeOffset now) => !Paused && !Sleeping && !Idle && !ForegroundBlocked && (BusyUntil == null || BusyUntil <= now);
    public bool IsActive(DateTimeOffset now) => CanNotify(now) && Prefs.Allows(now);
    public DayRecord Day(DateTimeOffset now)
    {
        var key = Labels.Day(now);
        if (!Saved.Days.TryGetValue(key, out var day))
            Saved.Days[key] = day = new();
        return day;
    }
    public void Note(string reason, DateTimeOffset now, double? seconds = null)
    {
        Saved.TimingEvents.Insert(0, new()
        {
            Date = now,
            Reason = reason,
            Seconds = seconds
        });
        Trim(Saved.TimingEvents);
    }
    static void Trim<T>(List<T> list)
    {
        if (list.Count > 1000)
            list.RemoveRange(1000, list.Count - 1000);
    }
    public void ResetDeadlines(DateTimeOffset now)
    {
        foregroundUpdated = ForegroundBlocked || idlePreserves ? now : null;
        foreach (var k in notBefore.Keys.ToArray())
        if (notBefore[k] <= now)
            notBefore.Remove(k);
        foreach (var k in Labels.Kinds)
        {
            var normal = now.AddMinutes(Prefs[k].IntervalMinutes);
            Deadlines[k] = notBefore.TryGetValue(k, out var limit) && limit > normal ? limit : normal;
        }
    }
    public void UpdatePreferences(Preferences value, DateTimeOffset now)
    {
        Shift(now);
        value.Validate();
        var old = Prefs;
        if (System.Text.Json.JsonSerializer.Serialize(old, DataJson.Options) == System.Text.Json.JsonSerializer.Serialize(value, DataJson.Options))
            return;
        Note("preferences", now);
        Saved.Preferences = value;
        if (old.LongBreak.Enabled != value.LongBreak.Enabled || old.LongBreak.Every != value.LongBreak.Every || old.LongBreak.DurationSeconds != value.LongBreak.DurationSeconds)
            Saved.StretchCycle = 0;
        foreach (var k in Labels.Kinds)
        if (old[k].Enabled != value[k].Enabled || old[k].IntervalMinutes != value[k].IntervalMinutes || old[k].DurationSeconds != value[k].DurationSeconds)
        {
            Deadlines[k] = now.AddMinutes(value[k].IntervalMinutes);
            notBefore.Remove(k);
        }
        if (old.WorkHoursOnly != value.WorkHoursOnly || old.WeekdaysOnly != value.WeekdaysOnly || old.StartHour != value.StartHour || old.EndHour != value.EndHour || old.WeeklyRoutineEnabled != value.WeeklyRoutineEnabled || System.Text.Json.JsonSerializer.Serialize(old.WeeklyRoutine) != System.Text.Json.JsonSerializer.Serialize(value.WeeklyRoutine))
            ResetDeadlines(now);
    }
    public void SetPaused(bool value, DateTimeOffset now, DateTimeOffset? until = null)
    {
        RefreshDay(now);
        if (Paused != value)
            Note(value ? "manualPause" : "manualResume", now);
        Paused = value;
        PausedUntil = value ? until : null;
        LastTick = now;
        work = null;
        ResetDeadlines(now);
    }
    public void SetBusy(int? minutes, DateTimeOffset now)
    {
        RefreshDay(now);
        if ((BusyUntil != null) != (minutes != null))
            Note(minutes == null ? "busyEnd" : "busyStart", now);
        BusyUntil = minutes == null ? null : now.AddMinutes(Math.Clamp(minutes.Value, 1, 180));
        work = null;
        LastTick = now;
        ResetDeadlines(now);
    }
    public bool SetForegroundBlocked(bool value, DateTimeOffset now)
    {
        if (ForegroundBlocked == value)
            return false;
        if ((now - LastTick).TotalSeconds is < 0 or > 5)
        {
            ResetUsage(now);
            ResetDeadlines(now);
        }
        else
            Shift(now);
        RefreshDay(now);
        Note(value ? "foregroundStart" : "foregroundEnd", now);
        ForegroundBlocked = value;
        foregroundUpdated = value || idlePreserves ? now : null;
        work = null;
        LastTick = now;
        if (Paused || Sleeping || (Idle && !idlePreserves) || BusyUntil != null || !Prefs.Allows(now))
            ResetDeadlines(now);
        return true;
    }
    void Shift(DateTimeOffset now)
    {
        if (foregroundUpdated == null)
            return;
        var delta = TimeSpan.FromSeconds(Math.Max(0, (now - foregroundUpdated.Value).TotalSeconds));
        foreach (var k in Deadlines.Keys.ToArray())
            Deadlines[k] += delta;
        foreach (var k in notBefore.Keys.ToArray())
            notBefore[k] += delta;
        if (waterUndo != null)
            waterUndo = waterUndo with
            {
                Deadline = waterUndo.Deadline + delta,
                NotBefore = waterUndo.NotBefore + delta
            };
        foregroundUpdated = now;
    }
    public void SetSleeping(bool value, DateTimeOffset now)
    {
        RefreshDay(now);
        if (Sleeping != value)
            Note(value ? "sleep" : "wake", now);
        Sleeping = value;
        awayStarted = null;
        work = null;
        LastTick = now;
        if (!value)
        {
            ResetUsage(now);
            ResetDeadlines(now);
        }
    }
    public bool UpdateIdle(double seconds, bool locked, DateTimeOffset now)
    {
        seconds = double.IsFinite(seconds) ? Math.Max(0, seconds) : 0;
        if (locked && lockBegan == null)
            lockBegan = now;
        bool longAbsence = seconds >= 300 || (lockBegan != null && (now - lockBegan.Value).TotalSeconds >= 300) || (!locked && seconds < 300 && lastInput != null && (now - lastInput.Value).TotalSeconds >= 300);
        if (longAbsence && !resetForAbsence)
        {
            if (SittingSeconds > 0)
                Note("awaySession", now);
            ResetUsage(now);
            work = null;
        }
        usageAway = locked || seconds >= 300;
        resetForAbsence = usageAway && (resetForAbsence || longAbsence);
        lastInput = now.AddSeconds(-seconds);
        if (!locked)
            lockBegan = null;
        bool pause = locked || (Prefs.IdlePauseEnabled && seconds >= Prefs.IdlePauseMinutes * 60);
        bool away = pause || seconds >= 300;
        if (away && !Sleeping && awayStarted == null)
            awayStarted = now;
        if (!away && awayStarted != null)
        {
            double duration = (now - awayStarted.Value).TotalSeconds;
            if (duration is >= 60 and <= 43200 && (now - LastTick).TotalSeconds is >= 0 and <= 5)
                Note("naturalAway", now, duration);
            awayStarted = null;
        }
        if (locked && idlePreserves)
        {
            idlePreserves = false;
            ResetDeadlines(now);
        }
        if (Idle == pause)
            return false;
        Shift(now);
        bool preserve = !locked && (idlePreserves || (pause && ForegroundBlocked));
        Note(pause ? "idleStart" : "idleEnd", now);
        Idle = pause;
        idlePreserves = pause && preserve;
        RefreshDay(now);
        work = null;
        LastTick = now;
        if (preserve)
            foregroundUpdated = ForegroundBlocked || idlePreserves ? now : null;
        else
            ResetDeadlines(now);
        return true;
    }
    void ResetUsage(DateTimeOffset now)
    {
        SittingSeconds = 0;
        usageDay = Labels.Day(now);
    }
    void RefreshDay(DateTimeOffset now)
    {
        if (usageDay != Labels.Day(now))
        {
            Note("newDay", now);
            ResetUsage(now);
            work = null;
        }
    }
    public List<Occurrence> PlannedOccurrences(DateTimeOffset now)
    {
        if (!CanNotify(now) || OnBreak)
            return [];
        var current = Saved.PlannedHistory.Where(o => Prefs.PlannedBreaks.Any(p => p.Enabled && p.Id == o.RuleId && p.Signature == o.RuleSignature)).ToList();
        var result = current.Where(o => !o.Resolved && o.DueAt >= now.AddSeconds(-60)).ToList();
        for (int i = 0; i <= 7; i++)
        foreach (var rule in Prefs.PlannedBreaks)
        {
            var o = rule.On(now.LocalDateTime.AddDays(i));
            if (o != null && o.DueAt >= now.AddSeconds(-60) && !current.Any(c => c.Id == o.Id))
                result.Add(o);
        }
        return result.OrderBy(o => o.DueAt).ToList();
    }
    public bool Accepts(Occurrence o, DateTimeOffset now, int grace = 600) => Prefs.PlannedBreaks.Any(p => p.Id == o.RuleId && p.Enabled && p.Signature == o.RuleSignature) && o.DueAt >= now.AddSeconds(-grace) && !Saved.PlannedHistory.Any(p => p.Id == o.Id && p.RuleSignature == o.RuleSignature && (p.Resolved || p.DueAt != o.DueAt));
    public void Claim(Occurrence o, DateTimeOffset now)
    {
        var item = DataJson.Clone(o);
        item.Resolved = true;
        Saved.PlannedHistory.RemoveAll(p => p.Id == o.Id);
        Saved.PlannedHistory.Add(item);
        if (Saved.PlannedHistory.Count > 1000)
            Saved.PlannedHistory.RemoveAt(0);
    }
    public void SnoozePlanned(Occurrence o, DateTimeOffset now)
    {
        var item = DataJson.Clone(o);
        item.DueAt = now.AddMinutes(5);
        item.Resolved = false;
        Saved.PlannedHistory.RemoveAll(p => p.Id == o.Id);
        Saved.PlannedHistory.Add(item);
        if (Saved.PlannedHistory.Count > 1000)
            Saved.PlannedHistory.RemoveAt(0);
    }
    public List<Batch> Batches(DateTimeOffset now)
    {
        if (!CanNotify(now) || OnBreak)
            return [];
        var result = PlannedOccurrences(now).Take(1).Select(o => new Batch([o.Kind], o.DueAt, o)).ToList();
        if (!IsActive(now))
            return result;
        var remaining = Labels.Kinds.Where(k => Prefs[k].Enabled).OrderBy(k => Deadlines[k]).ToList();
        int window = Prefs.MergeReminders ? Prefs.MergeWindowSeconds : 0;
        while (remaining.Count > 0)
        {
            var anchor = Deadlines[remaining[0]];
            var members = remaining.Where(k => Deadlines[k] <= anchor.AddSeconds(window) && (!notBefore.TryGetValue(k, out var minimum) || minimum <= anchor)).ToArray();
            if (members.Length == 0)
            {
                remaining.RemoveAt(0);
                continue;
            }
            if (Prefs.Allows(anchor))
                result.Add(new(Labels.Kinds.Where(members.Contains).ToArray(), anchor));
            remaining.RemoveAll(members.Contains);
        }
        return result.OrderBy(b => b.DueAt).ToList();
    }
    public Kind[] Advance(DateTimeOffset now, IEnumerable<Kind>? pending = null, bool count = true)
    {
        if (BusyUntil <= now)
            SetBusy(null, now);
        if (Paused && PausedUntil <= now)
            SetPaused(false, now);
        bool allowed = Prefs.Allows(now);
        if (lastAllowed != allowed)
        {
            Note(allowed ? "scheduleStart" : "scheduleEnd", now);
            lastAllowed = allowed;
            if (allowed)
                ResetDeadlines(now);
        }
        var before = LastTick;
        double elapsed = (now - before).TotalSeconds;
        LastTick = now;
        if (elapsed is < 0 or > 5)
        {
            Note("clockGap", now);
            awayStarted = null;
            work = null;
            ResetUsage(now);
            ResetDeadlines(now);
            return [];
        }
        if (!IsActive(now))
        {
            RefreshDay(now);
            work = null;
            if (!allowed)
                ResetUsage(now);
            if ((ForegroundBlocked || idlePreserves) && !Paused && !Sleeping && (!Idle || idlePreserves) && BusyUntil == null && allowed)
                Shift(now);
            else
                ResetDeadlines(now);
            return [];
        }
        if (!OnBreak && elapsed > 0)
            AddWork(before, now);
        else if (OnBreak)
        {
            RefreshDay(now);
            work = null;
        }
        var due = Batches(now).Where(b => b.Planned == null && b.DueAt <= now).SelectMany(b => b.Kinds).Where(k => !(pending?.Contains(k) ?? false)).Distinct().ToArray();
        foreach (var k in due)
        {
            if (count)
                RecordInteraction("due", k, now);
            Deadlines[k] = now.AddMinutes(Prefs[k].IntervalMinutes);
            notBefore.Remove(k);
        }
        return due;
    }
    void AddWork(DateTimeOffset from, DateTimeOffset to)
    {
        // Split at local hour/day boundaries; an individual observed tick never exceeds five seconds.
        var cursor = from;
        while (cursor < to)
        {
            var boundary = cursor.AddTicks(TimeSpan.TicksPerSecond - cursor.Ticks % TimeSpan.TicksPerSecond);
            var end = boundary < to ? boundary : to;
            double s = (end - cursor).TotalSeconds;
            RefreshDay(cursor);
            if (!usageAway)
                SittingSeconds += s;
            var day = Day(cursor);
            day.WorkSeconds += s;
            day.LongestSittingSeconds = Math.Max(day.LongestSittingSeconds, SittingSeconds);
            day.HourlyWorkSeconds[cursor.LocalDateTime.Hour] += s;
            if (work != null && Math.Abs((work.End - cursor).TotalSeconds) < .001 && Labels.Day(work.Start) == Labels.Day(cursor))
                work.End = end;
            else
            {
                work = new()
                {
                    Start = cursor,
                    End = end
                };
                Saved.WorkPeriods.Add(work);
                if (Saved.WorkPeriods.Count > 1000)
                    Saved.WorkPeriods.RemoveAt(0);
            }
            cursor = end;
        }
        RefreshDay(to);
    }
    public void RecordInteraction(string action, Kind kind, DateTimeOffset now, string? deliveryId = null)
    {
        if (deliveryId != null && Saved.ReminderEvents.Any(e => e.Action == action && e.PlannedDeliveryId == deliveryId))
            return;
        var day = Day(now);
        switch (action)
        {
            case "due":
                day.RemindersDue++;
                break;
            case "snoozed":
                day.RemindersSnoozed++;
                break;
            case "skipped":
                day.RemindersSkipped++;
                break;
        }
        Saved.ReminderEvents.Insert(0, new()
        {
            Date = now,
            Kind = kind,
            Action = action,
            PlannedDeliveryId = deliveryId
        });
        Trim(Saved.ReminderEvents);
    }
    public void Skip(Kind kind, DateTimeOffset now)
    {
        Shift(now);
        RecordInteraction("skipped", kind, now);
        Deadlines[kind] = now.AddMinutes(Prefs[kind].IntervalMinutes);
        notBefore.Remove(kind);
    }
    public void Snooze(Kind kind, DateTimeOffset now)
    {
        Shift(now);
        Deadlines[kind] = now.AddMinutes(5);
        notBefore[kind] = Deadlines[kind];
    }
    public void StoodUp(DateTimeOffset now)
    {
        SittingSeconds = 0;
        Note("stoodUp", now);
    }
    public bool IsLongBreak(Kind kind) => kind == Kind.Stretch && Prefs.LongBreak.Enabled && (Saved.StretchCycle + 1) % Prefs.LongBreak.Every == 0;
    public int RestDuration(Kind kind) => IsLongBreak(kind) ? Prefs.LongBreak.DurationSeconds : Prefs[kind].DurationSeconds;
    public void Complete(Kind kind, DateTimeOffset now, int? amount = null, string? label = null, bool advancesCycle = true)
    {
        Shift(now);
        var day = Day(now);
        int quantity = kind == Kind.Water ? Math.Clamp(amount ?? Prefs.WaterML, 50, 1000) : amount ?? RestDuration(kind);
        switch (kind)
        {
            case Kind.Water:
                day.WaterML += quantity;
                day.WaterCount++;
                break;
            case Kind.Eyes:
                day.EyeBreaks++;
                day.BreakSeconds += quantity;
                break;
            case Kind.Stretch:
                day.Stretches++;
                day.BreakSeconds += quantity;
                SittingSeconds = 0;
                if (advancesCycle)
                    Saved.StretchCycle = (Saved.StretchCycle + 1) % Prefs.LongBreak.Every;
                break;
        }
        var item = new ActivityEvent { Date = now, Kind = kind, Amount = quantity, RecordDay = Labels.Day(now), Origin = "confirmed", Label = label };
        if (kind == Kind.Water)
            waterUndo = new(item.Id, item.RecordDay, quantity, Deadlines.GetValueOrDefault(kind), notBefore.TryGetValue(kind, out var n) ? n : null);
        Saved.Events.Insert(0, item);
        Trim(Saved.Events);
        Deadlines[kind] = now.AddMinutes(Prefs[kind].IntervalMinutes);
        notBefore.Remove(kind);
    }
    public bool UndoWater(DateTimeOffset now)
    {
        Shift(now);
        if (waterUndo == null)
            return false;
        var u = waterUndo;
        if (!Saved.Events.Any(e => e.Id == u.Id) || !Saved.Days.TryGetValue(u.Day, out var day))
            return false;
        day.WaterML = Math.Max(0, day.WaterML - u.Amount);
        day.WaterCount = Math.Max(0, day.WaterCount - 1);
        Saved.Events.RemoveAll(e => e.Id == u.Id);
        waterUndo = null;
        Deadlines[Kind.Water] = u.Deadline > now.AddSeconds(30) ? u.Deadline.Value : now.AddSeconds(30);
        if (u.NotBefore != null)
            notBefore[Kind.Water] = u.NotBefore.Value;
        else
            notBefore.Remove(Kind.Water);
        return true;
    }
    public bool Correct(Guid id, int? amount, DateTimeOffset now)
    {
        var e = Saved.Events.FirstOrDefault(e => e.Id == id);
        if (e == null || (amount != null && (amount < (e.Kind == Kind.Water ? 50 : 10) || amount > (e.Kind == Kind.Water ? 1000 : 1800))))
            return false;
        string key = e.RecordDay ?? Labels.Day(e.Date);
        if (!Saved.Days.TryGetValue(key, out var day))
            return false;
        bool wasVoid = e.VoidedAt != null;
        if (wasVoid && amount == null)
            return false;
        if (!wasVoid)
        {
            switch (e.Kind)
            {
                case Kind.Water:
                    if (day.WaterCount <= 0 || day.WaterML < e.Amount)
                        return false;
                    day.WaterCount--;
                    day.WaterML -= e.Amount;
                    break;
                case Kind.Eyes:
                    if (day.EyeBreaks <= 0 || day.BreakSeconds < e.Amount)
                        return false;
                    day.EyeBreaks--;
                    day.BreakSeconds -= e.Amount;
                    break;
                default:
                    if (day.Stretches <= 0 || day.BreakSeconds < e.Amount)
                        return false;
                    day.Stretches--;
                    day.BreakSeconds -= e.Amount;
                    break;
            }
        }
        e.Revisions.Add(new()
        {
            ChangedAt = now,
            PreviousAmount = e.Amount,
            WasVoided = wasVoid
        });
        if (e.Revisions.Count > 100)
            e.Revisions.RemoveAt(0);
        e.VoidedAt = amount == null ? now : null;
        e.RecordDay = key;
        if (amount != null)
        {
            e.Amount = amount.Value;
            switch (e.Kind)
            {
                case Kind.Water:
                    day.WaterML += e.Amount;
                    day.WaterCount++;
                    break;
                case Kind.Eyes:
                    day.EyeBreaks++;
                    day.BreakSeconds += e.Amount;
                    break;
                default:
                    day.Stretches++;
                    day.BreakSeconds += e.Amount;
                    break;
            }
        }
        if (waterUndo?.Id == id)
            waterUndo = null;
        return true;
    }
}

public sealed class PeriodReview
{
    public DateTime Start
    {
        get;
    }
    public DateTime End
    {
        get;
    }
    public List<(DateTime Date, DayRecord? Record)> Records { get; } = [];
    public List<(DayRecord Current, DayRecord Previous)> Pairs { get; } = [];
    public PeriodReview(bool month, int offset, DateTimeOffset now, Dictionary<string, DayRecord> days)
    {
        var date = now.LocalDateTime.Date;
        var baseStart = month ? new DateTime(date.Year, date.Month, 1) : date.AddDays(-(((int)date.DayOfWeek + 6) % 7));
        Start = month ? baseStart.AddMonths(Math.Min(0, offset)) : baseStart.AddDays(Math.Min(0, offset) * 7);
        End = month ? Start.AddMonths(1) : Start.AddDays(7);
        var previous = month ? Start.AddMonths(-1) : Start.AddDays(-7);
        for (var d = Start; d < End; d = d.AddDays(1))
        {
            var current = d <= date ? days.GetValueOrDefault(d.ToString("yyyy-MM-dd")) : null;
            Records.Add((d, current));
            var p = previous.AddDays((d - Start).Days);
            if (d < date && p < Start && current != null && days.TryGetValue(p.ToString("yyyy-MM-dd"), out var prior))
                Pairs.Add((current, prior));
        }
    }
    public static DayRecord Sum(IEnumerable<DayRecord?> records)
    {
        var sum = new DayRecord();
        foreach (var d in records.OfType<DayRecord>())
        {
            sum.WaterML += d.WaterML;
            sum.EyeBreaks += d.EyeBreaks;
            sum.Stretches += d.Stretches;
            sum.WorkSeconds += d.WorkSeconds;
            sum.BreakSeconds += d.BreakSeconds;
        }
        return sum;
    }
}
