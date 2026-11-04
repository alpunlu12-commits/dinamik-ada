using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using DinamikAda.Core;

namespace DinamikAda.Island;

/// <summary>
/// Windows'ta notch yok: ada her zaman ekranın üst ortasında, macOS sürümünün
/// "simüle notch" modundaki gibi bir pil olarak çizilir. Ölçüler aynı.
/// </summary>
public sealed record NotchMetrics(double NotchWidth, double NotchHeight)
{
    public static NotchMetrics For(IslandSize size) => new(size == IslandSize.Small ? 180 : 210, 32);
}

/// <summary>Bir denetimin geometrisi, pencere koordinatlarında (DIP, y aşağı).</summary>
public sealed record IslandControlHit(IslandControl Control, Rect HitRect, Rect ValueRect)
{
    /// <summary>Değer alan denetimler için imleç konumundan 0…1.</summary>
    public double Fraction(Point p) => ValueRect.Width > 0 ? ((p.X - ValueRect.Left) / ValueRect.Width).Unit() : 0;
}

/// <summary>
/// Geometrinin tek doğruluk kaynağı. Görünüm denetimleri buradan konumlandırır,
/// tıklama dikdörtgenleri de aynı çağrılardan türetilir — gördüğün düğme ile
/// basabildiğin düğme ayrışamaz.
/// </summary>
public sealed record IslandLayout(NotchMetrics Metrics, IslandSize Size, ControlCenterSections Sections,
                                  ExpandedPayloadKind ExpandedPayload)
{
    /// <summary>Gölgenin kırpılmaması için panelin iki yanına ve altına eklenen pay.</summary>
    public const double ShadowPadding = 28;

    /// <summary>En geniş kompakt aksesuar çifti; panel bir kez, en geniş hâle göre ölçülür.</summary>
    public const double MaxAccessoryWidth = 96;

    public double NotchHeight => Math.Max(Metrics.NotchHeight, 28);

    public Size CompactSize(CompactAccessories accessories) =>
        new(Math.Max(Metrics.NotchWidth, 120) + accessories.TotalWidth, NotchHeight);

    public Size ExpandedSize
    {
        get
        {
            var width = ExpandedPayload.Width * (Size == IslandSize.Small ? 0.88 : 1);
            return new(Math.Max(width, CompactSize(CompactAccessories.None).Width + 40),
                       NotchHeight + ExpandedPayload.InnerHeight);
        }
    }

    public Size ControlCenterSize =>
        new(Size == IslandSize.Small ? 400 : 460, NotchHeight + ControlCenterMetrics.ContentHeight(Sections));

    public Size DropZoneSize => new(Size == IslandSize.Small ? 380 : 440, NotchHeight + 132);

    public Size SizeFor(IslandState state, CompactAccessories accessories) => state switch
    {
        IslandState.Compact => CompactSize(accessories),
        IslandState.Expanded => ExpandedSize,
        IslandState.ControlCenter => ControlCenterSize,
        _ => DropZoneSize,
    };

    /// <summary>
    /// Üst köşeler dışa açılır (ekranın üst kenarı genişliyormuş gibi). Kompakt ve
    /// yalın pilde sıfır: o zaman ada hiçbir şeyin üstüne açılmıyor.
    /// </summary>
    public double TopRadius(IslandState state, CompactAccessories? accessories = null) =>
        state != IslandState.Compact ? 10 : (accessories?.IsEmpty ?? true) ? 0 : 8;

    public double BottomRadius(IslandState state) => state switch
    {
        IslandState.Compact => Math.Min(NotchHeight / 2, 14),
        IslandState.Expanded => 22,
        IslandState.ControlCenter => 28,
        _ => 26,
    };

    private Size MaxSize
    {
        get
        {
            var compact = new Size(Math.Max(Metrics.NotchWidth, 120) + MaxAccessoryWidth, NotchHeight);
            var widths = new[] { compact.Width, ExpandedPayloadKind.MaxWidth, ControlCenterSize.Width, DropZoneSize.Width };
            var heights = new[] { compact.Height, NotchHeight + ExpandedPayloadKind.MaxInnerHeight, ControlCenterSize.Height, DropZoneSize.Height };
            return new(widths.Max(), heights.Max());
        }
    }

    /// <summary>Pencere boyutu (DIP): en büyük ada + gölge payı.</summary>
    public Size PanelSize => new(Math.Ceiling(MaxSize.Width + ShadowPadding * 2), Math.Ceiling(MaxSize.Height + ShadowPadding));

    /// <summary>
    /// Tek aksesuar varken pil, ortadaki şeridi yerinde tutacak kadar kaydırılır;
    /// yalnızca ihtiyaç duyulan tarafa büyür.
    /// </summary>
    public double CentreShift(IslandState state, CompactAccessories accessories) =>
        state != IslandState.Compact ? 0 : ((accessories.Trailing?.Width ?? 0) - (accessories.Leading?.Width ?? 0)) / 2;

    /// <summary>Adanın pencere içindeki dikdörtgeni.</summary>
    public Rect IslandRect(IslandState state, CompactAccessories accessories)
    {
        var size = SizeFor(state, accessories);
        return new Rect(PanelSize.Width / 2 - size.Width / 2 + CentreShift(state, accessories), 0, size.Width, size.Height);
    }

    private Rect ToWindow(Rect island, Rect frame) =>
        new(island.X + frame.X, NotchHeight + frame.Y, frame.Width, frame.Height);

    /// <summary>Genişlemiş Now Playing satırının düğmeleri.</summary>
    public List<IslandControlHit> ExpandedControlHits(CompactAccessories accessories)
    {
        var island = IslandRect(IslandState.Expanded, accessories);
        var inner = Math.Max(0, island.Height - NotchHeight);
        var hits = ExpandedMediaMetrics.TransportFrames(island.Width, inner)
            .Select(i => { var r = ToWindow(island, i.Frame); return new IslandControlHit(new IslandControl.Transport(i.Kind), r, r); })
            .ToList();
        var cover = ToWindow(island, ExpandedMediaMetrics.ArtworkFrame(inner));
        hits.Add(new IslandControlHit(new IslandControl.Artwork(), cover, cover));
        return hits;
    }

    /// <summary>
    /// Kontrol Merkezi'nin tıklama dikdörtgenleri, çizimle aynı ölçülerden.
    /// Sıra önemli: ilk eşleşen kazanır.
    /// </summary>
    public List<IslandControlHit> ControlHits(IReadOnlyList<SystemTile> tiles, bool hasMedia, CountdownState? countdown,
                                              int shelfCount, int? hoveredShelfIndex)
    {
        var island = IslandRect(IslandState.ControlCenter, CompactAccessories.None);
        Rect G(Rect f) => ToWindow(island, f);
        var hits = new List<IslandControlHit>();

        if (hasMedia && ControlCenterMetrics.ArtworkFrame(Sections) is { } cover)
        {
            var r = G(cover);
            hits.Add(new(new IslandControl.Artwork(), r, r));
        }
        // Sürgü başlıktan önce: 3 pt'lik çubuğun dikey büyütülmüş basma alanı başlık bloğuna uzanıyor.
        if (hasMedia && ControlCenterMetrics.MediaSeekFrame(island.Width, Sections) is { } bar)
        {
            var r = G(bar);
            var hit = r;
            hit.Inflate(0, 8);
            hits.Add(new(new IslandControl.Seek(), hit, r));
        }
        if (hasMedia)
        {
            foreach (var (kind, frame) in ControlCenterMetrics.TransportFrames(island.Width, Sections))
            {
                var r = G(frame);
                hits.Add(new(new IslandControl.Transport(kind), r, r));
            }
        }
        if (Sections.Timer)
        {
            if (countdown == null)
            {
                foreach (var (minutes, frame) in ControlCenterMetrics.TimerPresetFrames(Sections))
                {
                    var r = G(frame);
                    hits.Add(new(new IslandControl.Timer(new TimerAction.Start(minutes)), r, r));
                }
            }
            else
            {
                foreach (var (action, frame) in ControlCenterMetrics.TimerControlFrames(island.Width, Sections))
                {
                    var r = G(frame);
                    hits.Add(new(new IslandControl.Timer(action), r, r));
                }
            }
        }
        if (Sections.Shelf)
        {
            var chips = ControlCenterMetrics.ShelfChipFrames(shelfCount, Sections);
            for (var i = 0; i < chips.Count; i++)
            {
                // Kaldır rozeti yalnızca imleç çipin üstündeyken var; çipten önce test edilir.
                if (hoveredShelfIndex == i)
                {
                    var rr = G(ControlCenterMetrics.ShelfRemoveFrame(chips[i]));
                    hits.Add(new(new IslandControl.Shelf(new ShelfAction.Remove(i)), rr, rr));
                }
                var r = G(chips[i]);
                hits.Add(new(new IslandControl.Shelf(new ShelfAction.Open(i)), r, r));
            }
            foreach (var (action, frame) in ControlCenterMetrics.ShelfActionFrames(island.Width, Sections))
            {
                var r = G(frame);
                hits.Add(new(new IslandControl.Shelf(action), r, r));
            }
        }
        var tileFrames = ControlCenterMetrics.TileFrames(island.Width, tiles.Count, Sections);
        for (var i = 0; i < tiles.Count && i < tileFrames.Count; i++)
        {
            var r = G(tileFrames[i]);
            var value = r;
            value.Inflate(-ControlCenterMetrics.TileInset, 0);
            hits.Add(new(new IslandControl.Tile(tiles[i]), r, value));
        }
        return hits;
    }
}

/// <summary>Genişlemiş Now Playing satırının ölçüleri.</summary>
public static class ExpandedMediaMetrics
{
    public const double HorizontalPadding = 16;
    public const double ArtworkSide = 34;
    public const double TransportSide = 26;
    public const double TransportSpacing = 2;
    public static double TransportWidth => TransportSide * 3 + TransportSpacing * 2;
    public const double ArtworkGap = 12;
    public const double TransportGap = 10;

    public static Rect ArtworkFrame(double innerHeight) =>
        new(HorizontalPadding, (innerHeight - ArtworkSide) / 2, ArtworkSide, ArtworkSide);

    /// <summary>
    /// Metin sütunu açıkça hesaplanır, yığının çocuk ideallerine bırakılmaz:
    /// uzun bir parça adı kapağı ve düğmeleri satırdan dışarı itmesin.
    /// </summary>
    public static double TextColumnWidth(double islandWidth) =>
        Math.Max(0, islandWidth - HorizontalPadding - ArtworkSide - ArtworkGap - TransportWidth - HorizontalPadding - TransportGap);

    public static List<(TransportKind Kind, Rect Frame)> TransportFrames(double islandWidth, double innerHeight)
    {
        var top = (innerHeight - TransportSide) / 2;
        var x = islandWidth - HorizontalPadding - TransportWidth;
        var list = new List<(TransportKind, Rect)>();
        foreach (var k in new[] { TransportKind.Previous, TransportKind.PlayPause, TransportKind.Next })
        {
            list.Add((k, new Rect(x, top, TransportSide, TransportSide)));
            x += TransportSide + TransportSpacing;
        }
        return list;
    }
}

public enum CCSection { Media, Calendar, Timer, Shelf, System }

/// <summary>Kontrol Merkezi satırlarının ölçüleri (macOS sürümüyle aynı sayılar).</summary>
public static class ControlCenterMetrics
{
    public const double HorizontalPadding = 18;
    public const double HeaderHeight = 11;
    public const double HeaderSpacing = 8;
    public const double SectionSpacing = 16;
    public const double BottomMargin = 16;
    public const double MediaRowHeight = 46;
    public const double MediaProgressExtra = 26;
    public const double SeekBarHeight = 3;
    public const double CalendarRowHeight = 38;
    public const double TimerRowHeight = 34;
    public const double ShelfRowHeight = 54;
    public const double TileHeight = 56;
    public const double TileSpacing = 10;
    public const double TileInset = 10;
    public const double TransportSide = 28;
    public const double TransportSpacing = 4;
    public const double PresetWidth = 54;
    public const double PresetSpacing = 8;
    public const double ShelfChipWidth = 66;
    public const double ShelfChipSpacing = 8;
    public const double ShelfRemoveSide = 16;
    public const double ActionHeight = 16;
    public const double ActionSpacing = 12;
    public const double MediaArtworkSide = 44;
    public static readonly int[] Presets = { 5, 10, 25 };

    public static double RowHeight(CCSection s, ControlCenterSections sections) => s switch
    {
        CCSection.Media => MediaRowHeight + (sections.MediaProgress ? MediaProgressExtra : 0),
        CCSection.Calendar => CalendarRowHeight,
        CCSection.Timer => TimerRowHeight,
        CCSection.Shelf => ShelfRowHeight,
        _ => TileHeight,
    };

    public static List<CCSection> VisibleSections(ControlCenterSections sections)
    {
        var stack = new List<CCSection> { CCSection.Media };
        if (sections.Calendar) stack.Add(CCSection.Calendar);
        if (sections.Timer) stack.Add(CCSection.Timer);
        if (sections.Shelf) stack.Add(CCSection.Shelf);
        stack.Add(CCSection.System);
        return stack;
    }

    public static double? HeaderTop(CCSection section, ControlCenterSections sections)
    {
        double y = 0;
        foreach (var c in VisibleSections(sections))
        {
            if (c == section) return y;
            y += HeaderHeight + HeaderSpacing + RowHeight(c, sections) + SectionSpacing;
        }
        return null;
    }

    public static double? RowTop(CCSection section, ControlCenterSections sections) =>
        HeaderTop(section, sections) is { } h ? h + HeaderHeight + HeaderSpacing : null;

    public static double ContentHeight(ControlCenterSections sections)
    {
        var stack = VisibleSections(sections);
        var body = stack.Sum(s => HeaderHeight + HeaderSpacing + RowHeight(s, sections));
        return body + SectionSpacing * Math.Max(0, stack.Count - 1) + BottomMargin;
    }

    public static double TransportWidth => TransportSide * 3 + TransportSpacing * 2;

    public static List<(TransportKind Kind, Rect Frame)> TransportFrames(double islandWidth, ControlCenterSections sections)
    {
        var list = new List<(TransportKind, Rect)>();
        if (RowTop(CCSection.Media, sections) is not { } row) return list;
        var top = row + (MediaRowHeight - TransportSide) / 2;
        var x = islandWidth - HorizontalPadding - TransportWidth;
        foreach (var k in new[] { TransportKind.Previous, TransportKind.PlayPause, TransportKind.Next })
        {
            list.Add((k, new Rect(x, top, TransportSide, TransportSide)));
            x += TransportSide + TransportSpacing;
        }
        return list;
    }

    public static List<Rect> TileFrames(double islandWidth, int count, ControlCenterSections sections)
    {
        var list = new List<Rect>();
        if (count <= 0 || RowTop(CCSection.System, sections) is not { } top) return list;
        var available = islandWidth - HorizontalPadding * 2 - TileSpacing * (count - 1);
        var width = available / count;
        for (var i = 0; i < count; i++) list.Add(new Rect(HorizontalPadding + (width + TileSpacing) * i, top, width, TileHeight));
        return list;
    }

    public static List<(int Minutes, Rect Frame)> TimerPresetFrames(ControlCenterSections sections)
    {
        var list = new List<(int, Rect)>();
        if (RowTop(CCSection.Timer, sections) is not { } top) return list;
        for (var i = 0; i < Presets.Length; i++)
            list.Add((Presets[i], new Rect(HorizontalPadding + (PresetWidth + PresetSpacing) * i, top, PresetWidth, TimerRowHeight)));
        return list;
    }

    public static List<(TimerAction Action, Rect Frame)> TimerControlFrames(double islandWidth, ControlCenterSections sections)
    {
        var list = new List<(TimerAction, Rect)>();
        if (RowTop(CCSection.Timer, sections) is not { } row) return list;
        var side = TransportSide;
        var total = side * 3 + TransportSpacing * 2;
        var top = row + (TimerRowHeight - side) / 2;
        var x = islandWidth - HorizontalPadding - total;
        foreach (var a in new TimerAction[] { new TimerAction.Toggle(), new TimerAction.Restart(), new TimerAction.Cancel() })
        {
            list.Add((a, new Rect(x, top, side, side)));
            x += side + TransportSpacing;
        }
        return list;
    }

    public static Rect TimerReadoutFrame(double islandWidth, ControlCenterSections sections)
    {
        var row = RowTop(CCSection.Timer, sections) ?? 0;
        var controls = TransportSide * 3 + TransportSpacing * 2 + 12;
        return new Rect(HorizontalPadding, row, Math.Max(0, islandWidth - HorizontalPadding * 2 - controls), TimerRowHeight);
    }

    public static List<Rect> ShelfChipFrames(int count, ControlCenterSections sections)
    {
        var list = new List<Rect>();
        if (RowTop(CCSection.Shelf, sections) is not { } top) return list;
        for (var i = 0; i < count; i++)
            list.Add(new Rect(HorizontalPadding + (ShelfChipWidth + ShelfChipSpacing) * i, top, ShelfChipWidth, ShelfRowHeight));
        return list;
    }

    public static Rect ShelfRemoveFrame(Rect chip) =>
        new(chip.Right - ShelfRemoveSide + 2, chip.Top - 2, ShelfRemoveSide, ShelfRemoveSide);

    /// <summary>
    /// Kopyala / Paylaş / Temizle. Genişlikler tablodan değil, çizilecek metin
    /// ölçülerek bulunur: "Kopyala", "Copy" için ayrılan yere sığmıyordu.
    /// </summary>
    public static List<(ShelfAction Action, Rect Frame)> ShelfActionFrames(double islandWidth, ControlCenterSections sections)
    {
        var list = new List<(ShelfAction, Rect)>();
        if (HeaderTop(CCSection.Shelf, sections) is not { } header) return list;
        var labels = new (ShelfAction, string)[]
        {
            (new ShelfAction.CopyAll(), Strings.Copy), (new ShelfAction.ShareAll(), Strings.Share), (new ShelfAction.Clear(), Strings.Clear),
        };
        var widths = labels.Select(l => LabelWidth(l.Item2)).ToList();
        var total = widths.Sum() + ActionSpacing * (labels.Length - 1);
        var x = islandWidth - HorizontalPadding - total;
        for (var i = 0; i < labels.Length; i++)
        {
            list.Add((labels[i].Item1, new Rect(x, header - 3, widths[i], ActionHeight)));
            x += widths[i] + ActionSpacing;
        }
        return list;
    }

    public static double LabelWidth(string text)
    {
        var ft = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal),
            10, Brushes.White, 1.0);
        return Math.Ceiling(ft.WidthIncludingTrailingWhitespace) + 2;
    }

    public static Rect? MediaSeekFrame(double islandWidth, ControlCenterSections sections)
    {
        if (!sections.MediaProgress || RowTop(CCSection.Media, sections) is not { } row) return null;
        return new Rect(HorizontalPadding, row + MediaRowHeight + 4, islandWidth - HorizontalPadding * 2, SeekBarHeight);
    }

    public static Rect? ArtworkFrame(ControlCenterSections sections) =>
        RowTop(CCSection.Media, sections) is { } row
            ? new Rect(HorizontalPadding, row + (MediaRowHeight - MediaArtworkSide) / 2, MediaArtworkSide, MediaArtworkSide)
            : null;

    public static Rect CalendarRowFrame(double islandWidth, ControlCenterSections sections) =>
        new(HorizontalPadding, RowTop(CCSection.Calendar, sections) ?? 0, islandWidth - HorizontalPadding * 2, CalendarRowHeight);
}
