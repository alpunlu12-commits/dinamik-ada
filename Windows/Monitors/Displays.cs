using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;

namespace DinamikAda.Monitors;

/// <summary>Bağlı bir ekran: fiziksel piksel sınırları ve kalıcı kimliği.</summary>
public sealed record DisplayInfo(IntPtr Handle, Int32Rect Bounds, bool IsPrimary, string Id, string Name, double Scale);

/// <summary>
/// Ekranlar ve tercih edilen ekran. Tercih, ekranın aygıt arabirimi yolu ile
/// saklanır (monitör çıkarılıp takılınca değişmeyen kimlik); bağlı değilse ana
/// ekrana düşülür — hiçbir ekranda olmayan bir ada çökmüş gibi görünürdü.
/// </summary>
public static class Displays
{
    public static List<DisplayInfo> All()
    {
        var list = new List<DisplayInfo>();
        Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr monitor, IntPtr hdc, ref Native.RECT r, IntPtr data) =>
        {
            var info = new Native.MONITORINFOEX { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.MONITORINFOEX>() };
            if (!Native.GetMonitorInfo(monitor, ref info)) return true;
            var dd = new Native.DISPLAY_DEVICE { cb = System.Runtime.InteropServices.Marshal.SizeOf<Native.DISPLAY_DEVICE>() };
            var id = info.szDevice;
            var name = info.szDevice.TrimStart('\\', '.');
            if (Native.EnumDisplayDevices(info.szDevice, 0, ref dd, Native.EDD_GET_DEVICE_INTERFACE_NAME))
            {
                if (!string.IsNullOrEmpty(dd.DeviceID)) id = dd.DeviceID;
                if (!string.IsNullOrEmpty(dd.DeviceString)) name = dd.DeviceString;
            }
            double scale = 1;
            if (Native.GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 && dpiX > 0) scale = dpiX / 96.0;
            var m = info.rcMonitor;
            list.Add(new DisplayInfo(monitor, new Int32Rect(m.Left, m.Top, m.Right - m.Left, m.Bottom - m.Top),
                (info.dwFlags & Native.MONITORINFOF_PRIMARY) != 0, id, name, scale));
            return true;
        }, IntPtr.Zero);

        // Aynı modelden iki monitör aynı adı taşır; ayırt edilebilsinler.
        for (var i = 0; i < list.Count; i++)
            list[i] = list[i] with { Name = $"{i + 1}: {list[i].Name}" };
        return list;
    }

    /// <summary>"automatic" ya da "display:&lt;kimlik&gt;" tercihinden ekran.</summary>
    public static DisplayInfo? Preferred(string preference)
    {
        var all = All();
        if (preference.StartsWith("display:", StringComparison.Ordinal))
        {
            var id = preference["display:".Length..];
            var match = all.FirstOrDefault(d => d.Id == id);
            if (match != null) return match;
        }
        return all.FirstOrDefault(d => d.IsPrimary) ?? all.FirstOrDefault();
    }
}
