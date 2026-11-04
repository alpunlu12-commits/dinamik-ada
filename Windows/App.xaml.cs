using System;
using System.Threading;
using System.Windows;
using DinamikAda.Core;
using DinamikAda.Island;
using DinamikAda.UI;

namespace DinamikAda;

/// <summary>
/// Bildirim alanında yaşayan, görev çubuğunda simgesi olmayan uygulama
/// (macOS'taki LSUIElement menü çubuğu ajanının karşılığı).
/// </summary>
public partial class App : Application
{
    private const string MutexName = @"Local\DinamikAda.SingleInstance";
    private const string ShowEventName = @"Local\DinamikAda.ShowSettings";

    private Mutex? _single;
    private EventWaitHandle? _showSignal;
    private IslandController? _controller;
    private TrayMenu? _tray;

    public static IslandController? Controller => ((App)Current)._controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Tek örnek: ikinci açılış var olanın Ayarlar penceresini öne getirir.
        _single = new Mutex(true, MutexName, out var created);
        if (!created)
        {
            try { EventWaitHandle.OpenExisting(ShowEventName).Set(); } catch { }
            Shutdown();
            return;
        }
        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        new Thread(() => { while (_showSignal.WaitOne()) Dispatcher.BeginInvoke(SettingsWindow.ShowSingle); })
        { IsBackground = true, Name = "DinamikAda.ShowListener" }.Start();

        // Beklenmeyen bir hata adayı düşürmesin.
        DispatcherUnhandledException += (_, args) =>
        {
            System.Diagnostics.Debug.WriteLine("DinamikAda: " + args.Exception);
            args.Handled = true;
        };

        _ = AppState.Shared;
        _controller = new IslandController();
        _tray = new TrayMenu(_controller);
    }

    public static void Quit()
    {
        var app = (App)Current;
        app._tray?.Dispose();
        app._controller?.Shutdown();
        Current.Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try { _single?.ReleaseMutex(); } catch { }
        base.OnExit(e);
    }
}
