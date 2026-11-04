using System;
using System.Windows.Threading;

namespace DinamikAda.Island;

/// <summary>
/// Adanın geri sayımı. Kalan süre saatten türetilir, tıklarla azaltılmaz:
/// tekrarlayan bir zamanlayıcı kayar ve uyku sırasında beklendiği gibi
/// tetiklenmez; saati okumak her zaman doğru sonucu verir.
/// </summary>
public sealed class IslandTimer
{
    public Action<CountdownState?>? OnChange { get; set; }
    public Action<double>? OnFinished { get; set; }

    private CountdownState? _state;
    public CountdownState? State
    {
        get => _state;
        private set
        {
            if (Equals(_state, value)) return;
            _state = value;
            OnChange?.Invoke(value);
        }
    }

    private DateTime? _deadline;
    private DispatcherTimer? _ticker;

    public void Start(int minutes)
    {
        var duration = minutes * 60.0;
        _deadline = DateTime.UtcNow.AddSeconds(duration);
        State = new CountdownState(duration, duration, true);
        StartTicking();
    }

    public void Toggle()
    {
        if (State is not { } current) return;
        if (current.IsRunning)
        {
            var remaining = RemainingFromDeadline() ?? current.Remaining;
            _deadline = null;
            StopTicking();
            State = current with { Remaining = remaining, IsRunning = false };
        }
        else
        {
            _deadline = DateTime.UtcNow.AddSeconds(current.Remaining);
            State = current with { IsRunning = true };
            StartTicking();
        }
    }

    public void Restart()
    {
        if (State is not { } current) return;
        Start((int)Math.Round(current.Duration / 60, MidpointRounding.AwayFromZero));
    }

    public void Cancel()
    {
        StopTicking();
        _deadline = null;
        State = null;
    }

    private void StartTicking()
    {
        StopTicking();
        _ticker = new DispatcherTimer { Interval = TimeSpan.FromSeconds(0.2) };
        _ticker.Tick += (_, _) => Tick();
        _ticker.Start();
    }

    private void StopTicking()
    {
        _ticker?.Stop();
        _ticker = null;
    }

    private void Tick()
    {
        if (State is not { IsRunning: true } current || RemainingFromDeadline() is not { } remaining) return;
        if (remaining <= 0)
        {
            StopTicking();
            _deadline = null;
            State = current with { Remaining = 0, IsRunning = false };
            OnFinished?.Invoke(current.Duration);
            return;
        }
        State = current with { Remaining = remaining };
    }

    private double? RemainingFromDeadline() =>
        _deadline is { } d ? Math.Max(0, (d - DateTime.UtcNow).TotalSeconds) : null;
}
