using System;
using System.Drawing;
using System.Windows.Forms;
using DinamikAda.Core;
using DinamikAda.Island;

namespace DinamikAda.UI;

/// <summary>
/// Bildirim alanı simgesi ve menüsü — macOS'taki menü çubuğu öğesinin karşılığı:
/// çalan parça, zamanlayıcı, raf, takvim durumu, demo öğeleri, Ayarlar ve Çıkış.
/// </summary>
public sealed class TrayMenu : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly IslandController _controller;
    private static readonly int[] TimerPresets = { 1, 3, 5, 10, 15, 20, 25, 30, 45, 60 };

    public TrayMenu(IslandController controller)
    {
        _controller = controller;
        _icon = new NotifyIcon
        {
            Visible = true,
            Text = "Dinamik Ada",
            Icon = LoadIcon(),
            ContextMenuStrip = new ContextMenuStrip(),
        };
        _icon.ContextMenuStrip.Opening += (_, _) => Build();
        _icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) SettingsWindow.ShowSingle(); };
        Build();
    }

    private static Icon LoadIcon()
    {
        try
        {
            var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppIcon.ico"))?.Stream;
            if (stream != null) return new Icon(stream, SystemInformation.SmallIconSize);
        }
        catch { }
        return SystemIcons.Application;
    }

    private void Build()
    {
        var menu = _icon.ContextMenuStrip!;
        menu.Items.Clear();
        var s = AppState.Shared;
        var model = _controller.Model;

        // Çalan parça
        if (!s.MusicEnabled) Disabled(menu, Strings.NowPlayingOff);
        else if (model.NowPlaying is { } t) Disabled(menu, $"{(t.IsPlaying ? "▶" : "⏸")}  {t.Title} — {t.Artist}");
        else Disabled(menu, Strings.NothingPlaying);
        menu.Items.Add(new ToolStripSeparator());

        // Zamanlayıcı
        if (!s.TimerEnabled) Disabled(menu, Strings.TimerOff);
        else if (model.Countdown is { } c)
        {
            Disabled(menu, Strings.TimerStatus(c.Text, c.IsRunning));
            Item(menu, c.IsRunning ? Strings.PauseTimer : Strings.ResumeTimer, () => model.TimerAction(new TimerAction.Toggle()));
            Item(menu, Strings.RestartTimer, () => model.TimerAction(new TimerAction.Restart()));
            Item(menu, Strings.CancelTimer, () => model.TimerAction(new TimerAction.Cancel()));
        }
        else
        {
            var start = new ToolStripMenuItem(Strings.StartTimer);
            foreach (var m in TimerPresets)
            {
                var minutes = m;
                start.DropDownItems.Add(Strings.MinutesLong(minutes), null, (_, _) => model.TimerAction(new TimerAction.Start(minutes)));
            }
            menu.Items.Add(start);
        }
        menu.Items.Add(new ToolStripSeparator());

        // Raf
        if (!s.ShelfEnabled) Disabled(menu, Strings.ShelfOff);
        else if (model.Shelf.Count == 0) Disabled(menu, Strings.ShelfEmptyHint);
        else
        {
            Disabled(menu, Strings.ShelfStatus(model.Shelf.Count));
            Item(menu, Strings.CopyShelfFiles, () => model.ShelfAction(new ShelfAction.CopyAll()));
            Item(menu, Strings.ShareShelfFiles, () => model.ShelfAction(new ShelfAction.ShareAll()));
            Item(menu, Strings.ClearShelf, () => model.ShelfAction(new ShelfAction.Clear()));
        }
        menu.Items.Add(new ToolStripSeparator());

        // Takvim
        if (!s.CalendarEnabled) Disabled(menu, Strings.CalendarOff);
        else if (model.CalendarStatus == CalendarStatus.NoLink) Item(menu, Strings.CalendarNeedsLink, SettingsWindow.ShowSingle);
        else if (model.CalendarStatus == CalendarStatus.Failed) Item(menu, Strings.CalendarFailedMenu, SettingsWindow.ShowSingle);
        else if (model.UpcomingEvent is { } ev) Disabled(menu, Strings.UpNextMenu(ev.Title, ev.TimeText, ev.RelativeText));
        else Disabled(menu, Strings.NothingOnCalendar);
        menu.Items.Add(new ToolStripSeparator());

        // Demo öğeleri (8 sn'de kendiliğinden çözülür)
        Item(menu, Strings.DemoExpand, model.DemoExpand);
        Item(menu, model.State == IslandState.ControlCenter ? Strings.DemoHideCC : Strings.DemoShowCC, model.DemoToggleControlCenter);
        menu.Items.Add(new ToolStripSeparator());

        Item(menu, Strings.SettingsItem, SettingsWindow.ShowSingle);
        menu.Items.Add(new ToolStripSeparator());
        Item(menu, Strings.Quit, App.Quit);
    }

    private static void Disabled(ContextMenuStrip menu, string text) =>
        menu.Items.Add(new ToolStripMenuItem(text.Length > 60 ? text[..59] + "…" : text) { Enabled = false });

    private static void Item(ContextMenuStrip menu, string text, Action action) =>
        menu.Items.Add(text, null, (_, _) => action());

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
