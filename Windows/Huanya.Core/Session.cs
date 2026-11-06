namespace Huanya.Core;

public sealed record ActiveBreak(Kind Kind, DateTimeOffset EndsAt, int Duration, string Label, bool Planned);
public sealed class Session
{
    public ReminderEngine Engine
    {
        get;
    }
    public Preferences Prefs => Engine.Prefs;
    public DateTimeOffset Now
    {
        get; private set;
    }
    public List<Kind> Pending { get; } = [];
    public Occurrence? Planned
    {
        get; private set;
    }
    public ActiveBreak? Active
    {
        get; private set;
    }
    public Batch? Prewarning
    {
        get; private set;
    }
    public int Card
    {
        get; private set;
    }
    DateTimeOffset cardChanged;
    HashSet<string> dismissed = [];
    HashSet<string> notifiedPrewarnings = [];
    public bool Locked
    {
        get; private set;
    }
    public bool Visible => Pending.Count > 0 && Engine.CanNotify(Now) && (Prefs.Allows(Now) || Planned != null);
    public int Remaining => Math.Max(0, (int)Math.Ceiling(((Active?.EndsAt ?? Now) - Now).TotalSeconds));
    public event Action<Batch, bool>? Notification;
    public event Action? Changed;
    public Session(SavedState state, DateTimeOffset now)
    {
        Now = now;
        Engine = new(state, now);
        cardChanged = now;
    }
    public string Status => Engine.Sleeping ? "电脑睡眠中" : Locked ? "锁屏 / 会话暂停" : Active != null ? "正在休息" : Engine.Paused ? "提醒已暂停" : Engine.BusyUntil > Now ? "忙碌中 · " + Labels.Clock((Engine.BusyUntil.Value - Now).TotalSeconds) : Engine.ForegroundBlocked ? "指定应用使用中 · 暂停" : Engine.Idle ? "空闲中 · 自动暂停" : !Prefs.Allows(Now) ? "非提醒时段" : "好状态，进行中";
    public string Countdown => Engine.Batches(Now).FirstOrDefault() is { } b ? Labels.Clock((b.DueAt - Now).TotalSeconds) : "— —";
    public string Title(Kind k) => Active?.Kind == k ? Active.Label : Planned?.Kind == k ? Planned.Title : Engine.IsLongBreak(k) ? "起身长休息" : k.Title();
    public int Duration(Kind k) => Planned?.Kind == k ? Planned.Duration : Engine.RestDuration(k);
    public void Tick(DateTimeOffset now, double idleSeconds = 0, bool locked = false, bool foregroundBlocked = false)
    {
        var before = Now;
        Now = now;
        Locked = locked;
        bool changed = Engine.SetForegroundBlocked(foregroundBlocked, now);
        changed |= Engine.UpdateIdle(idleSeconds, locked, now);
        if (changed)
        {
            Prewarning = null;
            if (Engine.Idle || foregroundBlocked)
            {
                Pending.RemoveAll(k => Active?.Kind != k);
                if (Active == null)
                    Planned = null;
            }
        }
        var due = Engine.Advance(now, Pending);
        bool mayShow = Engine.CanNotify(now) && (Prefs.Allows(now) || Planned != null);
        if (!mayShow)
        {
            Prewarning = null;
            if (Active == null)
            {
                Pending.Clear();
                Planned = null;
            }
        }
        else if (due.Length > 0)
        {
            if (Prefs.FloatingReminder)
                Offer(due);
            else
                Notification?.Invoke(new(due, now), false);
        }
        if (Engine.CanNotify(now) && Active == null && Pending.Count == 0 && Engine.PlannedOccurrences(now).FirstOrDefault() is { } planned && planned.DueAt <= now)
        {
            if (Prefs.FloatingReminder)
                OfferPlanned(planned);
            else
            {
                var batch = new Batch([planned.Kind], planned.DueAt, planned);
                if (!Engine.Saved.ReminderEvents.Any(e => e.PlannedDeliveryId == batch.Id && e.Action == "due"))
                {
                    Engine.RecordInteraction("due", planned.Kind, now, batch.Id);
                    Notification?.Invoke(batch, false);
                }
            }
        }
        if (Visible && Pending.Contains(Kind.Stretch) && Prefs.StretchCardsEnabled && (Active == null || Remaining > 0))
        {
            if ((now - before).TotalSeconds is < 0 or > 5)
                cardChanged = now;
            else if ((now - cardChanged).TotalSeconds >= 20)
                CycleCard();
        }
        else
            cardChanged = now;
        var batches = Engine.Batches(now);
        dismissed.IntersectWith(batches.Select(b => b.Id));
        var next = batches.FirstOrDefault();
        notifiedPrewarnings.IntersectWith(batches.Select(b => b.Id));
        if (!Prefs.FloatingReminder && Prefs.PrewarningEnabled && Pending.Count == 0 && next != null && (next.DueAt - now).TotalSeconds > 0 && (next.DueAt - now).TotalSeconds <= Prefs.PrewarningSeconds && notifiedPrewarnings.Add(next.Id))
            Notification?.Invoke(next, true);
        Prewarning = Prefs.FloatingReminder && Prefs.PrewarningEnabled && Pending.Count == 0 && next != null && !dismissed.Contains(next.Id) && (next.DueAt - now).TotalSeconds > 0 && (next.DueAt - now).TotalSeconds <= Prefs.PrewarningSeconds ? next : null;
        Changed?.Invoke();
    }
    public void Offer(IEnumerable<Kind> kinds)
    {
        foreach (var k in kinds)
        if (!Pending.Contains(k))
            Pending.Add(k);
        Pending.Sort();
        Prewarning = null;
        cardChanged = Now;
        Changed?.Invoke();
    }
    public void OfferPlanned(Occurrence occurrence)
    {
        if (!Engine.CanNotify(Now) || Active != null || Pending.Count > 0 || !Engine.Accepts(occurrence, Now))
            return;
        Planned = occurrence;
        Engine.Claim(occurrence, Now);
        Engine.RecordInteraction("due", occurrence.Kind, Now, new Batch([occurrence.Kind], occurrence.DueAt, occurrence).Id);
        Offer([occurrence.Kind]);
    }
    public void OpenNotification(Batch batch, bool startNow = false)
    {
        if (!Engine.CanNotify(Now) || (Now - batch.DueAt).TotalSeconds > 600)
            return;
        if (batch.Planned != null)
            OfferPlanned(batch.Planned);
        else if (Prefs.Allows(Now))
            Offer(batch.Kinds.Where(k => Prefs[k].Enabled));
        if (startNow && Pending.FirstOrDefault(k => k != Kind.Water) is var kind && kind != Kind.Water)
            Start(kind);
    }
    public void TakePrewarning()
    {
        var batch = Prewarning;
        if (batch == null || !Engine.CanNotify(Now))
            return;
        dismissed.Add(batch.Id);
        if (batch.Planned != null)
            OfferPlanned(batch.Planned);
        else
            Offer(batch.Kinds);
        var timed = Pending.Where(k => k != Kind.Water).Cast<Kind?>().FirstOrDefault();
        if (timed != null)
            Start(timed.Value);
    }
    public void DismissPrewarning()
    {
        if (Prewarning != null)
            dismissed.Add(Prewarning.Id);
        Prewarning = null;
        Changed?.Invoke();
    }
    public void Start(Kind kind)
    {
        if (Active != null || !Pending.Contains(kind))
            return;
        if (kind == Kind.Water)
        {
            Water();
            return;
        }
        int duration = Duration(kind);
        Active = new(kind, Now.AddSeconds(duration), duration, Title(kind), Planned?.Kind == kind);
        Engine.OnBreak = true;
        Engine.Note("breakStart", Now);
        cardChanged = Now;
        Changed?.Invoke();
    }
    public void Finish()
    {
        if (Active == null || Remaining > 0)
            return;
        var active = Active;
        Engine.Complete(active.Kind, Now, active.Duration, active.Label, !active.Planned);
        Engine.Note("breakEnd", Now);
        Active = null;
        Engine.OnBreak = false;
        Remove(active.Kind);
    }
    public void Water(int? amount = null)
    {
        Engine.Complete(Kind.Water, Now, amount);
        Remove(Kind.Water);
        Prewarning = null;
        Changed?.Invoke();
    }
    void Remove(Kind kind)
    {
        Pending.Remove(kind);
        if (Planned?.Kind == kind)
            Planned = null;
        Changed?.Invoke();
    }
    public void Snooze(Kind? selected = null)
    {
        Dismiss(selected, true);
    }
    public void Skip(Kind? selected = null)
    {
        Dismiss(selected, false);
    }
    void Dismiss(Kind? selected, bool snooze, bool recordInteraction = true)
    {
        foreach (var kind in Pending.Where(k => selected == null || k == selected).ToArray())
        {
            if (snooze)
            {
                if (Planned?.Kind == kind)
                    Engine.SnoozePlanned(Planned, Now);
                else
                    Engine.Snooze(kind, Now);
                if (recordInteraction) Engine.RecordInteraction("snoozed", kind, Now);
            }
            else if (Planned?.Kind == kind)
                Engine.RecordInteraction("skipped", kind, Now);
            else
                Engine.Skip(kind, Now);
            if (Active?.Kind == kind)
            {
                Active = null;
                Engine.OnBreak = false;
                Engine.Note("breakEnd", Now);
            }
            Remove(kind);
        }
        Prewarning = null;
        Changed?.Invoke();
    }
    public void Pause(int? minutes = null)
    {
        Pending.Clear();
        Planned = null;
        Active = null;
        Engine.OnBreak = false;
        Prewarning = null;
        if (Engine.Paused || Engine.BusyUntil != null)
        {
            Engine.SetPaused(false, Now);
            Engine.SetBusy(null, Now);
        }
        else
            Engine.SetPaused(true, Now, minutes == null ? null : Now.AddMinutes(minutes.Value));
        Changed?.Invoke();
    }
    public void Busy(int? minutes)
    {
        Pending.Clear();
        Planned = null;
        Active = null;
        Engine.OnBreak = false;
        Prewarning = null;
        Engine.SetBusy(minutes, Now);
        Changed?.Invoke();
    }
    public void Sleep(bool sleeping, DateTimeOffset now)
    {
        Now = now;
        if (sleeping)
            Dismiss(null, true, false);
        Engine.SetSleeping(sleeping, now);
        Prewarning = null;
        Changed?.Invoke();
    }
    public void Edit(Preferences preferences)
    {
        Engine.UpdatePreferences(preferences, Now);
        Prewarning = null;
        if (Planned != null && Active == null && !Prefs.PlannedBreaks.Any(p => p.Enabled && p.Id == Planned.RuleId && p.Signature == Planned.RuleSignature))
            Remove(Planned.Kind);
        Pending.RemoveAll(k => !Prefs[k].Enabled && Active?.Kind != k && Planned?.Kind != k);
        Changed?.Invoke();
    }
    public void CycleCard()
    {
        Card = (Card + 1) % 3;
        cardChanged = Now;
        Changed?.Invoke();
    }
}
