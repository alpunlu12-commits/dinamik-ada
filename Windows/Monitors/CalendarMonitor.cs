using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows.Threading;
using DinamikAda.Island;
using Ical.Net;
using Ical.Net.CalendarComponents;

namespace DinamikAda.Monitors;

/// <summary>
/// Sıradaki etkinlik, bir iCal (ICS) bağlantısından.
///
/// Windows Takvimi paketlenmemiş masaüstü uygulamalarına kapalı; Google ve
/// Outlook ise her takvim için gizli bir iCal adresi veriyor. Takvim beş
/// dakikada bir indirilir, sıradaki etkinlik 30 sn'de bir yeniden hesaplanır
/// (macOS sürümündeki EventKit yenileme aralığı). Tekrarlayan etkinlikler
/// Ical.Net ile açılır; tüm gün etkinlikleri elenir — randevu değil bağlam.
/// </summary>
public sealed class CalendarMonitor
{
    public Action<UpcomingEvent?>? OnChange { get; set; }
    /// <summary>(durum, hata metni)</summary>
    public Action<CalendarStatus, string>? OnStatusChange { get; set; }
    /// <summary>Etkinliğe 5 dakika kala bir kez.</summary>
    public Action<UpcomingEvent>? OnImminent { get; set; }

    private const int ImminentMinutes = 5;
    private static readonly TimeSpan Horizon = TimeSpan.FromHours(12);
    private static readonly TimeSpan FetchInterval = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan RecomputeInterval = TimeSpan.FromSeconds(30);
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    private string _url = "";
    private Calendar? _calendar;
    private UpcomingEvent? _next;
    private readonly HashSet<string> _announced = new();
    private DispatcherTimer? _fetchTimer, _recomputeTimer;
    private int _generation;

    public void Start(string url)
    {
        var normalized = Normalize(url);
        if (_fetchTimer != null && normalized == _url) return;
        Stop();
        _url = normalized;
        if (_url.Length == 0)
        {
            OnStatusChange?.Invoke(CalendarStatus.NoLink, "");
            return;
        }
        _fetchTimer = new DispatcherTimer { Interval = FetchInterval };
        _fetchTimer.Tick += (_, _) => _ = Fetch();
        _fetchTimer.Start();
        _recomputeTimer = new DispatcherTimer { Interval = RecomputeInterval };
        _recomputeTimer.Tick += (_, _) => Recompute();
        _recomputeTimer.Start();
        _ = Fetch();
    }

    public void Stop()
    {
        _generation++;
        _fetchTimer?.Stop();
        _recomputeTimer?.Stop();
        _fetchTimer = _recomputeTimer = null;
        _calendar = null;
        _url = "";
        _announced.Clear();
        Deliver(null);
    }

    /// <summary>webcal:// bağlantıları https olarak indirilir.</summary>
    public static string Normalize(string url)
    {
        var u = url.Trim();
        if (u.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) u = "https://" + u["webcal://".Length..];
        return u;
    }

    private async Task Fetch()
    {
        var generation = _generation;
        var url = _url;
        try
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || (uri.Scheme != "https" && uri.Scheme != "http"))
                throw new InvalidOperationException("geçersiz adres");
            var text = await Http.GetStringAsync(uri);
            var calendar = await Task.Run(() => Calendar.Load(text));
            if (generation != _generation) return;
            _calendar = calendar;
            OnStatusChange?.Invoke(CalendarStatus.Connected, "");
            Recompute();
        }
        catch (Exception e)
        {
            if (generation != _generation) return;
            OnStatusChange?.Invoke(CalendarStatus.Failed, e is HttpRequestException h && h.StatusCode is { } code ? $"HTTP {(int)code}" : e.Message);
        }
    }

    private bool _computing;

    /// <summary>
    /// Tekrarlayan etkinlikleri açmak büyük takvimlerde zaman alabilir; arayüz
    /// iş parçacığını bekletmesin. Aynı anda tek hesap.
    /// </summary>
    private async void Recompute()
    {
        if (_calendar is not { } calendar || _computing) return;
        _computing = true;
        var generation = _generation;
        try
        {
            var next = await Task.Run(() => Next(calendar, DateTime.UtcNow));
            if (generation == _generation) Deliver(next);
        }
        finally
        {
            _computing = false;
        }
    }

    /// <summary>Şu andan itibaren 12 saat içinde başlayan ilk (tüm gün olmayan) etkinlik.</summary>
    public static UpcomingEvent? Next(Calendar calendar, DateTime nowUtc)
    {
        try
        {
            var occurrences = calendar.GetOccurrences(nowUtc.AddMinutes(-1), nowUtc + Horizon);
            return occurrences
                .Where(o => o.Source is CalendarEvent e && !e.IsAllDay)
                .Select(o => (Occurrence: o, Start: o.Period.StartTime.AsUtc))
                .Where(x => x.Start > nowUtc.AddMinutes(-1))
                .OrderBy(x => x.Start)
                .Select(x =>
                {
                    var e = (CalendarEvent)x.Occurrence.Source;
                    var title = string.IsNullOrWhiteSpace(e.Summary) ? "Event" : e.Summary.Trim();
                    var location = string.IsNullOrWhiteSpace(e.Location) ? null : e.Location.Trim();
                    return new UpcomingEvent($"{e.Uid}|{x.Start:o}", title, x.Start, location);
                })
                .FirstOrDefault();
        }
        catch
        {
            return null;
        }
    }

    private void Deliver(UpcomingEvent? ev)
    {
        if (!Equals(ev, _next))
        {
            _next = ev;
            OnChange?.Invoke(ev);
        }
        if (ev == null || ev.MinutesUntil > ImminentMinutes || ev.MinutesUntil < -1 || !_announced.Add(ev.Identifier)) return;
        OnImminent?.Invoke(ev);
    }
}
