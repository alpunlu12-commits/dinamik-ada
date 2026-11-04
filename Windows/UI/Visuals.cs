using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using Typography = System.Windows.Documents.Typography;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using DinamikAda.Core;
using Localization = DinamikAda.Core.Localization;

namespace DinamikAda.UI;

/// <summary>Adanın küçük görsel parçaları (macOS'taki IslandComponents).</summary>
public static class V
{
    public static readonly FontFamily Ui = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    private static readonly Dictionary<int, SolidColorBrush> WhiteCache = new();

    /// <summary>Beyazın verilen opaklıkta dondurulmuş fırçası.</summary>
    public static SolidColorBrush White(double opacity = 1)
    {
        var a = (int)Math.Round(Math.Clamp(opacity, 0, 1) * 255);
        if (WhiteCache.TryGetValue(a, out var b)) return b;
        b = new SolidColorBrush(Color.FromArgb((byte)a, 255, 255, 255));
        b.Freeze();
        return WhiteCache[a] = b;
    }

    public static SolidColorBrush Brush(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    public static readonly SolidColorBrush Green = Brush(Color.FromRgb(0x30, 0xD1, 0x58));
    public static readonly SolidColorBrush Orange = Brush(Color.FromRgb(0xFF, 0x9F, 0x0A));
    public static readonly SolidColorBrush CameraGreen = Brush(Color.FromRgb(51, 199, 89));
    public static readonly SolidColorBrush MicOrange = Brush(Color.FromRgb(255, 158, 10));

    public static TextBlock Text(string text, double size, FontWeight weight, Brush brush, bool mono = false)
    {
        var t = new TextBlock
        {
            Text = text,
            FontFamily = Ui,
            FontSize = size,
            FontWeight = weight,
            Foreground = brush,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (mono) Typography.SetNumeralAlignment(t, FontNumeralAlignment.Tabular);
        return t;
    }

    public static TextBlock Icon(string glyph, double size, Brush brush) => new()
    {
        Text = glyph,
        FontFamily = Icons,
        FontSize = size,
        Foreground = brush,
        VerticalAlignment = VerticalAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Center,
        TextAlignment = TextAlignment.Center,
    };

    /// <summary>Öğeyi bir Canvas'a mutlak konumda yerleştirir.</summary>
    public static T Place<T>(Canvas parent, T element, double x, double y, double w = double.NaN, double h = double.NaN) where T : FrameworkElement
    {
        Detach(element);
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
        if (!double.IsNaN(w)) element.Width = Math.Max(0, w);
        if (!double.IsNaN(h)) element.Height = Math.Max(0, h);
        parent.Children.Add(element);
        return element;
    }

    /// <summary>Yeniden kullanılan bir öğeyi eski ebeveyninden çıkarır.</summary>
    public static void Detach(FrameworkElement e)
    {
        switch (e.Parent)
        {
            case Panel p: p.Children.Remove(e); break;
            case Decorator d: d.Child = null; break;
            case ContentControl c: c.Content = null; break;
        }
    }

    /// <summary>Yatay dizi, ortalı.</summary>
    public static StackPanel Row(double spacing, params FrameworkElement[] items)
    {
        var p = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        for (var i = 0; i < items.Length; i++)
        {
            if (i > 0) items[i].Margin = new Thickness(spacing, items[i].Margin.Top, items[i].Margin.Right, items[i].Margin.Bottom);
            p.Children.Add(items[i]);
        }
        return p;
    }

    /// <summary>Kapsül metre: sönük iz üzerinde beyaz dolgu.</summary>
    public static Grid MeterBar(double value, double height = 6)
    {
        var g = new Grid { Height = height, VerticalAlignment = VerticalAlignment.Center };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(value.Unit(), 0.0001), GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(1 - value.Unit(), 0.0001), GridUnitType.Star) });
        var track = new Border { CornerRadius = new CornerRadius(height / 2), Background = White(0.16) };
        Grid.SetColumnSpan(track, 2);
        g.Children.Add(track);
        g.Children.Add(new Border { CornerRadius = new CornerRadius(height / 2), Background = White(), MinWidth = height });
        return g;
    }

    /// <summary>Albüm kapağı ya da yer tutucu nota.</summary>
    public static Border Artwork(BitmapSource? image, double side, double radius)
    {
        var b = new Border
        {
            Width = side,
            Height = side,
            CornerRadius = new CornerRadius(radius),
            Background = White(0.12),
            ClipToBounds = true,
        };
        if (image != null)
        {
            b.Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill };
        }
        else
        {
            b.Child = Icon(Glyphs.Music, side * 0.42, White(0.5));
        }
        return b;
    }

    /// <summary>Hover satırındaki "simge + değer" çipi.</summary>
    public static Border StatChip(string glyph, string value)
    {
        var icon = Icon(glyph, 11, White(0.75));
        icon.Width = 14;
        return new Border
        {
            Height = 26,
            CornerRadius = new CornerRadius(13),
            Background = White(0.10),
            Padding = new Thickness(10, 0, 10, 0),
            Child = Row(6, icon, Text(value, 11, FontWeights.Medium, White(), mono: true)),
        };
    }

    /// <summary>Oynat/atla düğmesi; imleç üstündeyken daire içinde aydınlanır.</summary>
    public static Grid TransportGlyph(string glyph, double size, bool hovered)
    {
        var g = new Grid();
        g.Children.Add(new Ellipse { Fill = White(hovered ? 0.14 : 0) });
        g.Children.Add(Icon(glyph, size, White(hovered ? 1 : 0.8)));
        return g;
    }

    /// <summary>Kamera (yeşil) ve mikrofon (turuncu) — Windows/macOS gösterge renkleri.</summary>
    public static StackPanel PrivacyDots(bool camera, bool microphone)
    {
        var items = new List<FrameworkElement>();
        if (camera) items.Add(Icon(Glyphs.Camera, 9, CameraGreen));
        if (microphone) items.Add(Icon(Glyphs.Microphone, 9, MicOrange));
        var p = Row(5, items.ToArray());
        p.HorizontalAlignment = HorizontalAlignment.Center;
        return p;
    }

    /// <summary>Raf doluyken tepsi simgesi ve sayı rozeti.</summary>
    public static Grid ShelfAccessory(int count)
    {
        var g = new Grid { Width = 22, Height = 20, HorizontalAlignment = HorizontalAlignment.Center };
        g.Children.Add(Icon(Glyphs.Tray, 12, White(0.85)));
        var badge = new Border
        {
            Width = 11,
            Height = 11,
            CornerRadius = new CornerRadius(5.5),
            Background = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Child = new TextBlock
            {
                Text = count.ToString(),
                FontFamily = Ui,
                FontSize = 7.5,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.Black,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        g.Children.Add(badge);
        return g;
    }

    /// <summary>Başlık ("ÇALIYOR", "SİSTEM") — yerel ayara göre büyük harf.</summary>
    public static TextBlock Header(string title) =>
        Text(Localization.Upper(title), 9, FontWeights.SemiBold, White(0.4));
}

/// <summary>
/// Kompakt pildeki dört çubuklu dalga formu. Çalarken çubuklar ayrı hızlarda
/// iner çıkar; duraklatılınca donar. Renkler kapak paletinden, çubuklar boyunca geçerek.
/// </summary>
public sealed class Waveform : StackPanel
{
    private static readonly (double Low, double High)[] Bars = { (4, 12), (7, 16), (5, 10), (9, 14) };
    public bool Playing { get; }
    public ArtworkPalette Palette { get; }

    public Waveform(bool playing, ArtworkPalette palette)
    {
        Playing = playing;
        Palette = palette;
        Orientation = Orientation.Horizontal;
        Height = 16;
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;
        for (var i = 0; i < Bars.Length; i++)
        {
            var color = palette.ColorAt(Bars.Length > 1 ? i / (double)(Bars.Length - 1) : 0);
            var bar = new Rectangle
            {
                Width = 2.5,
                Height = Bars[i].Low,
                RadiusX = 1.25,
                RadiusY = 1.25,
                Fill = V.Brush(color),
                Margin = new Thickness(i == 0 ? 0 : 2.5, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Children.Add(bar);
            if (playing)
            {
                var a = new DoubleAnimation(Bars[i].Low, Bars[i].High, TimeSpan.FromSeconds(0.42 + i * 0.06))
                {
                    AutoReverse = true,
                    RepeatBehavior = RepeatBehavior.Forever,
                    EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
                };
                bar.BeginAnimation(HeightProperty, a);
            }
        }
    }
}

/// <summary>Kameranın solundaki indirme göstergesi: aşağı kayan ok ve taban çizgisi.</summary>
public sealed class DownloadAccessory : Grid
{
    public DownloadAccessory(double side = 18)
    {
        Width = side;
        Height = side;
        ClipToBounds = true;
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;
        var arrow = V.Icon(Glyphs.Of(0xE74B), 8, V.White());   // aşağı ok
        arrow.VerticalAlignment = VerticalAlignment.Top;
        var shift = new TranslateTransform();
        arrow.RenderTransform = shift;
        Children.Add(arrow);
        Children.Add(new Rectangle
        {
            Width = side * 0.62,
            Height = 1.8,
            RadiusX = 0.9,
            RadiusY = 0.9,
            Fill = V.White(0.85),
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 2),
        });
        var duration = TimeSpan.FromSeconds(0.9);
        shift.BeginAnimation(TranslateTransform.YProperty,
            new DoubleAnimation(-2, 5, duration) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn } });
        arrow.BeginAnimation(OpacityProperty,
            new DoubleAnimation(1, 0, duration) { RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn } });
    }
}

/// <summary>
/// Sığmayan metni kaydıran tek satır. Sığıyorsa hiç kımıldamaz. İki kopya
/// arasında boşluk bırakılıp tam bir kopya kadar kaydırılır, dikiş görünmez;
/// uçlar maske ile adanın siyahına karışır.
/// </summary>
public sealed class Marquee : Canvas
{
    public string Value { get; }
    private const double Speed = 26, Gap = 44, InitialDelay = 1.4, Fade = 10;

    public Marquee(string text, double fontSize, FontWeight weight, Brush brush, double width)
    {
        Value = text;
        Width = width;
        Height = fontSize * 1.45;
        ClipToBounds = true;

        var first = V.Text(text, fontSize, weight, brush);
        first.TextTrimming = TextTrimming.None;
        first.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var textWidth = first.DesiredSize.Width;

        if (textWidth <= width + 0.5)
        {
            Children.Add(first);
            return;
        }

        var strip = new StackPanel { Orientation = Orientation.Horizontal };
        strip.Children.Add(first);
        var second = V.Text(text, fontSize, weight, brush);
        second.TextTrimming = TextTrimming.None;
        second.Margin = new Thickness(Gap, 0, 0, 0);
        strip.Children.Add(second);
        Children.Add(strip);

        var inset = Fade / Math.Max(width, 1);
        OpacityMask = new LinearGradientBrush(new GradientStopCollection
        {
            new(Colors.Transparent, 0), new(Colors.Black, Math.Min(inset, 0.5)),
            new(Colors.Black, Math.Max(1 - inset, 0.5)), new(Colors.Transparent, 1),
        }, new Point(0, 0), new Point(1, 0));

        var distance = textWidth + Gap;
        var shift = new TranslateTransform();
        strip.RenderTransform = shift;
        // Gecikme yalnızca başta bir kez; sonra kesintisiz döngü.
        shift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, -distance, TimeSpan.FromSeconds(distance / Speed))
        {
            BeginTime = TimeSpan.FromSeconds(InitialDelay),
            RepeatBehavior = RepeatBehavior.Forever,
        });
    }
}
