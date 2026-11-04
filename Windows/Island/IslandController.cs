using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Media;
using System.Windows;
using System.Windows.Controls;
using DinamikAda.Core;
using DinamikAda.Monitors;
using DinamikAda.UI;
using Microsoft.Win32;

namespace DinamikAda.Island;

/// <summary>
/// Pencere ⇄ model ⇄ ayarlar ⇄ izleyiciler. macOS sürümündeki IslandController'ın
/// karşılığı: izleyicileri ayarlara göre açar/kapatır, sistem olaylarını modele,
/// adadaki basışları eylemlere çevirir.
/// </summary>
public sealed class IslandController
{
    public IslandModel Model { get; } = new();
    public IslandTimer Countdown { get; } = new();
    public FileShelf Shelf { get; } = new();

    private readonly AppState _settings = AppState.Shared;
    private readonly IslandWindow _window;

    private readonly VolumeMonitor _volume = new();
    private readonly BrightnessMonitor _brightness = new();
    private readonly BatteryMonitor _battery = new();
    private readonly NowPlayingMonitor _nowPlaying = new();
    private readonly BluetoothMonitor _bluetooth = new();
    private readonly PrivacyMonitor _privacy = new();
    private readonly CalendarMonitor _calendar = new();
    private readonly MediaKeyMonitor _mediaKeys = new();
    private readonly DownloadMonitor _downloads = new();
    private readonly FullscreenDetector _fullscreen = new();

    public IslandController()
    {
        Model.AutoCollapseDelay = _settings.AutoCollapseDelay;
        _window = new IslandWindow(Model, _settings)
        {
            LayoutProvider = CurrentLayout,
            OnClick = Model.ToggleControlCenter,
            OnControl = HandleControl,
            OnScrub = Scrub,
            OnContextMenu = ShowContextMenu,
            OnFilesDropped = files => { Shelf.Add(files); Model.SetDropTargeting(false); },
        };

        Model.OnTimerAction = RunTimer;
        Model.OnShelfAction = RunShelf;
        Shelf.OnChange = items => Model.Shelf = items;
        Model.Shelf = Shelf.Items.ToList();
        _fullscreen.OnChange = hidden => _window.SetHiddenForFullscreen(hidden);

        _settings.PropertyChanged += OnSettingsChanged;
        SystemEvents.DisplaySettingsChanged += OnDisplaysChanged;

        PlaceOnDisplay();
        _window.Start();
        _fullscreen.Own = _window.Handle;
        ConfigureMonitors();
    }

    public IntPtr WindowHandle => _window.Handle;

    private IslandLayout CurrentLayout() =>
        new(NotchMetrics.For(_settings.IslandSize), _settings.IslandSize,
            Model.Sections(_settings.TimerEnabled), Model.ExpandedPayloadKind);

    private void PlaceOnDisplay()
    {
        var display = Displays.Preferred(_settings.PreferredDisplay);
        if (display == null) return;
        _window.Place(display);
        _fullscreen.Monitor = display.Handle;
    }

    private void OnDisplaysChanged(object? sender, EventArgs e) =>
        Application.Current?.Dispatcher.BeginInvoke(() => { PlaceOnDisplay(); _window.RequestRender(); });

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        Model.AutoCollapseDelay = _settings.AutoCollapseDelay;
        if (e.PropertyName is nameof(AppState.PreferredDisplay) or nameof(AppState.IslandSize)) PlaceOnDisplay();
        ConfigureMonitors();
        _window.RequestRender();
    }

    /// <summary>Kapatılan modülün izleyicisi tamamen durur.</summary>
    private void ConfigureMonitors()
    {
        var s = _settings;
        _volume.SnapsToFivePercent = s.SnapLevelsToFivePercent;

        if (s.VolumeEnabled)
        {
            _volume.OnChange = (level, muted) =>
            {
                Model.Volume = level;
                Model.Present(new TransientKind.Volume(level, muted));
            };
            _volume.Start();
            Model.Volume = _volume.CurrentLevel();
            if (s.SnapLevelsToFivePercent && Model.Volume is { } v && !v.IsOnFivePercentGrid())
            {
                _volume.SetLevel(v);
                Model.Volume = v.SnappedToFivePercent();
            }
        }
        else
        {
            _volume.Stop();
            Model.Volume = null;
        }

        if (s.BrightnessEnabled)
        {
            _brightness.OnChange = (level, userInitiated) =>
            {
                Model.Brightness = level;
                if (userInitiated) Model.Present(new TransientKind.Brightness(level));
            };
            _brightness.Start(level => Model.Brightness = level);
        }
        else
        {
            _brightness.Stop();
            Model.Brightness = null;
        }

        if (s.BatteryEnabled)
        {
            _battery.OnPowerEvent = (snapshot, ev) =>
            {
                Model.Power = snapshot;
                Model.Present(new TransientKind.Power(snapshot, ev));
            };
            _battery.OnSnapshot = snapshot => Model.Power = snapshot;
            _battery.Start();
            Model.Power = _battery.Snapshot;
        }
        else
        {
            _battery.Stop();
            Model.Power = null;
        }

        if (s.MusicEnabled)
        {
            _nowPlaying.OnChange = track => Model.UpdateNowPlaying(track);
            _nowPlaying.OnAvailabilityChange = ok => Model.MediaAvailable = ok;
            Model.OnTransport = _nowPlaying.Send;
            Model.OnSeek = _nowPlaying.Seek;
            _nowPlaying.Start();
        }
        else
        {
            _nowPlaying.Stop();
            Model.OnTransport = null;
            Model.OnSeek = null;
            Model.UpdateNowPlaying(null);
        }

        if (s.TimerEnabled)
        {
            Countdown.OnChange = state => Model.Countdown = state;
            Countdown.OnFinished = TimerFinished;
        }
        else
        {
            Countdown.Cancel();
            Model.Countdown = null;
        }

        if (s.BluetoothEnabled)
        {
            _bluetooth.OnChange = devices => Model.Devices = devices;
            _bluetooth.OnConnect = device => { if (device.HasBattery) Model.Present(new TransientKind.Device(device)); };
            _bluetooth.Start();
            Model.Devices = _bluetooth.Devices;
        }
        else
        {
            _bluetooth.Stop();
            Model.Devices = Array.Empty<BluetoothDevice>();
        }

        if (s.CalendarEnabled)
        {
            _calendar.OnChange = ev => Model.UpcomingEvent = ev;
            _calendar.OnStatusChange = (status, error) => { Model.CalendarStatus = status; Model.CalendarError = error; };
            _calendar.OnImminent = ev => Model.Present(new TransientKind.Upcoming(ev));
            _calendar.Start(s.CalendarUrl);
        }
        else
        {
            _calendar.Stop();
            Model.UpcomingEvent = null;
            Model.CalendarStatus = CalendarStatus.NoLink;
        }

        if (!s.ShelfEnabled) Model.SetDropTargeting(false);

        if (s.PrivacyEnabled)
        {
            _privacy.OnChange = state => Model.Privacy = state;
            _privacy.Start();
            Model.Privacy = _privacy.State;
        }
        else
        {
            _privacy.Stop();
            Model.Privacy = PrivacyState.Idle;
        }

        if (s.DownloadsEnabled)
        {
            _downloads.OnChange = activity => Model.Download = activity;
            _downloads.OnComplete = activity => Model.Present(new TransientKind.Download(activity));
            _downloads.Start();
            Model.Download = _downloads.Activity;
        }
        else
        {
            _downloads.Stop();
            Model.Download = null;
        }

        if (s.MediaKeysEnabled)
        {
            _mediaKeys.OnKey = HandleMediaKey;
            _mediaKeys.Start();
        }
        else
        {
            _mediaKeys.Stop();
        }

        if (s.HideWhenFullscreen) _fullscreen.Start();
        else _fullscreen.Stop();

        _window.SetHiddenFromCapture(s.HideInScreenshots);
    }

    /// <summary>Uygulanamayan tuş false döner ve sisteme aynen geçer.</summary>
    private bool HandleMediaKey(MediaKey key, bool precise)
    {
        if (!_settings.VolumeEnabled) return false;
        switch (key)
        {
            case MediaKey.VolumeUp: return _volume.Step(true, precise);
            case MediaKey.VolumeDown: return _volume.Step(false, precise);
            default:
                _volume.ToggleMute();
                return true;
        }
    }

    // MARK: Adadaki basışlar

    private void HandleControl(IslandControl control)
    {
        switch (control)
        {
            case IslandControl.Transport t: Model.Transport(t.Kind); break;
            case IslandControl.Timer t: Model.TimerAction(t.Action); break;
            case IslandControl.Shelf s: Model.ShelfAction(s.Action); break;
            case IslandControl.Artwork:
                if (Model.NowPlaying is { } track)
                {
                    NowPlayingMonitor.OpenApp(track.SourceAppId);
                    Model.Collapse();
                }
                break;
        }
    }

    private void Scrub(IslandControl control, double value)
    {
        switch (control)
        {
            case IslandControl.Seek:
                Model.OnSeek?.Invoke(value);
                if (Model.NowPlaying is { Duration: { } duration } track)
                    Model.UpdateNowPlaying(track with { Elapsed = duration * value.Unit(), ElapsedSampledAt = DateTime.UtcNow });
                break;
            case IslandControl.Tile { Kind: SystemTile.Volume }:
                _volume.SetLevel(value);
                Model.Volume = _settings.SnapLevelsToFivePercent ? value.SnappedToFivePercent() : value;
                break;
            case IslandControl.Tile { Kind: SystemTile.Brightness }:
                _brightness.SetLevel(value);
                Model.Brightness = value;
                break;
        }
    }

    public void RunTimer(TimerAction action)
    {
        switch (action)
        {
            case TimerAction.Start s: Countdown.Start(s.Minutes); break;
            case TimerAction.Toggle: Countdown.Toggle(); break;
            case TimerAction.Restart: Countdown.Restart(); break;
            case TimerAction.Cancel: Countdown.Cancel(); break;
        }
    }

    private void TimerFinished(double duration)
    {
        if (_settings.SoundEffectsEnabled) PlayChime();
        Model.Present(new TransientKind.TimerFinished(duration));
    }

    private static void PlayChime()
    {
        try
        {
            var wav = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media", "Windows Notify System Generic.wav");
            if (File.Exists(wav)) new SoundPlayer(wav).Play();
            else SystemSounds.Asterisk.Play();
        }
        catch { }
    }

    public void RunShelf(ShelfAction action)
    {
        switch (action)
        {
            case ShelfAction.Open o when o.Index < Shelf.Items.Count: FileShelf.Open(Shelf.Items[o.Index]); break;
            case ShelfAction.Remove r when r.Index < Shelf.Items.Count: Shelf.Remove(new[] { Shelf.Items[r.Index] }); break;
            case ShelfAction.ToggleSelection t: Model.ToggleShelfSelection(t.Index); break;
            case ShelfAction.CopyAll: FileShelf.Copy(Model.EffectiveShelfItems); break;
            case ShelfAction.ShareAll: FileShelf.Share(Model.EffectiveShelfItems, _window.Handle); break;
            case ShelfAction.Clear:
                if (Model.ShelfSelection.Count == 0) Shelf.Clear();
                else Shelf.Remove(Model.EffectiveShelfItems);
                break;
        }
    }

    /// <summary>
    /// Sağ tık menüsü. Seçimin *içindeki* bir çipe sağ tıklamak menüyü tüm seçime
    /// uygular. Menü açıkken ada imleçten bağımsız açık tutulur.
    /// </summary>
    private void ShowContextMenu(IslandControl? control)
    {
        var menu = new ContextMenu();
        if (control is IslandControl.Shelf { Action: ShelfAction.Open o } && o.Index < Shelf.Items.Count)
        {
            var item = Shelf.Items[o.Index];
            var targets = Model.ShelfSelection.Contains(item.Id) ? Model.EffectiveShelfItems : new() { item };
            var many = targets.Count > 1;
            Add(menu, many ? Strings.OpenCount(targets.Count) : Strings.Open, () => targets.ForEach(FileShelf.Open));
            Add(menu, Strings.RevealInExplorer, () => FileShelf.Reveal(targets));
            menu.Items.Add(new Separator());
            Add(menu, Strings.Copy, () => FileShelf.Copy(targets));
            Add(menu, Strings.ShareEllipsis, () => FileShelf.Share(targets, _window.Handle));
            Add(menu, Strings.MoveToEllipsis, () => MoveShelfItems(targets));
            menu.Items.Add(new Separator());
            Add(menu, many ? Strings.RemoveCount(targets.Count) : Strings.RemoveFromShelf, () => Shelf.Remove(targets));
        }
        else if (Shelf.Items.Count > 0 && _settings.ShelfEnabled)
        {
            var targets = Model.EffectiveShelfItems;
            Add(menu, Strings.CopyShelfFiles, () => FileShelf.Copy(targets));
            Add(menu, Strings.ShareShelfFiles, () => FileShelf.Share(targets, _window.Handle));
            Add(menu, Strings.MoveToEllipsis, () => MoveShelfItems(targets));
            menu.Items.Add(new Separator());
            Add(menu, Strings.RevealInExplorer, () => FileShelf.Reveal(targets));
            menu.Items.Add(new Separator());
            Add(menu, Strings.ClearShelf, Shelf.Clear);
        }
        if (menu.Items.Count == 0) return;

        Model.HoldOpen(true);
        menu.Closed += (_, _) => Model.HoldOpen(false);
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.IsOpen = true;
    }

    private static void Add(ContextMenu menu, string title, Action action)
    {
        var item = new MenuItem { Header = title };
        item.Click += (_, _) => action();
        menu.Items.Add(item);
    }

    private void MoveShelfItems(System.Collections.Generic.List<ShelfItem> items)
    {
        Shelf.Move(items, (moved, error) =>
        {
            Model.SubtractSelection(moved.Select(m => m.Id));
            if (error != null) MessageBox.Show(error, Strings.MoveFailed, MessageBoxButton.OK, MessageBoxImage.Warning);
        });
    }

    public void Shutdown()
    {
        _volume.Stop();
        _brightness.Stop();
        _battery.Stop();
        _nowPlaying.Stop();
        _bluetooth.Stop();
        _privacy.Stop();
        _calendar.Stop();
        _mediaKeys.Stop();
        _downloads.Stop();
        _fullscreen.Stop();
        Countdown.Cancel();
        SystemEvents.DisplaySettingsChanged -= OnDisplaysChanged;
        _window.Close();
    }
}
