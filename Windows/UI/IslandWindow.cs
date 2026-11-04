using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using DinamikAda.Core;
using DinamikAda.Island;
using DinamikAda.Monitors;

namespace DinamikAda.UI;

/// <summary>
/// Adayı taşıyan saydam, etkinleşmeyen, en üstte duran pencere (macOS'taki
/// OverlayPanel + PassthroughHostingView).
///
/// Ada dışında her yerde tıklama alttaki uygulamaya geçer: imleç adanın
/// üstünde değilken pencere WS_EX_TRANSPARENT olur. Hover ve "dışarı tıklayınca
/// kapan" imleç örneklemesiyle çözülür; tıklamalar geometriyle, aynı
/// <see cref="IslandLayout"/> ölçülerinden — gördüğün düğme ile basabildiğin
/// düğme ayrışamaz. Hover alanı cömert (12×8), tıklama alanı tam.
/// </summary>
public sealed class IslandWindow : Window
{
    private readonly IslandModel _model;
    private readonly AppState _settings;
    private readonly Canvas _root = new();
    private readonly Path _island = new() { Fill = Brushes.Black, Stroke = V.White(0.08), StrokeThickness = 0.5 };
    private readonly Canvas _content = new() { IsHitTestVisible = false };
    private readonly Rectangle _catcher = new() { Fill = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)), Visibility = Visibility.Collapsed };
    private readonly DropShadowEffect _shadow = new() { Color = Colors.Black, BlurRadius = 24, ShadowDepth = 6, Direction = 270, Opacity = 0 };
    private readonly IslandView _view = new();

    private readonly Spring _w = new(0), _h = new(0), _shift = new(0), _top = new(0), _bottom = new(0), _shadowOpacity = new(0);
    private bool _animating;
    private TimeSpan _lastFrame;
    private bool _firstLayout = true;

    private IslandLayout? _layout;
    private DisplayInfo? _display;
    private IntPtr _hwnd;
    private List<IslandControlHit> _hits = new();
    private bool _renderQueued;
    private IslandState _lastRendered = IslandState.Compact;

    // İmleç
    private readonly DispatcherTimer _hoverTimer = new() { Interval = TimeSpan.FromSeconds(0.06) };
    private bool _wasButtonDown;
    private int _progressTick;
    private int _topmostTick;
    private bool _transparent = true;

    // Basma / sürükleme
    private IslandControlHit? _scrubbing;
    private (string Path, Point Origin)? _pendingDrag;
    private const double ShelfDragThreshold = 6;
    public bool IsDraggingOut { get; private set; }

    // Bırakma
    private bool _probeActive;
    private readonly DispatcherTimer _dragLeave = new() { Interval = TimeSpan.FromMilliseconds(150) };

    private bool _hiddenForFullscreen;

    // MARK: Bağlantılar (denetleyici doldurur)

    public Func<IslandLayout>? LayoutProvider { get; set; }
    public Action<IslandControl>? OnControl { get; set; }
    public Action? OnClick { get; set; }
    public Action<IslandControl, double>? OnScrub { get; set; }
    public Action<IslandControl?>? OnContextMenu { get; set; }
    public Action<string[]>? OnFilesDropped { get; set; }

    private static readonly Thickness HoverMargin = new(12, 8, 12, 8);

    public IslandWindow(IslandModel model, AppState settings)
    {
        _model = model;
        _settings = settings;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Focusable = false;
        Title = "Dinamik Ada";
        AllowDrop = true;
        UseLayoutRounding = true;
        // Yerleşim gelene kadar ekran dışında ve küçük dursun.
        Width = 1;
        Height = 1;
        Left = -10000;
        Top = -10000;
        WindowStartupLocation = WindowStartupLocation.Manual;

        _island.Effect = _shadow;
        _root.Children.Add(_catcher);
        _root.Children.Add(_island);
        _root.Children.Add(_content);
        _content.Children.Add(_view.Compact);
        _content.Children.Add(_view.Expanded);
        _content.Children.Add(_view.ControlCenter);
        _content.Children.Add(_view.DropZone);
        foreach (var layer in Layers) layer.Opacity = 0;
        _view.Compact.Opacity = 1;
        Content = _root;

        SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            Native.SetExStyle(_hwnd, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TRANSPARENT, true);
            ApplyPlacement();
        };
        DpiChanged += (_, _) => Dispatcher.BeginInvoke(ApplyPlacement, DispatcherPriority.Background);

        model.PropertyChanged += OnModelChanged;
        _hoverTimer.Tick += (_, _) => SampleHover();
        _dragLeave.Tick += (_, _) => { _dragLeave.Stop(); _model.SetDropTargeting(false); };

        MouseLeftButtonDown += OnLeftDown;
        MouseMove += OnMove;
        MouseLeftButtonUp += OnLeftUp;
        MouseRightButtonUp += OnRightUp;
        DragEnter += OnDragOver;
        DragOver += OnDragOver;
        DragLeave += (_, _) => _dragLeave.Start();
        Drop += OnDropFiles;
    }

    private IEnumerable<Canvas> Layers => new[] { _view.Compact, _view.Expanded, _view.ControlCenter, _view.DropZone };

    public IntPtr Handle => _hwnd;

    // MARK: Konum

    /// <summary>Adayı bir ekranın üst ortasına yerleştirir.</summary>
    public void Place(DisplayInfo display)
    {
        _display = display;
        ApplyPlacement();
    }

    private void ApplyPlacement()
    {
        if (_hwnd == IntPtr.Zero || _display == null || _layout == null) return;
        var panel = _layout.PanelSize;
        var scale = _display.Scale;
        var pw = (int)Math.Round(panel.Width * scale);
        var ph = (int)Math.Round(panel.Height * scale);
        var x = _display.Bounds.X + (_display.Bounds.Width - pw) / 2;
        var y = _display.Bounds.Y;
        Width = panel.Width;
        Height = panel.Height;
        _root.Width = panel.Width;
        _root.Height = panel.Height;
        Native.SetWindowPos(_hwnd, Native.HWND_TOPMOST, x, y, pw, ph,
            Native.SWP_NOACTIVATE | (_hiddenForFullscreen ? 0 : Native.SWP_SHOWWINDOW));
    }

    public void Start()
    {
        Show();
        _hoverTimer.Start();
        RequestRender();
    }

    /// <summary>Tam ekran bir uygulama ekranı kullanırken ada tamamen kaldırılır.</summary>
    public void SetHiddenForFullscreen(bool hidden)
    {
        if (hidden == _hiddenForFullscreen) return;
        _hiddenForFullscreen = hidden;
        if (hidden)
        {
            _model.Collapse();
            Hide();
        }
        else
        {
            Show();
            ApplyPlacement();
        }
    }

    /// <summary>Ekran görüntüsü, kayıt ve paylaşılan ekrandan çıkar.</summary>
    public void SetHiddenFromCapture(bool hidden)
    {
        if (_hwnd != IntPtr.Zero) Native.SetWindowDisplayAffinity(_hwnd, hidden ? Native.WDA_EXCLUDEFROMCAPTURE : Native.WDA_NONE);
    }

    // MARK: Çizim

    private void OnModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(IslandModel.MediaTick))
        {
            if (_model.RenderedState == IslandState.ControlCenter && _layout != null
                && ControlCenterMetrics.MediaSeekFrame(_layout.ControlCenterSize.Width, _layout.Sections) is { } bar)
                _view.TickSeek(_model.NowPlaying, bar.Width);
            return;
        }
        RequestRender();
    }

    public void RequestRender()
    {
        if (_renderQueued) return;
        _renderQueued = true;
        Dispatcher.BeginInvoke(Render, DispatcherPriority.Render);
    }

    private void Render()
    {
        _renderQueued = false;
        if (LayoutProvider == null) return;
        var layout = LayoutProvider();
        var panelChanged = _layout == null || _layout.PanelSize != layout.PanelSize;
        _layout = layout;
        if (panelChanged) ApplyPlacement();

        var state = _model.RenderedState;
        var acc = _model.CompactAccessories;
        var size = layout.SizeFor(state, acc);

        _w.SetTarget(size.Width);
        _h.SetTarget(size.Height);
        _shift.SetTarget(layout.CentreShift(state, acc));
        _top.SetTarget(layout.TopRadius(state, acc));
        _bottom.SetTarget(layout.BottomRadius(state));
        _shadowOpacity.SetTarget(state == IslandState.Compact ? 0 : 0.35);
        if (_firstLayout)
        {
            _firstLayout = false;
            foreach (var s in new[] { _w, _h, _shift, _top, _bottom, _shadowOpacity }) s.Snap(s.Target);
        }

        // Etkin katmanı içerikle doldur; diğerleri solarak çekilir.
        _view.BuildCompact(layout, acc);
        var inner = Math.Max(0, size.Height - layout.NotchHeight);
        switch (state)
        {
            case IslandState.Expanded:
                _view.BuildExpanded(_model, size.Width, inner);
                break;
            case IslandState.ControlCenter:
                _view.BuildControlCenter(_model, size.Width, inner, layout.Sections);
                break;
            case IslandState.DropZone:
                _view.BuildDropZone(_model.IsDropHighlighted, _model.DroppedFileCount, size.Width, inner);
                break;
        }
        if (state != _lastRendered)
        {
            Fade(_view.Compact, state == IslandState.Compact);
            Fade(_view.Expanded, state == IslandState.Expanded);
            Fade(_view.ControlCenter, state == IslandState.ControlCenter);
            Fade(_view.DropZone, state == IslandState.DropZone);
            _lastRendered = state;
        }

        UpdateHitRegion();
        StartAnimating();
        Frame();
    }

    private static void Fade(UIElement e, bool visible) =>
        e.BeginAnimation(OpacityProperty, new DoubleAnimation(visible ? 1 : 0, TimeSpan.FromSeconds(visible ? 0.22 : 0.12)));

    private void StartAnimating()
    {
        if (_animating) return;
        _animating = true;
        _lastFrame = TimeSpan.Zero;
        CompositionTarget.Rendering += OnRendering;
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        var now = ((RenderingEventArgs)e).RenderingTime;
        var dt = _lastFrame == TimeSpan.Zero ? 1 / 60.0 : Math.Min((now - _lastFrame).TotalSeconds, 1 / 30.0);
        if (dt <= 0) return;
        _lastFrame = now;
        var (response, damping) = _settings.Spring;
        var springs = new[] { _w, _h, _shift, _top, _bottom, _shadowOpacity };
        foreach (var s in springs) s.Step(dt, response, damping);
        Frame();
        if (springs.All(s => s.IsSettled))
        {
            CompositionTarget.Rendering -= OnRendering;
            _animating = false;
        }
    }

    /// <summary>Yayların şu anki değerleriyle şekli ve katmanların yerini günceller.</summary>
    private void Frame()
    {
        if (_layout == null) return;
        var w = Math.Max(1, _w.Value);
        var h = Math.Max(1, _h.Value);
        var x = _layout.PanelSize.Width / 2 - w / 2 + _shift.Value;
        var rect = new Rect(x, 0, w, h);
        var shape = IslandShape.Build(rect, Math.Max(0, _top.Value), Math.Max(0, _bottom.Value));
        _island.Data = shape;
        _content.Clip = shape;
        _shadow.Opacity = Math.Clamp(_shadowOpacity.Value, 0, 1);

        var centre = x + w / 2;
        Canvas.SetLeft(_view.Compact, centre - _view.Compact.Width / 2);
        Canvas.SetTop(_view.Compact, 0);
        foreach (var layer in new[] { _view.Expanded, _view.ControlCenter, _view.DropZone })
        {
            if (double.IsNaN(layer.Width)) continue;
            Canvas.SetLeft(layer, centre - layer.Width / 2);
            Canvas.SetTop(layer, _layout.NotchHeight);
        }
    }

    // MARK: Tıklama alanları

    private Rect IslandRect => _layout?.IslandRect(_model.RenderedState, _model.CompactAccessories) ?? Rect.Empty;

    private int? HoveredShelfIndex => _model.HoveredControl switch
    {
        IslandControl.Shelf { Action: ShelfAction.Open o } => o.Index,
        IslandControl.Shelf { Action: ShelfAction.Remove r } => r.Index,
        _ => null,
    };

    private void UpdateHitRegion()
    {
        if (_layout == null) return;
        _hits = _model.RenderedState switch
        {
            IslandState.ControlCenter => _layout.ControlHits(_model.SystemTiles, _model.NowPlaying != null, _model.Countdown,
                                                             _model.Shelf.Count, HoveredShelfIndex),
            IslandState.Expanded when _model.NowPlaying != null && _model.Transient == null && _model.Countdown == null
                => _layout.ExpandedControlHits(_model.CompactAccessories),
            _ => new List<IslandControlHit>(),
        };
        if (_hits.Count == 0 && _model.HoveredControl != null) _model.HoveredControl = null;
    }

    private IslandControlHit? HitAt(Point p) => _hits.FirstOrDefault(h => h.HitRect.Contains(p));

    // MARK: İmleç örneklemesi

    private Point? PointerInWindow()
    {
        if (!IsVisible || PresentationSource.FromVisual(_root) == null) return null;
        if (!Native.GetCursorPos(out var pt)) return null;
        try { return _root.PointFromScreen(new Point(pt.X, pt.Y)); } catch { return null; }
    }

    private void SampleHover()
    {
        if (_hiddenForFullscreen || IsDraggingOut || _layout == null) return;

        if (++_topmostTick >= 33 && _hwnd != IntPtr.Zero)
        {
            // Başka bir "en üstte" pencere araya girdiyse yerimizi geri al.
            _topmostTick = 0;
            Native.SetWindowPos(_hwnd, Native.HWND_TOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
        }
        TickProgress();

        var buttonDown = Native.IsKeyDown(Native.VK_LBUTTON);
        if (_scrubbing != null && !buttonDown) EndScrub();   // kaçan bir bırakma sürüklemeyi kilitlemesin

        if (PointerInWindow() is not { } pointer) return;

        if (_settings.ShelfEnabled) SampleDropProbe(buttonDown, pointer);

        if (_scrubbing != null)
        {
            _model.SetHovering(true);
            return;
        }

        var island = IslandRect;
        var hoverRect = island;
        hoverRect.Inflate(HoverMargin.Left, HoverMargin.Top);
        var hovering = hoverRect.Contains(pointer);
        var pressable = island.Contains(pointer);

        DismissIfClickedAway(buttonDown, hovering);

        var accepting = pressable || _model.IsDropTargeting || _probeActive;
        SetTransparent(!accepting);
        _model.SetHovering(hovering);
        SampleHoveredControl(pressable ? pointer : null);
    }

    private void SetTransparent(bool transparent)
    {
        if (transparent == _transparent || _hwnd == IntPtr.Zero) return;
        _transparent = transparent;
        Native.SetExStyle(_hwnd, Native.WS_EX_TRANSPARENT, transparent);
    }

    /// <summary>Oynatma kafası her 4 örnekte (~0,24 sn) ileri sarılır, yalnız ada açıkken.</summary>
    private void TickProgress()
    {
        if (++_progressTick < 4) return;
        _progressTick = 0;
        if (_model.RenderedState > IslandState.Compact && _model.NowPlaying is { IsPlaying: true, HasProgress: true })
            _model.TickMedia();
    }

    /// <summary>Ada açıkken başka bir yere basılırsa hemen topla.</summary>
    private void DismissIfClickedAway(bool buttonDown, bool pointerOnIsland)
    {
        var pressed = buttonDown && !_wasButtonDown;
        _wasButtonDown = buttonDown;
        if (!pressed || pointerOnIsland || _model.RenderedState == IslandState.Compact
            || _model.IsDropTargeting || _probeActive || _scrubbing != null) return;
        _model.Collapse();
    }

    private void SampleHoveredControl(Point? pointer)
    {
        var hovered = pointer is { } p ? HitAt(p)?.Control : null;
        if (Equals(_model.HoveredControl, hovered)) return;
        _model.HoveredControl = hovered;
        // Raf çipinin üstüne gelince "kaldır" rozeti tıklanabilir olsun.
        UpdateHitRegion();
    }

    // MARK: Fare

    private void OnLeftDown(object sender, MouseButtonEventArgs e)
    {
        var p = e.GetPosition(_root);
        if (_model.RenderedState == IslandState.ControlCenter && HitAt(p)?.Control is IslandControl.Shelf { Action: ShelfAction.Open o }
            && o.Index < _model.Shelf.Count)
        {
            _pendingDrag = (_model.Shelf[o.Index].Path, p);
            return;
        }
        if (HitAt(p) is { } hit && IsScrubbable(hit.Control))
        {
            _scrubbing = hit;
            _root.CaptureMouse();
            OnScrub?.Invoke(hit.Control, hit.Fraction(p));
        }
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        var p = e.GetPosition(_root);
        if (_pendingDrag is { } pending && e.LeftButton == MouseButtonState.Pressed)
        {
            if ((p - pending.Origin).Length < ShelfDragThreshold) return;
            _pendingDrag = null;
            BeginFileDrag(pending.Path);
            return;
        }
        if (_scrubbing is { } s) OnScrub?.Invoke(s.Control, s.Fraction(p));
    }

    private void OnLeftUp(object sender, MouseButtonEventArgs e)
    {
        _pendingDrag = null;
        if (_scrubbing != null)
        {
            EndScrub();
            return;
        }
        var p = e.GetPosition(_root);
        if (HitAt(p) is { } hit)
        {
            switch (hit.Control)
            {
                case IslandControl.Shelf { Action: ShelfAction.Open o }
                    when Keyboard.Modifiers.HasFlag(ModifierKeys.Control) || Keyboard.Modifiers.HasFlag(ModifierKeys.Shift):
                    OnControl?.Invoke(new IslandControl.Shelf(new ShelfAction.ToggleSelection(o.Index)));
                    break;
                case IslandControl.Tile or IslandControl.Seek:
                    break;   // salt gösterge kutucuğu tıklamayı yutar, panel altından kapanmaz
                default:
                    OnControl?.Invoke(hit.Control);
                    break;
            }
            return;
        }
        if (IslandRect.Contains(p)) OnClick?.Invoke();
    }

    private void OnRightUp(object sender, MouseButtonEventArgs e)
    {
        var p = e.GetPosition(_root);
        if (!IslandRect.Contains(p)) return;
        OnContextMenu?.Invoke(HitAt(p)?.Control);
    }

    private void EndScrub()
    {
        _scrubbing = null;
        if (_root.IsMouseCaptured) _root.ReleaseMouseCapture();
    }

    private static bool IsScrubbable(IslandControl c) => c switch
    {
        IslandControl.Tile t => t.Kind.IsAdjustable(),
        IslandControl.Seek => true,
        _ => false,
    };

    /// <summary>
    /// Raftaki bir dosyayı dışarı sürükle. Sürükleme sürerken kendi dosyamızı
    /// bırakma olarak kabul etmeyiz ve ada açık kalır.
    /// </summary>
    private void BeginFileDrag(string path)
    {
        IsDraggingOut = true;
        _model.SetDropTargeting(false);
        _model.HoldOpen(true);
        try
        {
            var data = new DataObject(DataFormats.FileDrop, new[] { path });
            DragDrop.DoDragDrop(_root, data, DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link);
        }
        catch { }
        finally
        {
            IsDraggingOut = false;
            _model.HoldOpen(false);
        }
    }

    // MARK: Bırakma

    /// <summary>
    /// Windows'ta bir dosya sürüklemesinin başladığını duyuran genel bir bildirim
    /// yok (macOS sürükleme panosunu yokluyordu). Sol tuş basılıyken imleç adanın
    /// bırakma alanına girince, neredeyse saydam bir yakalama yüzeyi açılır;
    /// gerçekten dosya taşıyan bir sürükleme ise Windows ona DragEnter gönderir.
    /// </summary>
    private void SampleDropProbe(bool buttonDown, Point pointer)
    {
        if (_layout == null) return;
        var zone = _layout.IslandRect(IslandState.DropZone, CompactAccessories.None);
        zone.Inflate(24, 16);
        if (buttonDown && !_probeActive && zone.Contains(pointer) && !IsDraggingOut && _scrubbing == null
            && _model.RenderedState != IslandState.ControlCenter)
        {
            _probeActive = true;
            Canvas.SetLeft(_catcher, Math.Max(0, zone.X));
            Canvas.SetTop(_catcher, 0);
            _catcher.Width = Math.Min(zone.Width, _layout.PanelSize.Width);
            _catcher.Height = Math.Min(zone.Bottom, _layout.PanelSize.Height);
            _catcher.Visibility = Visibility.Visible;
            SetTransparent(false);
        }
        else if (!buttonDown && _probeActive)
        {
            _probeActive = false;
            _catcher.Visibility = Visibility.Collapsed;
            if (_model.IsDropTargeting) _model.SetDropTargeting(false);
        }
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        _dragLeave.Stop();
        if (IsDraggingOut || !_settings.ShelfEnabled || e.Data.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0)
        {
            e.Effects = DragDropEffects.None;
            e.Handled = true;
            return;
        }
        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
        _model.DroppedFileCount = files.Length;
        var island = _layout?.IslandRect(IslandState.DropZone, CompactAccessories.None) ?? Rect.Empty;
        _model.SetDropTargeting(true, island.Contains(e.GetPosition(_root)));
    }

    private void OnDropFiles(object sender, DragEventArgs e)
    {
        _dragLeave.Stop();
        if (!IsDraggingOut && e.Data.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
            OnFilesDropped?.Invoke(files);
        _model.SetDropTargeting(false);
        e.Handled = true;
    }
}
