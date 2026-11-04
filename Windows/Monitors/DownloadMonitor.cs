using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using DinamikAda.Island;

namespace DinamikAda.Monitors;

/// <summary>
/// İndirilenler klasörünün canlı etkinliği. Her tarayıcı önce kısmi bir dosya
/// yazar ve bitince yerine taşır; bu dosyaların varlığı "iniyor", kaybolup
/// yerine tam dosyanın gelmesi "bitti" demek. Yüzde gösterilmez: hiçbir
/// tarayıcı beklenen boyutu başka bir uygulamanın okuyabileceği yerde yayınlamaz.
///
/// Kısmi dosya yalnızca **büyüdüğü sürece** sayılır: tarayıcılar iptal edilmiş
/// indirmelerin dosyasını geride bırakır; unutulmuş bir dosya adada kalıcı
/// gösterge bırakmasın. Duraklamış dosya varken yoklama 0,6 sn'den 5 sn'ye düşer.
/// </summary>
public sealed class DownloadMonitor
{
    public Action<DownloadActivity?>? OnChange { get; set; }
    public Action<DownloadActivity>? OnComplete { get; set; }
    public DownloadActivity? Activity { get; private set; }

    private static readonly HashSet<string> PartialExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".crdownload",  // Chrome, Edge, Brave, Vivaldi
        ".part",        // Firefox
        ".partial",     // eski Edge
        ".opdownload",  // Opera
        ".download",
    };

    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(0.6);
    private static readonly TimeSpan StalledPollInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan StallTimeout = TimeSpan.FromSeconds(6);

    private readonly string _folder;
    private FileSystemWatcher? _watcher;
    private readonly DispatcherTimer _debounce = new() { Interval = TimeSpan.FromMilliseconds(150) };
    private DispatcherTimer? _poll;
    private TimeSpan? _pollInterval;
    private Dictionary<string, long> _partials = new();
    private Dictionary<string, DateTime> _lastGrowth = new();
    private HashSet<string> _completed = new();

    public DownloadMonitor(string? folder = null)
    {
        _folder = folder ?? DownloadsFolder();
        _debounce.Tick += (_, _) => { _debounce.Stop(); Scan(); };
    }

    public void Start()
    {
        if (_watcher != null || !Directory.Exists(_folder)) return;
        try
        {
            _watcher = new FileSystemWatcher(_folder) { IncludeSubdirectories = false, NotifyFilter = NotifyFilters.FileName | NotifyFilters.Size | NotifyFilters.LastWrite | NotifyFilters.DirectoryName };
            FileSystemEventHandler h = (_, _) => Kick();
            _watcher.Created += h;
            _watcher.Changed += h;
            _watcher.Deleted += h;
            _watcher.Renamed += (_, _) => Kick();
            _watcher.EnableRaisingEvents = true;
        }
        catch
        {
            _watcher = null;
            return;
        }
        Seed();
    }

    public void Stop()
    {
        _watcher?.Dispose();
        _watcher = null;
        _debounce.Stop();
        _poll?.Stop();
        _poll = null;
        _pollInterval = null;
        _partials.Clear();
        _lastGrowth.Clear();
        _completed.Clear();
        Publish(null);
    }

    private void Kick() => Application.Current?.Dispatcher.BeginInvoke(() =>
    {
        if (_watcher == null) return;
        _debounce.Stop();
        _debounce.Start();
    });

    /// <summary>
    /// Açılışta klasörde zaten duran kısmi dosyalar duraklamış başlar: onları bu
    /// oturum başlatmadı ve hareket ettiklerine dair bir kanıt yok.
    /// </summary>
    private void Seed()
    {
        var (partial, complete) = Contents();
        _partials = partial;
        _completed = complete;
        _lastGrowth = partial.ToDictionary(p => p.Key, _ => DateTime.MinValue);
        UpdatePolling();
    }

    private void Scan()
    {
        var (partial, complete) = Contents();
        var finished = _partials.Keys.Where(k => !partial.ContainsKey(k)).Select(CompletedName);
        foreach (var name in finished)
        {
            if (!complete.Contains(name) || _completed.Contains(name)) continue;
            OnComplete?.Invoke(new DownloadActivity(name, Size(Path.Combine(_folder, name)), true));
        }
        NoteGrowth(partial);
        _partials = partial;
        _completed = complete;
        UpdatePolling();
        PublishCurrent();
    }

    private void NoteGrowth(Dictionary<string, long> fresh)
    {
        var now = DateTime.UtcNow;
        foreach (var (name, size) in fresh)
        {
            if (!_partials.TryGetValue(name, out var previous)) { _lastGrowth[name] = now; continue; }
            if (size > previous) _lastGrowth[name] = now;
        }
        _lastGrowth = _lastGrowth.Where(kv => fresh.ContainsKey(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value);
    }

    private Dictionary<string, long> ActivePartials
    {
        get
        {
            var cutoff = DateTime.UtcNow - StallTimeout;
            return _partials.Where(p => _lastGrowth.TryGetValue(p.Key, out var t) && t > cutoff)
                            .ToDictionary(p => p.Key, p => p.Value);
        }
    }

    private void UpdatePolling()
    {
        TimeSpan? wanted = _partials.Count == 0 ? null : ActivePartials.Count == 0 ? StalledPollInterval : PollInterval;
        if (wanted == _pollInterval) return;
        _pollInterval = wanted;
        _poll?.Stop();
        _poll = null;
        if (wanted is not { } interval) return;
        _poll = new DispatcherTimer { Interval = interval };
        _poll.Tick += (_, _) =>
        {
            var fresh = Contents().Partial;
            NoteGrowth(fresh);
            _partials = fresh;
            UpdatePolling();
            PublishCurrent();
        };
        _poll.Start();
    }

    private void PublishCurrent()
    {
        var active = ActivePartials;
        if (active.Count == 0) { Publish(null); return; }
        var biggest = active.MaxBy(p => p.Value);
        Publish(new DownloadActivity(CompletedName(biggest.Key), biggest.Value, false, Math.Max(0, active.Count - 1)));
    }

    private void Publish(DownloadActivity? next)
    {
        if (Equals(next, Activity)) return;
        Activity = next;
        OnChange?.Invoke(next);
    }

    /// <summary>
    /// Kısmi ve tamamlanmış dosyalar. Boş dosyalar "tamamlanmış" sayılmaz:
    /// Firefox indirmenin başında son adla boş bir yer tutucu açar; onu sayarsak
    /// indirme bittiğinde "zaten vardı" sanıp haber vermezdik.
    /// </summary>
    private (Dictionary<string, long> Partial, HashSet<string> Complete) Contents()
    {
        var partial = new Dictionary<string, long>();
        var complete = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var entry in new DirectoryInfo(_folder).EnumerateFileSystemInfos())
            {
                if ((entry.Attributes & FileAttributes.Hidden) != 0) continue;
                if (PartialExtensions.Contains(entry.Extension)) partial[entry.Name] = Size(entry.FullName);
                else if (entry is DirectoryInfo || (entry is FileInfo f && f.Length > 0)) complete.Add(entry.Name);
            }
        }
        catch { }
        return (partial, complete);
    }

    private static long Size(string path)
    {
        try
        {
            if (Directory.Exists(path))
                return new DirectoryInfo(path).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
            return File.Exists(path) ? new FileInfo(path).Length : 0;
        }
        catch
        {
            return 0;
        }
    }

    private static string CompletedName(string partialName) =>
        PartialExtensions.Contains(Path.GetExtension(partialName)) ? Path.GetFileNameWithoutExtension(partialName) : partialName;

    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);

    /// <summary>Kullanıcının taşımış olabileceği gerçek İndirilenler klasörü.</summary>
    public static string DownloadsFolder()
    {
        try
        {
            if (SHGetKnownFolderPath(new Guid("374DE290-123F-4565-9164-39C4925E467B"), 0, IntPtr.Zero, out var ptr) == 0)
            {
                var path = Marshal.PtrToStringUni(ptr);
                Marshal.FreeCoTaskMem(ptr);
                if (!string.IsNullOrEmpty(path)) return path;
            }
        }
        catch { }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    }
}
