using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using DinamikAda.Core;
using Localization = DinamikAda.Core.Localization;
using DinamikAda.Island;

namespace DinamikAda.UI;

/// <summary>
/// Adanın içerikleri: kompakt aksesuarlar, genişlemiş satır (göstergeler, Now
/// Playing, geri sayım, hızlı bilgiler), Kontrol Merkezi ve bırakma alanı.
/// macOS sürümündeki IslandView + IslandPayloads'ın karşılığı; bütün konumlar
/// <see cref="IslandLayout"/> ölçülerinden gelir. Tıklama burada değil,
/// pencerede geometriyle çözülür — bu yüzden içerik tıklama almaz.
/// </summary>
public sealed class IslandView
{
    public Canvas Compact { get; } = new() { IsHitTestVisible = false };
    public Canvas Expanded { get; } = new() { IsHitTestVisible = false };
    public Canvas ControlCenter { get; } = new() { IsHitTestVisible = false };
    public Canvas DropZone { get; } = new() { IsHitTestVisible = false };

    // Animasyonu olan parçalar her çizimde yeniden kurulmasın, yoksa baştan başlarlar.
    private Waveform? _waveform;
    private DownloadAccessory? _download;
    private Marquee? _marquee;
    private Border? _seekFill;
    private TextBlock? _seekElapsed, _seekRemaining;

    // MARK: Kompakt

    public void BuildCompact(IslandLayout layout, CompactAccessories accessories)
    {
        Compact.Children.Clear();
        var size = layout.CompactSize(accessories);
        Compact.Width = size.Width;
        Compact.Height = layout.NotchHeight;
        if (accessories.IsEmpty) return;

        var h = layout.NotchHeight;
        if (accessories.Leading is { } leading)
            V.Place(Compact, Accessory(leading, h), 0, 0, leading.Width, h);
        if (accessories.Trailing is { } trailing)
            V.Place(Compact, Accessory(trailing, h), size.Width - trailing.Width, 0, trailing.Width, h);
    }

    private FrameworkElement Accessory(CompactAccessory a, double h)
    {
        FrameworkElement content = a switch
        {
            CompactAccessory.Artwork art => V.Artwork(art.Image, 20, 5),
            CompactAccessory.Waveform w => WaveformFor(w.Playing, w.Palette),
            CompactAccessory.Countdown c => V.Text(c.Text, 11, FontWeights.SemiBold, V.White(), mono: true),
            CompactAccessory.TimerGlyph => V.Icon(Glyphs.Timer, 13, V.White(0.85)),
            CompactAccessory.Privacy p => V.PrivacyDots(p.Camera, p.Microphone),
            CompactAccessory.Shelf s => V.ShelfAccessory(s.Count),
            CompactAccessory.Download => _download ??= new DownloadAccessory(),
            _ => new Grid(),
        };
        V.Detach(content);
        content.HorizontalAlignment = HorizontalAlignment.Center;
        content.VerticalAlignment = VerticalAlignment.Center;
        var cell = new Grid { Height = h };
        cell.Children.Add(content);
        return cell;
    }

    private Waveform WaveformFor(bool playing, ArtworkPalette palette)
    {
        if (_waveform == null || _waveform.Playing != playing || !_waveform.Palette.Equals(palette))
            _waveform = new Waveform(playing, palette);
        return _waveform;
    }

    // MARK: Genişlemiş

    public void BuildExpanded(IslandModel model, double width, double innerHeight)
    {
        Expanded.Children.Clear();
        Expanded.Width = width;
        Expanded.Height = innerHeight;

        if (model.Transient is { } transient)
        {
            Row(Expanded, Hud(transient), width, innerHeight);
        }
        else if (model.Countdown is { } countdown)
        {
            Row(Expanded, CountdownRow(countdown), width, innerHeight);
        }
        else if (model.NowPlaying is { } track)
        {
            NowPlayingRow(model, track, width, innerHeight);
        }
        else
        {
            var chips = new List<FrameworkElement>();
            if (model.Power is { } p) chips.Add(V.StatChip(Glyphs.Battery(p.Percentage, p.IsCharging), $"{p.Percentage}%"));
            if (model.Volume is { } v) chips.Add(V.StatChip(Glyphs.Volume(v, false), v.PercentText()));
            if (model.Brightness is { } b) chips.Add(V.StatChip(Glyphs.Brightness, b.PercentText()));
            FrameworkElement row = chips.Count == 0
                ? V.Text(Strings.DynamicIsland, 12, FontWeights.SemiBold, V.White(0.8))
                : V.Row(8, chips.ToArray());
            row.HorizontalAlignment = HorizontalAlignment.Center;
            var host = new Grid { Width = width, Height = innerHeight };
            host.Children.Add(row);
            V.Place(Expanded, host, 0, 0);
        }
    }

    /// <summary>18 pt yatay dolgu ile tam satır.</summary>
    private static void Row(Canvas layer, FrameworkElement content, double width, double height)
    {
        var host = new Grid { Width = width, Height = height, Margin = new Thickness(0) };
        content.Margin = new Thickness(18, 0, 18, 0);
        content.VerticalAlignment = VerticalAlignment.Center;
        host.Children.Add(content);
        V.Place(layer, host, 0, 0);
    }

    /// <summary>simge | içerik | sağdaki değer</summary>
    private static Grid ThreeColumns(FrameworkElement icon, double iconWidth, FrameworkElement middle, FrameworkElement? trailing, double gap = 12)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(iconWidth) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(icon);
        middle.Margin = new Thickness(gap, 0, trailing == null ? 0 : 8, 0);
        middle.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(middle, 1);
        g.Children.Add(middle);
        if (trailing != null)
        {
            trailing.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(trailing, 2);
            g.Children.Add(trailing);
        }
        return g;
    }

    private static StackPanel TwoLines(string title, string? subtitle, double subtitleOpacity = 0.55)
    {
        var p = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        p.Children.Add(V.Text(title, 12, FontWeights.SemiBold, V.White()));
        if (!string.IsNullOrEmpty(subtitle))
        {
            var s = V.Text(subtitle, 10, FontWeights.Normal, V.White(subtitleOpacity));
            s.Margin = new Thickness(0, 2, 0, 0);
            p.Children.Add(s);
        }
        return p;
    }

    private static FrameworkElement Hud(TransientKind kind)
    {
        switch (kind)
        {
            case TransientKind.Volume v:
                return MeterRow(Glyphs.Volume(v.Level, v.Muted), v.Muted ? 0 : v.Level, v.Muted ? Strings.Muted : v.Level.PercentText());
            case TransientKind.Brightness b:
                return MeterRow(Glyphs.Brightness, b.Level, b.Level.PercentText());
            case TransientKind.Power p:
            {
                var s = p.Snapshot;
                var (glyph, tint) = p.Event switch
                {
                    PowerEvent.FullyCharged => (Glyphs.Battery(100, true), (Brush)V.Green),
                    PowerEvent.LowBattery => (Glyphs.Warning, (Brush)V.Orange),
                    _ => (Glyphs.Battery(s.Percentage, s.IsCharging), s.IsCharging ? V.Green : (Brush)V.White()),
                };
                var headline = p.Event switch
                {
                    PowerEvent.PluggedIn => Strings.PowerAdapter,
                    PowerEvent.Unplugged => Strings.OnBattery,
                    PowerEvent.FullyCharged => Strings.FullyCharged,
                    _ => Strings.LowBattery,
                };
                string? sub = s.MinutesRemaining is { } m
                    ? (s.IsCharging ? Strings.UntilFull(Duration(m)) : Strings.Remaining(Duration(m)))
                    : null;
                var lines = TwoLines(headline, sub);
                if (p.Event.IsWarning) ((TextBlock)lines.Children[0]).Foreground = V.Orange;
                return ThreeColumns(V.Icon(glyph, 15, tint), 22, lines,
                    V.Text($"{s.Percentage}%", 15, FontWeights.SemiBold, V.White(), mono: true));
            }
            case TransientKind.Device d:
            {
                var pips = new List<FrameworkElement>();
                if (d.Info.Left is { } l) pips.Add(Pip("L", l));
                if (d.Info.Right is { } r) pips.Add(Pip("R", r));
                if (d.Info.Left == null && d.Info.Right == null && d.Info.Single is { } single) pips.Add(Pip(null, single));
                if (d.Info.Case is { } c) pips.Add(Pip("C", c));
                return ThreeColumns(V.Icon(Glyphs.Headphones, 15, V.White()), 24,
                    TwoLines(d.Info.Name, Strings.Connected), V.Row(10, pips.ToArray()));
            }
            case TransientKind.TimerFinished t:
                return ThreeColumns(V.Icon(Glyphs.Timer, 15, V.White()), 22,
                    TwoLines(Strings.TimerFinished, Strings.MinutesShort((int)Math.Round(t.Duration / 60, MidpointRounding.AwayFromZero))), null);
            case TransientKind.Upcoming e:
                return ThreeColumns(V.Icon(Glyphs.Calendar, 15, V.White()), 22,
                    TwoLines(e.Info.Title, e.Info.Location ?? e.Info.TimeText),
                    V.Text(e.Info.RelativeText, 12, FontWeights.SemiBold, V.White()));
            case TransientKind.Download dl:
            {
                var a = dl.Activity;
                var name = V.Text(a.FileName, 12, FontWeights.SemiBold, V.White());
                name.TextTrimming = TextTrimming.CharacterEllipsis;
                var lines = new StackPanel();
                lines.Children.Add(name);
                var sub = V.Text(a.IsComplete ? Strings.DownloadFinished : Strings.Downloading(a.OtherCount), 10, FontWeights.Normal, V.White(0.55));
                sub.Margin = new Thickness(0, 2, 0, 0);
                lines.Children.Add(sub);
                return ThreeColumns(V.Icon(Glyphs.Download, 15, a.IsComplete ? V.Green : V.White()), 22, lines,
                    V.Text(Bytes(a.Bytes), 12, FontWeights.SemiBold, V.White(0.85), mono: true));
            }
        }
        return new Grid();
    }

    private static Grid MeterRow(string glyph, double value, string trailing)
    {
        var text = V.Text(trailing, 11, FontWeights.Medium, V.White(0.8), mono: true);
        text.Width = 44;
        text.TextAlignment = TextAlignment.Right;
        return ThreeColumns(V.Icon(glyph, 14, V.White()), 20, V.MeterBar(value), text);
    }

    private static StackPanel Pip(string? label, int percentage)
    {
        var p = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var value = V.Text($"{percentage}%", 11, FontWeights.SemiBold, V.White(), mono: true);
        value.HorizontalAlignment = HorizontalAlignment.Center;
        p.Children.Add(value);
        if (label != null)
        {
            var l = V.Text(label, 8, FontWeights.Medium, V.White(0.4));
            l.HorizontalAlignment = HorizontalAlignment.Center;
            p.Children.Add(l);
        }
        return p;
    }

    private static Grid CountdownRow(CountdownState c)
    {
        var text = V.Text(c.Text, 17, FontWeights.SemiBold, V.White(), mono: true);
        text.Opacity = c.IsRunning ? 1 : 0.55;
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(V.Icon(Glyphs.Timer, 14, V.White()));
        text.Margin = new Thickness(12, 0, 12, 0);
        Grid.SetColumn(text, 1);
        g.Children.Add(text);
        var meter = V.MeterBar(c.Progress, 5);
        Grid.SetColumn(meter, 2);
        g.Children.Add(meter);
        if (!c.IsRunning)
        {
            var paused = V.Text(Strings.Paused, 10, FontWeights.Medium, V.White(0.5));
            paused.Margin = new Thickness(12, 0, 0, 0);
            Grid.SetColumn(paused, 3);
            g.Children.Add(paused);
        }
        return g;
    }

    private void NowPlayingRow(IslandModel model, NowPlaying track, double width, double innerHeight)
    {
        var cover = ExpandedMediaMetrics.ArtworkFrame(innerHeight);
        var art = V.Artwork(track.Artwork, ExpandedMediaMetrics.ArtworkSide, 8);
        V.Place(Expanded, art, cover.X, cover.Y);
        if (model.HoveredControl is IslandControl.Artwork)
            V.Place(Expanded, new Border { CornerRadius = new CornerRadius(8), Background = V.White(0.22) }, cover.X, cover.Y, cover.Width, cover.Height);

        var column = ExpandedMediaMetrics.TextColumnWidth(width);
        if (_marquee == null || _marquee.Value != track.Title || Math.Abs(_marquee.Width - column) > 0.5)
            _marquee = new Marquee(track.Title, 12, FontWeights.SemiBold, V.White(), column);
        var text = new StackPanel { Width = column, ClipToBounds = true };
        V.Detach(_marquee);
        text.Children.Add(_marquee);
        var artist = V.Text(track.Artist, 10, FontWeights.Normal, V.White(0.55));
        artist.Margin = new Thickness(0, 2, 0, 0);
        text.Children.Add(artist);
        text.Measure(new Size(column, double.PositiveInfinity));
        V.Place(Expanded, text, ExpandedMediaMetrics.HorizontalPadding + ExpandedMediaMetrics.ArtworkSide + ExpandedMediaMetrics.ArtworkGap,
            (innerHeight - text.DesiredSize.Height) / 2);

        foreach (var (kind, frame) in ExpandedMediaMetrics.TransportFrames(width, innerHeight))
        {
            var hovered = model.HoveredControl is IslandControl.Transport t && t.Kind == kind;
            V.Place(Expanded, V.TransportGlyph(TransportGlyph(kind, track.IsPlaying), kind == TransportKind.PlayPause ? 14 : 12, hovered),
                frame.X, frame.Y, frame.Width, frame.Height);
        }
    }

    private static string TransportGlyph(TransportKind kind, bool playing) => kind switch
    {
        TransportKind.Previous => Glyphs.Previous,
        TransportKind.Next => Glyphs.Next,
        _ => playing ? Glyphs.Pause : Glyphs.Play,
    };

    // MARK: Kontrol Merkezi

    public void BuildControlCenter(IslandModel model, double width, double innerHeight, ControlCenterSections sections)
    {
        var cc = ControlCenter;
        cc.Children.Clear();
        cc.Width = width;
        cc.Height = innerHeight;
        _seekFill = null;
        var pad = ControlCenterMetrics.HorizontalPadding;
        var hovered = model.HoveredControl;

        // ÇALIYOR
        V.Place(cc, V.Header(Strings.NowPlaying), pad, 0);
        var mediaTop = ControlCenterMetrics.RowTop(CCSection.Media, sections) ?? 0;
        var artFrame = ControlCenterMetrics.ArtworkFrame(sections)!.Value;
        if (model.NowPlaying is { } track)
        {
            V.Place(cc, V.Artwork(track.Artwork, ControlCenterMetrics.MediaArtworkSide, 9), artFrame.X, artFrame.Y);
            if (hovered is IslandControl.Artwork)
                V.Place(cc, new Border { CornerRadius = new CornerRadius(9), Background = V.White(0.22) }, artFrame.X, artFrame.Y, artFrame.Width, artFrame.Height);
            var textX = pad + ControlCenterMetrics.MediaArtworkSide + 12;
            var textW = Math.Max(0, width - textX - pad - ControlCenterMetrics.TransportWidth - 12);
            var lines = new StackPanel { Width = textW };
            lines.Children.Add(V.Text(track.Title, 13, FontWeights.SemiBold, V.White()));
            var artist = V.Text(track.Artist, 11, FontWeights.Normal, V.White(0.55));
            artist.Margin = new Thickness(0, 3, 0, 0);
            lines.Children.Add(artist);
            var source = V.Text(track.SourceName, 9, FontWeights.Medium, V.White(0.35));
            source.Margin = new Thickness(0, 3, 0, 0);
            lines.Children.Add(source);
            lines.Measure(new Size(textW, double.PositiveInfinity));
            V.Place(cc, lines, textX, mediaTop + (ControlCenterMetrics.MediaRowHeight - lines.DesiredSize.Height) / 2);

            if (track.HasProgress && ControlCenterMetrics.MediaSeekFrame(width, sections) is { } bar)
                SeekBar(cc, track, bar, hovered is IslandControl.Seek);
        }
        else
        {
            V.Place(cc, V.Artwork(null, 44, 9), artFrame.X, artFrame.Y);
            var none = V.Text(Strings.NothingPlaying, 12, FontWeights.Normal, V.White(0.4));
            none.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            V.Place(cc, none, pad + 44 + 12, mediaTop + (ControlCenterMetrics.MediaRowHeight - none.DesiredSize.Height) / 2);
        }
        foreach (var (kind, frame) in ControlCenterMetrics.TransportFrames(width, sections))
        {
            var isHovered = hovered is IslandControl.Transport t && t.Kind == kind;
            var glyph = V.TransportGlyph(TransportGlyph(kind, model.NowPlaying?.IsPlaying ?? false), kind == TransportKind.PlayPause ? 15 : 13, isHovered);
            glyph.Opacity = model.NowPlaying == null ? 0.3 : 1;
            V.Place(cc, glyph, frame.X, frame.Y, frame.Width, frame.Height);
        }

        if (sections.Calendar) CalendarSection(cc, model, width, sections);
        if (sections.Timer) TimerSection(cc, model, width, sections, hovered);
        if (sections.Shelf) ShelfSection(cc, model, width, sections, hovered);

        // SİSTEM
        V.Place(cc, V.Header(Strings.System), pad, ControlCenterMetrics.HeaderTop(CCSection.System, sections) ?? 0);
        var tiles = model.SystemTiles;
        var frames = ControlCenterMetrics.TileFrames(width, tiles.Count, sections);
        for (var i = 0; i < tiles.Count && i < frames.Count; i++)
            V.Place(cc, Tile(model, tiles[i], hovered is IslandControl.Tile tt && tt.Kind == tiles[i]), frames[i].X, frames[i].Y, frames[i].Width, frames[i].Height);
    }

    private void SeekBar(Canvas cc, NowPlaying track, Rect bar, bool hovered)
    {
        var track01 = new Border { CornerRadius = new CornerRadius(1.5), Background = V.White(0.18) };
        var fill = new Border
        {
            CornerRadius = new CornerRadius(1.5),
            Background = V.White(hovered ? 1 : 0.75),
            HorizontalAlignment = HorizontalAlignment.Left,
            Width = bar.Width * (track.Progress ?? 0),
        };
        var g = new Grid { RenderTransformOrigin = new Point(0.5, 0.5) };
        if (hovered) g.RenderTransform = new ScaleTransform(1, 1.8);
        g.Children.Add(track01);
        g.Children.Add(fill);
        V.Place(cc, g, bar.X, bar.Y, bar.Width, bar.Height);
        _seekFill = fill;
        _seekElapsed = V.Text(Clock(track.ElapsedNow), 9, FontWeights.Medium, V.White(0.45), mono: true);
        _seekRemaining = V.Text(Clock(track.Duration - (track.ElapsedNow ?? 0), negative: true), 9, FontWeights.Medium, V.White(0.45), mono: true);
        V.Place(cc, _seekElapsed, bar.X, bar.Bottom + 4);
        _seekRemaining.TextAlignment = TextAlignment.Right;
        V.Place(cc, _seekRemaining, bar.Right - 60, bar.Bottom + 4, 60);
    }

    /// <summary>Oynatma kafası saatten ileri sarılır; bütün Kontrol Merkezi'ni yeniden kurmadan.</summary>
    public void TickSeek(NowPlaying? track, double barWidth)
    {
        if (_seekFill == null || track == null) return;
        _seekFill.Width = barWidth * (track.Progress ?? 0);
        if (_seekElapsed != null) _seekElapsed.Text = Clock(track.ElapsedNow);
        if (_seekRemaining != null) _seekRemaining.Text = Clock(track.Duration - (track.ElapsedNow ?? 0), negative: true);
    }

    private static string Clock(double? seconds, bool negative = false)
    {
        if (seconds is not { } s || double.IsNaN(s) || s < 0) return "";
        var total = (int)Math.Round(s, MidpointRounding.AwayFromZero);
        int h = total / 3600, m = total % 3600 / 60, sec = total % 60;
        var sign = negative ? "-" : "";
        return h > 0 ? $"{sign}{h}:{m:00}:{sec:00}" : $"{sign}{m}:{sec:00}";
    }

    private static void CalendarSection(Canvas cc, IslandModel model, double width, ControlCenterSections sections)
    {
        V.Place(cc, V.Header(Strings.UpNext), ControlCenterMetrics.HorizontalPadding, ControlCenterMetrics.HeaderTop(CCSection.Calendar, sections) ?? 0);
        if (model.UpcomingEvent is not { } ev) return;
        var frame = ControlCenterMetrics.CalendarRowFrame(width, sections);
        var right = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        var time = V.Text(ev.TimeText, 12, FontWeights.SemiBold, V.White(), mono: true);
        time.HorizontalAlignment = HorizontalAlignment.Right;
        right.Children.Add(time);
        var rel = V.Text(ev.RelativeText, 10, FontWeights.Normal, V.White(0.5));
        rel.HorizontalAlignment = HorizontalAlignment.Right;
        rel.Margin = new Thickness(0, 2, 0, 0);
        right.Children.Add(rel);
        var row = ThreeColumns(V.Icon(Glyphs.Calendar, 14, V.White(0.8)), 20, TwoLines(ev.Title, ev.Location, 0.45), right);
        V.Place(cc, row, frame.X, frame.Y, frame.Width, frame.Height);
    }

    private static void TimerSection(Canvas cc, IslandModel model, double width, ControlCenterSections sections, IslandControl? hovered)
    {
        V.Place(cc, V.Header(Strings.Timer), ControlCenterMetrics.HorizontalPadding, ControlCenterMetrics.HeaderTop(CCSection.Timer, sections) ?? 0);
        if (model.Countdown is { } c)
        {
            var readout = ControlCenterMetrics.TimerReadoutFrame(width, sections);
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var text = V.Text(c.Text, 17, FontWeights.SemiBold, V.White(), mono: true);
            text.Opacity = c.IsRunning ? 1 : 0.55;
            text.Margin = new Thickness(0, 0, 12, 0);
            g.Children.Add(text);
            var meter = V.MeterBar(c.Progress, 4);
            Grid.SetColumn(meter, 1);
            g.Children.Add(meter);
            V.Place(cc, g, readout.X, readout.Y, readout.Width, readout.Height);
            foreach (var (action, frame) in ControlCenterMetrics.TimerControlFrames(width, sections))
            {
                var glyph = action switch
                {
                    TimerAction.Toggle => c.IsRunning ? Glyphs.Pause : Glyphs.Play,
                    TimerAction.Restart => Glyphs.Restart,
                    _ => Glyphs.Close,
                };
                var isHovered = hovered is IslandControl.Timer t && t.Action == action;
                V.Place(cc, V.TransportGlyph(glyph, action is TimerAction.Toggle ? 14 : 12, isHovered), frame.X, frame.Y, frame.Width, frame.Height);
            }
        }
        else
        {
            foreach (var (minutes, frame) in ControlCenterMetrics.TimerPresetFrames(sections))
            {
                var isHovered = hovered is IslandControl.Timer { Action: TimerAction.Start s } && s.Minutes == minutes;
                var label = V.Text(Strings.MinutesShort(minutes), 11, FontWeights.Medium, V.White(isHovered ? 1 : 0.8));
                label.HorizontalAlignment = HorizontalAlignment.Center;
                var preset = new Border { CornerRadius = new CornerRadius(9), Background = V.White(isHovered ? 0.18 : 0.10), Child = label };
                V.Place(cc, preset, frame.X, frame.Y, frame.Width, frame.Height);
            }
        }
    }

    private static void ShelfSection(Canvas cc, IslandModel model, double width, ControlCenterSections sections, IslandControl? hovered)
    {
        var header = model.ShelfSelection.Count == 0
            ? Strings.Shelf
            : $"{Strings.Shelf} · {Strings.SelectedCount(model.ShelfSelection.Count)}";
        V.Place(cc, V.Header(header), ControlCenterMetrics.HorizontalPadding, ControlCenterMetrics.HeaderTop(CCSection.Shelf, sections) ?? 0);

        foreach (var (action, frame) in ControlCenterMetrics.ShelfActionFrames(width, sections))
        {
            var title = action switch { ShelfAction.CopyAll => Strings.Copy, ShelfAction.ShareAll => Strings.Share, _ => Strings.Clear };
            var isHovered = hovered is IslandControl.Shelf s && s.Action == action;
            var label = V.Text(title, 10, FontWeights.Medium, V.White(isHovered ? 1 : 0.5));
            label.TextAlignment = TextAlignment.Right;
            V.Place(cc, label, frame.X, frame.Y, frame.Width, frame.Height);
        }

        var chips = ControlCenterMetrics.ShelfChipFrames(model.Shelf.Count, sections);
        for (var i = 0; i < chips.Count; i++)
        {
            var item = model.Shelf[i];
            var isHovered = hovered is IslandControl.Shelf { Action: ShelfAction.Open o } && o.Index == i
                         || hovered is IslandControl.Shelf { Action: ShelfAction.Remove r } && r.Index == i;
            var selected = model.ShelfSelection.Contains(item.Id);
            V.Place(cc, Chip(item, isHovered, selected), chips[i].X, chips[i].Y, chips[i].Width, chips[i].Height);
            if (isHovered)
            {
                var remove = ControlCenterMetrics.ShelfRemoveFrame(chips[i]);
                var removeHovered = hovered is IslandControl.Shelf { Action: ShelfAction.Remove rr } && rr.Index == i;
                var badge = new Grid();
                badge.Children.Add(new Ellipse { Fill = V.White(removeHovered ? 1 : 0.75) });
                badge.Children.Add(V.Icon(Glyphs.Close, 7, new SolidColorBrush(Color.FromArgb(217, 0, 0, 0))));
                V.Place(cc, badge, remove.X, remove.Y, remove.Width, remove.Height);
            }
        }
    }

    private static Border Chip(ShelfItem item, bool hovered, bool selected)
    {
        var p = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var icon = new Image { Source = FileIcons.For(item.Path), Width = 26, Height = 26, HorizontalAlignment = HorizontalAlignment.Center };
        p.Children.Add(icon);
        var name = V.Text(MiddleTruncate(item.Name, 11), 9, FontWeights.Normal, V.White(selected ? 1 : 0.75));
        name.HorizontalAlignment = HorizontalAlignment.Center;
        name.Margin = new Thickness(0, 4, 0, 0);
        p.Children.Add(name);
        return new Border
        {
            CornerRadius = new CornerRadius(10),
            Background = V.White(selected ? 0.22 : hovered ? 0.16 : 0.08),
            BorderBrush = V.White(selected ? 0.9 : 0),
            BorderThickness = new Thickness(1.5),
            Padding = new Thickness(4, 0, 4, 0),
            Child = p,
        };
    }

    /// <summary>"çok-uzun-dosya-adı.pdf" → "çok-u…ı.pdf" (macOS'taki .middle kırpma).</summary>
    private static string MiddleTruncate(string s, int max)
    {
        if (s.Length <= max) return s;
        var head = (max - 1) / 2;
        var tail = max - 1 - head;
        return s[..head] + "…" + s[^tail..];
    }

    private static Border Tile(IslandModel model, SystemTile tile, bool active)
    {
        var device = model.Devices.FirstOrDefault(d => d.Headline != null);
        var (glyph, value, meter) = tile switch
        {
            SystemTile.Volume => (Glyphs.Volume(model.Volume ?? 0, false), (model.Volume ?? 0).PercentText(), model.Volume ?? 0),
            SystemTile.Brightness => (Glyphs.Brightness, (model.Brightness ?? 0).PercentText(), model.Brightness ?? 0),
            SystemTile.Battery => (Glyphs.Battery(model.Power?.Percentage ?? 0, model.Power?.IsCharging ?? false),
                                   $"{model.Power?.Percentage ?? 0}%", (model.Power?.Percentage ?? 0) / 100.0),
            _ => (Glyphs.Headphones, device?.Headline is { } h ? $"{h}%" : "—", (device?.Headline ?? 0) / 100.0),
        };
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var head = V.Row(5, V.Icon(glyph, 11, V.White(0.75)), V.Text(value, 11, FontWeights.Medium, V.White(), mono: true));
        head.HorizontalAlignment = HorizontalAlignment.Left;
        stack.Children.Add(head);
        var bar = V.MeterBar(meter, tile.IsAdjustable() ? 6 : 5);
        bar.Margin = new Thickness(0, 8, 0, 0);
        stack.Children.Add(bar);
        return new Border
        {
            CornerRadius = new CornerRadius(10),
            Background = V.White(active && tile.IsAdjustable() ? 0.15 : 0.08),
            Padding = new Thickness(ControlCenterMetrics.TileInset, 0, ControlCenterMetrics.TileInset, 0),
            Child = stack,
        };
    }

    // MARK: Bırakma alanı

    public void BuildDropZone(bool highlighted, int fileCount, double width, double innerHeight)
    {
        var dz = DropZone;
        dz.Children.Clear();
        dz.Width = width;
        dz.Height = innerHeight;

        V.Place(dz, new Rectangle
        {
            RadiusX = 16,
            RadiusY = 16,
            Stroke = V.White(highlighted ? 0.55 : 0.25),
            StrokeThickness = 1.5,
            StrokeDashArray = new DoubleCollection { 4, 3.3 },
        }, 10, 10, width - 20, innerHeight - 20);

        var column = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var icon = V.Icon(Glyphs.Download, 26, V.White(highlighted ? 1 : 0.8));
        if (highlighted) icon.RenderTransform = new ScaleTransform(1.12, 1.12, 13, 13);
        column.Children.Add(icon);
        var label = V.Text(highlighted ? Strings.ReleaseToKeep : Strings.DropFilesHere, 12, FontWeights.SemiBold, V.White());
        label.HorizontalAlignment = HorizontalAlignment.Center;
        label.Margin = new Thickness(0, 8, 0, 0);
        column.Children.Add(label);
        if (fileCount > 0)
        {
            var count = V.Text(Strings.Files(fileCount), 10, FontWeights.Normal, V.White(0.5));
            count.HorizontalAlignment = HorizontalAlignment.Center;
            count.Margin = new Thickness(0, 8, 0, 0);
            column.Children.Add(count);
        }
        var host = new Grid { Width = width, Height = innerHeight };
        host.Children.Add(column);
        V.Place(dz, host, 0, 0);
    }

    private static string Duration(int minutes) => Strings.Duration(minutes / 60, minutes % 60);

    private static string Bytes(long count)
    {
        string[] units = { "KB", "MB", "GB" };
        double v = count / 1000.0;
        var i = 0;
        while (v >= 1000 && i < units.Length - 1) { v /= 1000; i++; }
        return v.ToString(v < 10 ? "0.0" : "0", Localization.Culture) + " " + units[i];
    }
}

/// <summary>Dosya simgeleri (Gezgin'in gösterdiği), yol başına bir kez okunur.</summary>
public static class FileIcons
{
    private static readonly Dictionary<string, BitmapSource?> Cache = new(StringComparer.OrdinalIgnoreCase);

    public static BitmapSource? For(string path)
    {
        if (Cache.TryGetValue(path, out var cached)) return cached;
        BitmapSource? image = null;
        try
        {
            var info = new Monitors.Native.SHFILEINFO();
            Monitors.Native.SHGetFileInfo(path, 0, ref info, (uint)System.Runtime.InteropServices.Marshal.SizeOf(info),
                Monitors.Native.SHGFI_ICON | Monitors.Native.SHGFI_LARGEICON);
            if (info.hIcon != IntPtr.Zero)
            {
                image = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(info.hIcon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                image.Freeze();
                Monitors.Native.DestroyIcon(info.hIcon);
            }
        }
        catch { }
        return Cache[path] = image;
    }
}
