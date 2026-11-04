using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
using DinamikAda.Island;
using DinamikAda.UI;
using Windows.Media.Control;

namespace DinamikAda.Monitors;

/// <summary>
/// Sistem geneli Now Playing: Windows'un medya oturumları (GSMTC) — ses
/// göstergesindeki medya kartının kaynağı. Spotify, tarayıcılar, Medya Oynatıcı
/// ve Windows'a kaydolan her şey; kapak, zaman çizelgesi ve düğmeler dahil.
/// İzin gerekmez. macOS'taki MediaRemote köprüsünün ve AppleScript yedeğinin
/// yerine geçer.
/// </summary>
public sealed class NowPlayingMonitor
{
    public Action<NowPlaying?>? OnChange { get; set; }
    /// <summary>Medya oturumlarına erişilebildi mi (Ayarlar'da gösterilir).</summary>
    public Action<bool>? OnAvailabilityChange { get; set; }

    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private bool _running;
    private bool _refreshing;
    private bool _refreshAgain;

    // Kapak parça başına bir kez okunur.
    private string? _artworkKey;
    private BitmapSource? _artwork;
    private ArtworkPalette _palette = ArtworkPalette.None;

    public async void Start()
    {
        if (_running) return;
        _running = true;
        try
        {
            var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            if (!_running) return;
            _manager = manager;
            _manager.CurrentSessionChanged += OnSessionsChanged;
            _manager.SessionsChanged += OnSessionsChanged;
            OnAvailabilityChange?.Invoke(true);
            AttachSession();
            await Refresh();
        }
        catch (Exception e)
        {
            Debug.WriteLine("DinamikAda: medya oturumları alınamadı — " + e.Message);
            OnAvailabilityChange?.Invoke(false);
        }
    }

    public void Stop()
    {
        if (!_running) return;
        _running = false;
        DetachSession();
        if (_manager != null)
        {
            _manager.CurrentSessionChanged -= OnSessionsChanged;
            _manager.SessionsChanged -= OnSessionsChanged;
            _manager = null;
        }
        _artworkKey = null;
        _artwork = null;
        OnChange?.Invoke(null);
    }

    private void OnSessionsChanged(GlobalSystemMediaTransportControlsSessionManager sender, object args) =>
        Dispatch(() => { AttachSession(); _ = Refresh(); });

    private void AttachSession()
    {
        var current = _manager?.GetCurrentSession();
        if (ReferenceEquals(current, _session)) return;
        DetachSession();
        _session = current;
        if (_session == null) return;
        _session.MediaPropertiesChanged += OnSessionEvent;
        _session.PlaybackInfoChanged += OnSessionEvent;
        _session.TimelinePropertiesChanged += OnSessionEvent;
    }

    private void DetachSession()
    {
        if (_session == null) return;
        _session.MediaPropertiesChanged -= OnSessionEvent;
        _session.PlaybackInfoChanged -= OnSessionEvent;
        _session.TimelinePropertiesChanged -= OnSessionEvent;
        _session = null;
    }

    private void OnSessionEvent(GlobalSystemMediaTransportControlsSession sender, object args) =>
        Dispatch(() => _ = Refresh());

    private static void Dispatch(Action action) => Application.Current?.Dispatcher.BeginInvoke(action);

    /// <summary>Üst üste gelen olayları tek okumaya indirger.</summary>
    private async Task Refresh()
    {
        if (_refreshing) { _refreshAgain = true; return; }
        _refreshing = true;
        try
        {
            do
            {
                _refreshAgain = false;
                OnChange?.Invoke(await Read());
            } while (_refreshAgain && _running);
        }
        finally
        {
            _refreshing = false;
        }
    }

    private async Task<NowPlaying?> Read()
    {
        var session = _session;
        if (!_running || session == null) return null;
        try
        {
            var props = await session.TryGetMediaPropertiesAsync();
            if (props == null || string.IsNullOrWhiteSpace(props.Title)) return null;
            var playback = session.GetPlaybackInfo();
            var timeline = session.GetTimelineProperties();
            var appId = session.SourceAppUserModelId ?? "";

            var key = $"{appId}|{props.Title}|{props.Artist}";
            if (key != _artworkKey)
            {
                _artworkKey = key;
                _artwork = await LoadArtwork(props.Thumbnail);
                _palette = ArtworkPaletteExtractor.Extract(_artwork);
            }

            double? duration = null, elapsed = null;
            DateTime? sampledAt = null;
            var length = (timeline.EndTime - timeline.StartTime).TotalSeconds;
            if (length > 0)
            {
                duration = length;
                elapsed = Math.Max(0, (timeline.Position - timeline.StartTime).TotalSeconds);
                sampledAt = timeline.LastUpdatedTime.Year > 2000 ? timeline.LastUpdatedTime.UtcDateTime : DateTime.UtcNow;
            }

            return new NowPlaying
            {
                SourceAppId = appId,
                SourceName = DisplayName(appId),
                Title = props.Title,
                Artist = props.Artist ?? "",
                IsPlaying = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                Artwork = _artwork,
                Palette = _palette,
                Duration = duration,
                Elapsed = elapsed,
                ElapsedSampledAt = sampledAt,
                PlaybackRate = playback.PlaybackRate,
            };
        }
        catch
        {
            return null;
        }
    }

    private static async Task<BitmapSource?> LoadArtwork(Windows.Storage.Streams.IRandomAccessStreamReference? reference)
    {
        if (reference == null) return null;
        try
        {
            using var stream = await reference.OpenReadAsync();
            using var managed = stream.AsStreamForRead();
            var ms = new MemoryStream();
            await managed.CopyToAsync(ms);
            ms.Position = 0;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 160;
            image.StreamSource = ms;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    // MARK: Komutlar

    public async void Send(TransportKind kind)
    {
        var s = _session;
        if (s == null) return;
        try
        {
            _ = kind switch
            {
                TransportKind.PlayPause => await s.TryTogglePlayPauseAsync(),
                TransportKind.Next => await s.TrySkipNextAsync(),
                _ => await s.TrySkipPreviousAsync(),
            };
        }
        catch { }
    }

    /// <summary>Parçanın bir oranına atla (sürgü).</summary>
    public async void Seek(double fraction)
    {
        var s = _session;
        if (s == null) return;
        try
        {
            var t = s.GetTimelineProperties();
            var target = t.StartTime + TimeSpan.FromTicks((long)((t.EndTime - t.StartTime).Ticks * Math.Clamp(fraction, 0, 1)));
            await s.TryChangePlaybackPositionAsync(target.Ticks);
        }
        catch { }
    }

    /// <summary>Parçanın geldiği uygulamayı öne getir.</summary>
    public static void OpenApp(string appId)
    {
        if (string.IsNullOrEmpty(appId)) return;
        try
        {
            if (appId.Contains('!'))
            {
                // Mağaza / paketli uygulama: kimliği ile başlatmak var olan pencereyi öne getirir.
                Process.Start(new ProcessStartInfo("explorer.exe", $"shell:AppsFolder\\{appId}") { UseShellExecute = true });
                return;
            }
            var name = Path.GetFileNameWithoutExtension(appId);
            var process = Process.GetProcessesByName(name).FirstOrDefault(p => p.MainWindowHandle != IntPtr.Zero);
            if (process == null) return;
            var hwnd = process.MainWindowHandle;
            if (Native.IsIconic(hwnd)) Native.ShowWindow(hwnd, Native.SW_RESTORE);
            Native.SetForegroundWindow(hwnd);
        }
        catch { }
    }

    /// <summary>"Spotify.exe" → "Spotify", "MSEdge" → "Microsoft Edge"…</summary>
    public static string DisplayName(string appId)
    {
        var id = appId.ToLowerInvariant();
        if (id.Contains("spotify")) return "Spotify";
        if (id.Contains("msedge")) return "Microsoft Edge";
        if (id.Contains("chrome")) return "Google Chrome";
        if (id.Contains("firefox") || id.Contains("308046b0af4a39cb")) return "Firefox";
        if (id.Contains("opera")) return "Opera";
        if (id.Contains("brave")) return "Brave";
        if (id.Contains("vivaldi")) return "Vivaldi";
        if (id.Contains("vlc")) return "VLC";
        if (id.Contains("zunemusic")) return Core.Localization.Language == Core.AppLanguage.Turkish ? "Medya Oynatıcı" : "Media Player";
        if (id.Contains("zunevideo")) return Core.Localization.Language == Core.AppLanguage.Turkish ? "Filmler ve TV" : "Films & TV";
        var raw = appId.Contains('!') ? appId[(appId.IndexOf('!') + 1)..] : appId;
        raw = Path.GetFileNameWithoutExtension(raw);
        var dot = raw.LastIndexOf('.');
        if (dot >= 0 && dot < raw.Length - 1) raw = raw[(dot + 1)..];
        return raw.Length == 0 ? appId : char.ToUpperInvariant(raw[0]) + raw[1..];
    }
}
