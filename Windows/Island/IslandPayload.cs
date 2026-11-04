using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DinamikAda.Core;
using DinamikAda.UI;

namespace DinamikAda.Island;

/// <summary>
/// Sistemde çalan (ya da duraklatılmış) bir parça. Windows'ta kaynak, medya
/// oturumunun uygulama kimliğidir (Spotify.exe, chrome, bir AUMID…).
/// </summary>
public sealed record NowPlaying
{
    public required string SourceAppId { get; init; }
    public required string SourceName { get; init; }
    public required string Title { get; init; }
    public string Artist { get; init; } = "";
    public bool IsPlaying { get; init; }
    public BitmapSource? Artwork { get; init; }
    public ArtworkPalette Palette { get; init; } = ArtworkPalette.None;

    /// <summary>Parça uzunluğu, oynatıcı yayınlıyorsa.</summary>
    public double? Duration { get; init; }

    /// <summary>
    /// <see cref="ElapsedSampledAt"/> anındaki konum. Saatten ileri sarılarak
    /// okunur: medya oturumu bir konum ve zaman damgası verir, tıkırdayan saat değil.
    /// </summary>
    public double? Elapsed { get; init; }
    public DateTime? ElapsedSampledAt { get; init; }
    public double? PlaybackRate { get; init; }

    public string TrackKey => $"{SourceAppId}|{Title}|{Artist}";

    /// <summary>Oynatma kafasının şu anki yeri.</summary>
    public double? ElapsedNow
    {
        get
        {
            if (Elapsed is not { } e) return null;
            if (!IsPlaying || ElapsedSampledAt is not { } at) return e;
            var projected = e + (DateTime.UtcNow - at).TotalSeconds * (PlaybackRate ?? 1);
            return Duration is { } d ? Math.Min(Math.Max(0, projected), d) : Math.Max(0, projected);
        }
    }

    /// <summary>0…1; süre bilinmiyorsa null — boş bir çubuk bilgi yokluğunu bilgi gibi gösterirdi.</summary>
    public double? Progress => Duration is { } d && d > 0 && ElapsedNow is { } e ? (e / d).Unit() : null;

    public bool HasProgress => Duration != null && Elapsed != null;

    /// <summary>Yeniden çizim gerekip gerekmediğine bakarken resim nesnesini değil kimliği karşılaştır.</summary>
    public bool SameContent(NowPlaying? other) =>
        other != null && other.TrackKey == TrackKey && other.IsPlaying == IsPlaying
        && ReferenceEquals(other.Artwork, Artwork) && other.Duration == Duration
        && other.Elapsed == Elapsed && other.PlaybackRate == PlaybackRate;
}

/// <summary>Kompakt pilde ortadaki şeridin iki yanındaki yuvalar.</summary>
public abstract record CompactAccessory
{
    public virtual double Width => 34;

    public sealed record Artwork(BitmapSource? Image) : CompactAccessory;
    public sealed record Waveform(bool Playing, ArtworkPalette Palette) : CompactAccessory;
    public sealed record Countdown(string Text) : CompactAccessory { public override double Width => 48; }
    public sealed record TimerGlyph : CompactAccessory;
    public sealed record Privacy(bool Camera, bool Microphone) : CompactAccessory
    {
        public override double Width => Camera && Microphone ? 40 : 28;
    }
    public sealed record Shelf(int Count) : CompactAccessory;
    public sealed record Download : CompactAccessory;
}

public sealed record CompactAccessories(CompactAccessory? Leading, CompactAccessory? Trailing)
{
    public static readonly CompactAccessories None = new(null, null);
    public double TotalWidth => (Leading?.Width ?? 0) + (Trailing?.Width ?? 0);
    public bool IsEmpty => Leading == null && Trailing == null;
}

/// <summary>Adanın kendi geri sayımı.</summary>
public sealed record CountdownState(double Duration, double Remaining, bool IsRunning)
{
    public bool IsFinished => Remaining <= 0;

    /// <summary>0…1 geçen.</summary>
    public double Progress => Duration > 0 ? ((Duration - Remaining) / Duration).Unit() : 0;

    /// <summary>"4:32", bir saat olunca "1:04:32".</summary>
    public string Text
    {
        get
        {
            var total = (int)Math.Ceiling(Remaining);
            int h = total / 3600, m = total % 3600 / 60, s = total % 60;
            return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m}:{s:00}";
        }
    }
}

public abstract record TimerAction
{
    public sealed record Start(int Minutes) : TimerAction;
    public sealed record Toggle : TimerAction;
    public sealed record Restart : TimerAction;
    public sealed record Cancel : TimerAction;
}

/// <summary>Kontrol Merkezi'nin SİSTEM satırındaki kutucuk.</summary>
public enum SystemTile { Volume, Brightness, Battery, Bluetooth }

public static class SystemTileExtensions
{
    /// <summary>Ses ve parlaklık denetimdir; geri kalanlar gösterge.</summary>
    public static bool IsAdjustable(this SystemTile t) => t is SystemTile.Volume or SystemTile.Brightness;
}

public abstract record ShelfAction
{
    public sealed record Open(int Index) : ShelfAction;
    public sealed record Remove(int Index) : ShelfAction;
    /// <summary>Ctrl- ya da Shift-tıklama: açmak yerine seçime ekle/çıkar.</summary>
    public sealed record ToggleSelection(int Index) : ShelfAction;
    public sealed record CopyAll : ShelfAction;
    public sealed record ShareAll : ShelfAction;
    public sealed record Clear : ShelfAction;
}

public enum TransportKind { PlayPause, Next, Previous }

/// <summary>Ada üzerinde imlecin etkileyebileceği her şey.</summary>
public abstract record IslandControl
{
    public sealed record Transport(TransportKind Kind) : IslandControl;
    /// <summary>Albüm kapağı: basınca parçanın geldiği uygulama öne gelir.</summary>
    public sealed record Artwork : IslandControl;
    /// <summary>İlerleme çubuğu: basılıp sürüklenir.</summary>
    public sealed record Seek : IslandControl;
    public sealed record Tile(SystemTile Kind) : IslandControl;
    public sealed record Timer(TimerAction Action) : IslandControl;
    public sealed record Shelf(ShelfAction Action) : IslandControl;
}

/// <summary>Genişlemiş adanın gösterdiği şey — ne kadar genişleyeceğine bu karar verir.</summary>
public abstract record ExpandedPayloadKind
{
    public sealed record Meter : ExpandedPayloadKind;
    public sealed record Wide : ExpandedPayloadKind;
    public sealed record NowPlayingKind : ExpandedPayloadKind;
    public sealed record CountdownKind : ExpandedPayloadKind;
    public sealed record QuickStats(int Chips) : ExpandedPayloadKind;

    /// <summary>
    /// Bilerek dar: ada baktığın şeyin *üstüne* açılıyor, yanlara aldığı her nokta
    /// başka bir pencerenin kapanan noktası. Uzun parça adı marquee ile kayar.
    /// </summary>
    public double Width => this switch
    {
        Meter => 300,
        Wide => 360,
        NowPlayingKind => 360,
        CountdownKind => 288,
        QuickStats q => q.Chips == 0 ? 200 : 34 + q.Chips * 74 + (q.Chips - 1) * 8,
        _ => 360,
    };

    public double InnerHeight => 56;

    public const double MaxWidth = 360;
    public const double MaxInnerHeight = 56;
}

/// <summary>Kontrol Merkezi'nin hangi isteğe bağlı bölümleri gösterdiği.</summary>
public sealed record ControlCenterSections(bool Calendar, bool Timer, bool Shelf, bool MediaProgress = false)
{
    public static readonly ControlCenterSections None = new(false, false, false);
}

/// <summary>Güç durumunun neden gösterildiği.</summary>
public abstract record PowerEvent
{
    public sealed record PluggedIn : PowerEvent;
    public sealed record Unplugged : PowerEvent;
    public sealed record FullyCharged : PowerEvent;
    public sealed record LowBattery(int Threshold) : PowerEvent;

    /// <summary>Uyarılar turuncu çizilir ve biraz daha uzun tutulur.</summary>
    public bool IsWarning => this is LowBattery;
}

public sealed record PowerSnapshot(int Percentage, bool IsCharging, bool IsPluggedIn, int? MinutesRemaining);

/// <summary>
/// Bir Bluetooth ses cihazı ve bildirdiği pil. Windows tek bir değer verir;
/// AirPods'un sol/sağ/kutu ayrımı yalnızca macOS'ta okunabiliyor.
/// </summary>
public sealed record BluetoothDevice(string Name, int? Left = null, int? Right = null, int? Case = null, int? Single = null)
{
    /// <summary>Tek bir sayıya yer varken gösterilecek değer.</summary>
    public int? Headline => Single ?? (Left is null ? Right : Right is null ? Left : Math.Min(Left.Value, Right.Value));
    public bool HasBattery => Headline != null || Case != null;
}

public sealed record PrivacyState(bool CameraActive, bool MicrophoneActive)
{
    public bool IsActive => CameraActive || MicrophoneActive;
    public static readonly PrivacyState Idle = new(false, false);
}

public sealed record DownloadActivity(string FileName, long Bytes, bool IsComplete, int OtherCount = 0);

public sealed record UpcomingEvent(string Identifier, string Title, DateTime StartUtc, string? Location)
{
    /// <summary>Kalan dakika aşağı yuvarlanır: yukarı yuvarlansa son yarım dakika "1 dk sonra" derdi.</summary>
    public int MinutesUntil => (int)Math.Floor((StartUtc - DateTime.UtcNow).TotalMinutes);

    public string RelativeText
    {
        get
        {
            var minutes = MinutesUntil;
            if (minutes <= 0) return Strings.JustNow;
            if (minutes < 60) return Strings.InMinutes(minutes);
            var hours = minutes / 60.0;
            var text = hours < 2 ? hours.ToString("0.0", Localization.Culture) : ((int)Math.Round(hours, MidpointRounding.AwayFromZero)).ToString();
            return Strings.InHours(text);
        }
    }

    public string TimeText => StartUtc.ToLocalTime().ToString("t", Localization.Culture);
}

/// <summary>Adayı kısa süre devralan içerik.</summary>
public abstract record TransientKind
{
    public sealed record Volume(double Level, bool Muted) : TransientKind;
    public sealed record Brightness(double Level) : TransientKind;
    public sealed record Power(PowerSnapshot Snapshot, PowerEvent Event) : TransientKind;
    public sealed record Device(BluetoothDevice Info) : TransientKind;
    public sealed record TimerFinished(double Duration) : TransientKind;
    public sealed record Upcoming(UpcomingEvent Info) : TransientKind;
    public sealed record Download(DownloadActivity Activity) : TransientKind;

    /// <summary>Ada bunu ne kadar tutar.</summary>
    public double Dwell => this switch
    {
        Power p => p.Event.IsWarning ? 3.4 : 2.2,
        Upcoming => 3.0,
        Download d => d.Activity.IsComplete ? 3.4 : 2.6,
        _ => 1.7,
    };
}

/// <summary>Raftaki bir dosya.</summary>
public sealed record ShelfItem(string Path)
{
    public string Id => Path;
    public string Name => System.IO.Path.GetFileName(Path);
}
