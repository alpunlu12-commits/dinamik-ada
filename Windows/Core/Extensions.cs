using System;

namespace DinamikAda.Core;

public static class Levels
{
    /// <summary>0…1 aralığına sıkıştırır.</summary>
    public static double Unit(this double v) => Math.Min(Math.Max(v, 0), 1);

    public static string PercentText(this double v) => $"{(int)Math.Round(v.Unit() * 100, MidpointRounding.AwayFromZero)}%";

    /// <summary>
    /// %5 ızgarasına oturtulmuş değer. Yalnızca etiketi yuvarlamak yetmez:
    /// değerin kendisi ızgaraya oturtulur ki her tuş basışı tam %5 etsin.
    /// </summary>
    public static double SnappedToFivePercent(this double v) => Math.Round(v.Unit() * 20, MidpointRounding.AwayFromZero) / 20;

    public static bool IsOnFivePercentGrid(this double v) => Math.Abs(v.Unit() - v.SnappedToFivePercent()) < 0.002;

    /// <summary>
    /// Bundan küçük değişimler oturtulmaz: sesini yavaşça kısan bir uygulamayla
    /// (ya da ortam ışığına göre kayan parlaklıkla) kavga edilmesin.
    /// </summary>
    public const double DiscreteStepThreshold = 0.03;
}
