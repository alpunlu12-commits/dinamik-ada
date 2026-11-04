namespace DinamikAda.Core;

/// <summary>
/// Segoe Fluent Icons / Segoe MDL2 Assets simge kodları — macOS'taki SF Symbols'ün
/// karşılığı. Windows 11'de Fluent, Windows 10'da MDL2 aynı kodları taşır.
/// </summary>
public static class Glyphs
{
    public static string Of(int code) => ((char)code).ToString();

    public static readonly string Play = Of(0xE768);
    public static readonly string Pause = Of(0xE769);
    public static readonly string Previous = Of(0xE892);
    public static readonly string Next = Of(0xE893);
    public static readonly string Music = Of(0xE8D6);
    public static readonly string Timer = Of(0xE916);
    public static readonly string Restart = Of(0xE72C);
    public static readonly string Close = Of(0xE711);
    public static readonly string Calendar = Of(0xE787);
    public static readonly string Download = Of(0xE896);
    public static readonly string Tray = Of(0xE7B8);
    public static readonly string Headphones = Of(0xE7F6);
    public static readonly string Camera = Of(0xE714);
    public static readonly string Microphone = Of(0xE720);
    public static readonly string Warning = Of(0xE7BA);
    public static readonly string Brightness = Of(0xE706);
    public static readonly string Settings = Of(0xE713);
    public static readonly string Bell = Of(0xEA8F);
    public static readonly string Check = Of(0xE73E);

    public static readonly string Mute = Of(0xE74F);
    private static readonly int[] VolumeLevels = { 0xE993, 0xE994, 0xE995 };

    /// <summary>Ses düzeyine göre hoparlör simgesi (IslandSymbol.volume).</summary>
    public static string Volume(double level, bool muted)
    {
        if (muted || level <= 0) return Mute;
        if (level < 0.34) return Of(VolumeLevels[0]);
        if (level < 0.67) return Of(VolumeLevels[1]);
        return Of(VolumeLevels[2]);
    }

    /// <summary>Pil simgesi: Battery0 (E850) … Battery9 (E859), Battery10 (E83F); şarjda şimşekli.</summary>
    public static string Battery(int percentage, bool charging)
    {
        if (charging) return Of(0xE83E);
        var tenth = (int)System.Math.Round(System.Math.Clamp(percentage, 0, 100) / 10.0);
        return tenth >= 10 ? Of(0xE83F) : Of(0xE850 + tenth);
    }
}
