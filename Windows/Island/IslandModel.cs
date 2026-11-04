using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Threading;
using DinamikAda.Core;

namespace DinamikAda.Island;

/// <summary>Üç ada boyutu (+ bırakma alanı), karşılaştırılabilsin diye sıralı.</summary>
public enum IslandState { Compact = 0, Expanded = 1, ControlCenter = 2, DropZone = 3 }

/// <summary>Takvim modülünün durumu.</summary>
public enum CalendarStatus { NoLink, Connected, Failed }

/// <summary>
/// Geçici etkileşim durumu ve adadaki içerik. macOS sürümündeki IslandModel'in
/// birebir karşılığı.
///
/// Adanın görünüşüne iki girdi karar verir:
///  • <see cref="State"/> — imleçten: üzerine gelmek genişletir, tıklamak Kontrol Merkezi'ni açar.
///  • <see cref="Transient"/> — sistemden: ses, parlaklık, güç değişimi adayı kısa süre devralır.
/// <see cref="RenderedState"/> ikisini tek cevaba indirir. Kontrol Merkezi her şeyin
/// üstündedir: kullanıcı onu bilerek açtıysa bir ses tuşu onu elinden almamalı.
/// Burada geometri yok — denetleyici olayları besler, görünüm sonucu okur.
/// </summary>
public sealed class IslandModel : ObservableObject
{
    private IslandState _state = IslandState.Compact;
    public IslandState State { get => _state; private set => Set(ref _state, value); }

    private bool _isHovering;
    public bool IsHovering { get => _isHovering; private set => Set(ref _isHovering, value); }

    /// <summary>Menüden bir "Demo:" eylemiyle açık tutuluyor mu.</summary>
    private bool _isPinned;
    public bool IsPinned { get => _isPinned; private set => Set(ref _isPinned, value); }

    private NowPlaying? _nowPlaying;
    public NowPlaying? NowPlaying { get => _nowPlaying; private set => Set(ref _nowPlaying, value); }

    private TransientKind? _transient;
    public TransientKind? Transient { get => _transient; private set => Set(ref _transient, value); }

    private PowerSnapshot? _power;
    public PowerSnapshot? Power { get => _power; set => Set(ref _power, value); }

    private double? _brightness;
    public double? Brightness { get => _brightness; set => Set(ref _brightness, value); }

    private double? _volume;
    public double? Volume { get => _volume; set => Set(ref _volume, value); }

    private CountdownState? _countdown;
    public CountdownState? Countdown { get => _countdown; set => Set(ref _countdown, value); }

    private IReadOnlyList<BluetoothDevice> _devices = Array.Empty<BluetoothDevice>();
    public IReadOnlyList<BluetoothDevice> Devices
    {
        get => _devices;
        set { if (!_devices.SequenceEqual(value)) { _devices = value; OnPropertyChanged(); } }
    }

    private PrivacyState _privacy = PrivacyState.Idle;
    public PrivacyState Privacy { get => _privacy; set => Set(ref _privacy, value); }

    private UpcomingEvent? _upcomingEvent;
    public UpcomingEvent? UpcomingEvent { get => _upcomingEvent; set => Set(ref _upcomingEvent, value); }

    private CalendarStatus _calendarStatus;
    public CalendarStatus CalendarStatus { get => _calendarStatus; set => Set(ref _calendarStatus, value); }
    private string _calendarError = "";
    public string CalendarError { get => _calendarError; set => Set(ref _calendarError, value); }

    private bool _mediaAvailable;
    public bool MediaAvailable { get => _mediaAvailable; set => Set(ref _mediaAvailable, value); }

    private DownloadActivity? _download;
    public DownloadActivity? Download { get => _download; set => Set(ref _download, value); }

    /// <summary>Oynatma kafasının saatten ileri sarılması için ~4 Hz'lik tik.</summary>
    private uint _mediaTick;
    public uint MediaTick { get => _mediaTick; private set => Set(ref _mediaTick, value); }
    public void TickMedia() => MediaTick = unchecked(MediaTick + 1);

    private IReadOnlyList<ShelfItem> _shelf = Array.Empty<ShelfItem>();
    public IReadOnlyList<ShelfItem> Shelf
    {
        get => _shelf;
        set
        {
            if (_shelf.SequenceEqual(value)) return;
            _shelf = value;
            // Artık rafta olmayan bir şeyi seçili tutma.
            var ids = value.Select(i => i.Id).ToHashSet();
            if (ShelfSelection.RemoveWhere(id => !ids.Contains(id)) > 0) OnPropertyChanged(nameof(ShelfSelection));
            OnPropertyChanged();
        }
    }

    /// <summary>Ctrl/Shift-tıklama ile seçilmiş raf dosyaları (kimlikleri).</summary>
    public HashSet<string> ShelfSelection { get; } = new();

    private bool _isDropTargeting;
    public bool IsDropTargeting { get => _isDropTargeting; private set => Set(ref _isDropTargeting, value); }
    private bool _isDropHighlighted;
    public bool IsDropHighlighted { get => _isDropHighlighted; private set => Set(ref _isDropHighlighted, value); }
    private int _droppedFileCount;
    public int DroppedFileCount { get => _droppedFileCount; set => Set(ref _droppedFileCount, value); }

    /// <summary>İmlecin altındaki denetim; denetleyicinin imleç örneklemesinden gelir.</summary>
    private IslandControl? _hoveredControl;
    public IslandControl? HoveredControl { get => _hoveredControl; set => Set(ref _hoveredControl, value); }

    /// <summary>Şu an gösterilmeye değer SİSTEM kutucukları, sabit sırayla.</summary>
    public List<SystemTile> SystemTiles
    {
        get
        {
            var tiles = new List<SystemTile>();
            if (Volume != null) tiles.Add(SystemTile.Volume);
            if (Brightness != null) tiles.Add(SystemTile.Brightness);
            if (Power != null) tiles.Add(SystemTile.Battery);
            // Yalnızca gösterecek bir seviye varsa kutucuğa değer.
            if (Devices.Any(d => d.Headline != null)) tiles.Add(SystemTile.Bluetooth);
            return tiles;
        }
    }

    /// <summary>Genişlemiş adanın gösterdiği şey — genişliğine bu karar verir.</summary>
    public ExpandedPayloadKind ExpandedPayloadKind
    {
        get
        {
            switch (Transient)
            {
                case TransientKind.Volume or TransientKind.Brightness: return new ExpandedPayloadKind.Meter();
                case not null: return new ExpandedPayloadKind.Wide();
            }
            if (Countdown != null) return new ExpandedPayloadKind.CountdownKind();
            if (NowPlaying != null) return new ExpandedPayloadKind.NowPlayingKind();
            return new ExpandedPayloadKind.QuickStats(new[] { Power != null, Volume != null, Brightness != null }.Count(b => b));
        }
    }

    /// <summary>Adanın gerçekte çizdiği durum; tıklama alanı da buradan ölçülür.</summary>
    private IslandState _renderedState = IslandState.Compact;
    public IslandState RenderedState { get => _renderedState; private set => Set(ref _renderedState, value); }

    /// <summary>
    /// Ada kompaktken ortadaki şeridin iki yanında ne durur. Sol kimlik (bu ne),
    /// sağ canlı değer (ne yapıyor). Etkin kamera ya da mikrofon sol yuvada
    /// albüm kapağının önüne geçer: kaydedildiğini bilmek ne çaldığını bilmekten önemli.
    /// </summary>
    public CompactAccessories CompactAccessories
    {
        get
        {
            CompactAccessory? privacy = Privacy.IsActive
                ? new CompactAccessory.Privacy(Privacy.CameraActive, Privacy.MicrophoneActive)
                : null;
            CompactAccessory? leading = null, trailing = null;

            if (NowPlaying is { } track)
            {
                leading = new CompactAccessory.Artwork(track.Artwork);
                trailing = Countdown != null
                    ? new CompactAccessory.Countdown(Countdown.Text)
                    : new CompactAccessory.Waveform(track.IsPlaying, track.Palette);
            }
            else if (Countdown != null)
            {
                leading = new CompactAccessory.TimerGlyph();
                trailing = new CompactAccessory.Countdown(Countdown.Text);
            }

            // Süren bir indirme sol yuvayı alır (kapakla aynı taraf); kapak oradaysa sağ.
            if (Download != null)
            {
                if (leading == null) leading = new CompactAccessory.Download();
                else trailing ??= new CompactAccessory.Download();
            }

            if (leading == null && Shelf.Count > 0) leading = new CompactAccessory.Shelf(Shelf.Count);

            if (privacy != null)
            {
                if (leading == null) leading = privacy;
                else if (trailing == null) trailing = privacy;
                else leading = privacy;
            }
            return new CompactAccessories(leading, trailing);
        }
    }

    // MARK: Bağlantılar

    public Action<TransportKind>? OnTransport { get; set; }
    public Action<double>? OnSeek { get; set; }
    public Action<TimerAction>? OnTimerAction { get; set; }
    public Action<ShelfAction>? OnShelfAction { get; set; }

    /// <summary>İmleç ayrıldıktan sonra toplanmadan önce beklenecek saniye.</summary>
    public double AutoCollapseDelay { get; set; } = AppState.DefaultCollapseDelay;

    /// <summary>
    /// "Demo:" menü eylemi adayı ne kadar açık tutar. Ekran kaydı başlatmaya yetecek
    /// kadar uzun, yanlışlıkla tıklanınca donmuş gibi görünmeyecek kadar kısa.
    /// </summary>
    private const double DemoPinDuration = 8;

    private readonly DispatcherTimer _collapseTimer = new();
    private readonly DispatcherTimer _transientTimer = new();
    private readonly DispatcherTimer _pinTimer = new();

    public IslandModel()
    {
        _collapseTimer.Tick += (_, _) =>
        {
            _collapseTimer.Stop();
            if (IsHovering || IsPinned) return;
            State = IslandState.Compact;
            UpdateRenderedState();
        };
        _transientTimer.Tick += (_, _) => ClearTransient();
        _pinTimer.Tick += (_, _) =>
        {
            _pinTimer.Stop();
            if (!IsPinned) return;
            IsPinned = false;
            if (!IsHovering) ScheduleCollapse();
        };
    }

    // MARK: İmleç

    public void SetHovering(bool hovering)
    {
        if (hovering == IsHovering) return;
        IsHovering = hovering;
        if (hovering)
        {
            // Gerçek bir hover demo sabitlemesini devralır.
            Unpin();
            CancelCollapse();
            if (State == IslandState.Compact) State = IslandState.Expanded;
        }
        else
        {
            ScheduleCollapse();
        }
        UpdateRenderedState();
    }

    /// <summary>Adaya tıklama: Kontrol Merkezi'ni aç ya da kapat.</summary>
    public void ToggleControlCenter()
    {
        CancelCollapse();
        if (State == IslandState.ControlCenter)
        {
            IsPinned = false;
            State = IsHovering ? IslandState.Expanded : IslandState.Compact;
        }
        else
        {
            State = IslandState.ControlCenter;
            // Kontrol Merkezi bilinçli bir seçim; altındaki göstergeyi bırak.
            ClearTransient();
        }
        if (!IsHovering) ScheduleCollapse();
        UpdateRenderedState();
    }

    public void Transport(TransportKind kind) => OnTransport?.Invoke(kind);
    public void TimerAction(TimerAction action) => OnTimerAction?.Invoke(action);
    public void ShelfAction(ShelfAction action) => OnShelfAction?.Invoke(action);

    /// <summary>Bir sürüklemeyi yakalamayı teklif et ya da teklifi geri çek.</summary>
    public void SetDropTargeting(bool targeting, bool highlighted = false)
    {
        IsDropTargeting = targeting;
        IsDropHighlighted = targeting && highlighted;
        UpdateRenderedState();
    }

    /// <summary>Raf geneli bir eylemin hedefi: seçim varsa seçim, yoksa rafın tamamı.</summary>
    public List<ShelfItem> EffectiveShelfItems =>
        ShelfSelection.Count == 0 ? Shelf.ToList() : Shelf.Where(i => ShelfSelection.Contains(i.Id)).ToList();

    public void ToggleShelfSelection(int index)
    {
        if (index < 0 || index >= Shelf.Count) return;
        var id = Shelf[index].Id;
        if (!ShelfSelection.Remove(id)) ShelfSelection.Add(id);
        OnPropertyChanged(nameof(ShelfSelection));
    }

    public void SubtractSelection(IEnumerable<string> ids)
    {
        var changed = false;
        foreach (var id in ids) changed |= ShelfSelection.Remove(id);
        if (changed) OnPropertyChanged(nameof(ShelfSelection));
    }

    /// <summary>Kontrol Merkezi'nin hangi isteğe bağlı bölümleri gösterdiği.</summary>
    public ControlCenterSections Sections(bool timerEnabled) =>
        new(UpcomingEvent != null, timerEnabled, Shelf.Count > 0, NowPlaying?.HasProgress ?? false);

    // MARK: Demo eylemleri (bildirim alanı menüsü)

    public void DemoExpand()
    {
        CancelCollapse();
        Pin();
        State = IslandState.Expanded;
        UpdateRenderedState();
    }

    public void DemoToggleControlCenter()
    {
        CancelCollapse();
        if (State == IslandState.ControlCenter)
        {
            Unpin();
            State = IslandState.Compact;
        }
        else
        {
            Pin();
            State = IslandState.ControlCenter;
        }
        UpdateRenderedState();
    }

    /// <summary>
    /// Başka bir şey etkileşimin sahibi olduğu sürece (sağ tık menüsü, dosyayı
    /// dışarı sürükleme) imleçten bağımsız açık tut. Zaman aşımı yok — çağıran söyler.
    /// </summary>
    public void HoldOpen(bool holding)
    {
        if (holding)
        {
            CancelCollapse();
            _pinTimer.Stop();
            IsPinned = true;
        }
        else
        {
            IsPinned = false;
            if (!IsHovering) ScheduleCollapse();
        }
    }

    private void Pin()
    {
        IsPinned = true;
        _pinTimer.Stop();
        _pinTimer.Interval = TimeSpan.FromSeconds(DemoPinDuration);
        _pinTimer.Start();
    }

    private void Unpin()
    {
        _pinTimer.Stop();
        IsPinned = false;
    }

    public void Collapse()
    {
        // Seçim açık panele aittir; dönüp gelince on dakika önceki seçili çipler kalmasın.
        if (ShelfSelection.Count > 0)
        {
            ShelfSelection.Clear();
            OnPropertyChanged(nameof(ShelfSelection));
        }
        CancelCollapse();
        Unpin();
        State = IslandState.Compact;
        UpdateRenderedState();
    }

    // MARK: İçerik

    public void UpdateNowPlaying(NowPlaying? track)
    {
        if (track == null && NowPlaying == null) return;
        if (track != null && track.SameContent(NowPlaying)) return;
        NowPlaying = track;
    }

    /// <summary>Bir sistem olayını adada kısa süre göster.</summary>
    public void Present(TransientKind kind)
    {
        // Kullanıcının kendi açtığı Kontrol Merkezi'ni asla bölme.
        if (State == IslandState.ControlCenter) return;
        Transient = kind;
        UpdateRenderedState();
        _transientTimer.Stop();
        _transientTimer.Interval = TimeSpan.FromSeconds(kind.Dwell);
        _transientTimer.Start();
    }

    private void ClearTransient()
    {
        _transientTimer.Stop();
        if (Transient == null) return;
        Transient = null;
        UpdateRenderedState();
    }

    private void UpdateRenderedState()
    {
        // Havadaki bir sürükleme her şeyin üstündedir: süresi belli tek durum o.
        var resolved = IsDropTargeting ? IslandState.DropZone
            : State == IslandState.ControlCenter ? IslandState.ControlCenter
            : Transient != null ? IslandState.Expanded
            : State;
        RenderedState = resolved;
    }

    // MARK: Otomatik toplanma

    private void ScheduleCollapse()
    {
        CancelCollapse();
        if (IsPinned || State == IslandState.Compact) return;
        _collapseTimer.Interval = TimeSpan.FromSeconds(Math.Max(0.001, AutoCollapseDelay));
        _collapseTimer.Start();
    }

    private void CancelCollapse() => _collapseTimer.Stop();
}
