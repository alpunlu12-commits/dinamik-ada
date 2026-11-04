using System;
using System.Windows;
using System.Windows.Media;

namespace DinamikAda.UI;

/// <summary>
/// Adanın şekli (macOS'taki NotchShape). Üst köşeler dışa açılır: kıvrımlar
/// verilen dikdörtgenin *dışına*, her yandan tam üst yarıçap kadar çizilir —
/// gövde tam genişliğinde kalır ve ada ekranın üst kenarı genişliyormuş gibi
/// okunur. Alt köşeler dışbükey ve durum büyüdükçe açılır.
/// </summary>
public static class IslandShape
{
    public static Geometry Build(Rect rect, double topRadius, double bottomRadius)
    {
        var bottom = Math.Max(0, Math.Min(bottomRadius, Math.Min(rect.Width, rect.Height) / 2));
        var top = Math.Max(0, Math.Min(topRadius, rect.Height / 2));

        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            c.BeginFigure(new Point(rect.Left - top, rect.Top), true, true);
            if (top > 0)
                c.ArcTo(new Point(rect.Left, rect.Top + top), new Size(top, top), 0, false, SweepDirection.Clockwise, true, true);
            c.LineTo(new Point(rect.Left, rect.Bottom - bottom), true, true);
            if (bottom > 0)
                c.ArcTo(new Point(rect.Left + bottom, rect.Bottom), new Size(bottom, bottom), 0, false, SweepDirection.Counterclockwise, true, true);
            c.LineTo(new Point(rect.Right - bottom, rect.Bottom), true, true);
            if (bottom > 0)
                c.ArcTo(new Point(rect.Right, rect.Bottom - bottom), new Size(bottom, bottom), 0, false, SweepDirection.Counterclockwise, true, true);
            c.LineTo(new Point(rect.Right, rect.Top + top), true, true);
            if (top > 0)
                c.ArcTo(new Point(rect.Right + top, rect.Top), new Size(top, top), 0, false, SweepDirection.Clockwise, true, true);
        }
        g.Freeze();
        return g;
    }
}
