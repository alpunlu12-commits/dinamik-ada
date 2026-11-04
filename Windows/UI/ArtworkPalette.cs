using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace DinamikAda.UI;

/// <summary>
/// Albüm kapağının baskın renkleri; kompakt pildeki dalga formu çubukları bu
/// renklere boyanır ve renk çubuklar boyunca geçer. Boş palet = eski beyaz görünüm.
/// </summary>
public sealed record ArtworkPalette(IReadOnlyList<Color> Colors)
{
    public static readonly ArtworkPalette None = new(Array.Empty<Color>());
    public bool IsEmpty => Colors.Count == 0;

    public Color ColorAt(double fraction)
    {
        if (Colors.Count == 0) return Color.FromArgb(217, 255, 255, 255);
        if (Colors.Count == 1) return Colors[0];
        var position = Math.Clamp(fraction, 0, 1) * (Colors.Count - 1);
        var index = Math.Min((int)position, Colors.Count - 2);
        var t = position - index;
        Color a = Colors[index], b = Colors[index + 1];
        return Color.FromRgb((byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));
    }

    public bool Equals(ArtworkPalette? other) => other != null && Colors.SequenceEqual(other.Colors);
    public override int GetHashCode() => Colors.Count;
}

/// <summary>
/// Kapaktan palet çıkarır. Ortalama renk *değil*: kırmızı köşeli mavi bir kapağın
/// ortalaması kapakta hiç olmayan çamurlu bir mor verir. Pikseller tona göre 12
/// kovaya bölünür, en dolu kovalar kazanır. Siyaha/beyaza yakın ve soluk pikseller
/// elenir, kalan renk siyah pil üzerinde okunacak bir doygunluk/parlaklık tabanına
/// çekilir. Kullanılabilir rengi olmayan kapak boş palet döndürür.
/// </summary>
public static class ArtworkPaletteExtractor
{
    private const int SampleSide = 24;
    private const int HueBins = 12;
    private const double MinSaturation = 0.18;
    private const double MinBrightness = 0.15;
    private const double OutputSaturationFloor = 0.55;
    private const double OutputBrightnessFloor = 0.72;

    public static ArtworkPalette Extract(BitmapSource? image)
    {
        if (image == null || image.PixelWidth == 0 || image.PixelHeight == 0) return ArtworkPalette.None;
        byte[] pixels;
        try
        {
            var scaled = new TransformedBitmap(image, new ScaleTransform(
                SampleSide / (double)image.PixelWidth, SampleSide / (double)image.PixelHeight));
            var bgra = new FormatConvertedBitmap(scaled, PixelFormats.Bgra32, null, 0);
            int w = bgra.PixelWidth, h = bgra.PixelHeight;
            pixels = new byte[w * h * 4];
            bgra.CopyPixels(pixels, w * 4, 0);
        }
        catch
        {
            return ArtworkPalette.None;
        }
        return Extract(pixels);
    }

    /// <summary>BGRA piksellerden palet (test edilebilsin diye ayrı).</summary>
    public static ArtworkPalette Extract(byte[] bgra)
    {
        var weights = new double[HueBins];
        var hueSum = new double[HueBins];
        var satSum = new double[HueBins];
        var brightSum = new double[HueBins];

        for (var i = 0; i + 3 < bgra.Length; i += 4)
        {
            if (bgra[i + 3] == 0) continue;
            RgbToHsb(bgra[i + 2] / 255.0, bgra[i + 1] / 255.0, bgra[i] / 255.0, out var hue, out var sat, out var bright);
            if (sat < MinSaturation || bright < MinBrightness) continue;
            var weight = sat * bright;
            var bin = Math.Min((int)(hue * HueBins), HueBins - 1);
            weights[bin] += weight;
            hueSum[bin] += hue * weight;
            satSum[bin] += sat * weight;
            brightSum[bin] += bright * weight;
        }

        var ranked = Enumerable.Range(0, HueBins).Where(b => weights[b] > 0).OrderByDescending(b => weights[b]).ToList();
        if (ranked.Count == 0) return ArtworkPalette.None;
        var floor = weights[ranked[0]] * 0.18;
        var colors = ranked.Take(3).Where(b => weights[b] >= floor).Select(b =>
        {
            var w = weights[b];
            return HsbToColor(hueSum[b] / w, Math.Max(satSum[b] / w, OutputSaturationFloor),
                              Math.Max(brightSum[b] / w, OutputBrightnessFloor));
        }).ToList();
        return new ArtworkPalette(colors);
    }

    private static void RgbToHsb(double r, double g, double b, out double h, out double s, out double v)
    {
        var max = Math.Max(r, Math.Max(g, b));
        var min = Math.Min(r, Math.Min(g, b));
        var d = max - min;
        v = max;
        s = max <= 0 ? 0 : d / max;
        if (d <= 0) { h = 0; return; }
        if (max == r) h = ((g - b) / d) % 6;
        else if (max == g) h = (b - r) / d + 2;
        else h = (r - g) / d + 4;
        h /= 6;
        if (h < 0) h += 1;
    }

    private static Color HsbToColor(double h, double s, double v)
    {
        h = (h % 1 + 1) % 1 * 6;
        var i = (int)Math.Floor(h);
        var f = h - i;
        double p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
        var (r, g, b) = i switch
        {
            0 => (v, t, p),
            1 => (q, v, p),
            2 => (p, v, t),
            3 => (p, q, v),
            4 => (t, p, v),
            _ => (v, p, q),
        };
        return Color.FromRgb((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));
    }
}
