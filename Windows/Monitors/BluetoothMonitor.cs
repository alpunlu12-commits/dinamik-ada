using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using DinamikAda.Island;
using Windows.Devices.Enumeration;

namespace DinamikAda.Monitors;

/// <summary>
/// Bağlı Bluetooth ses cihazları ve bildirdikleri pil.
///
/// Bağlantı, eşleşmiş Bluetooth uç noktalarını izleyen bir DeviceWatcher'dan
/// gelir. Pil yüzdesi Windows'un Ayarlar &gt; Bluetooth sayfasında gösterdiği
/// aygıt özelliğinden (DEVPKEY_Bluetooth_Battery) okunur; uç nokta ile aygıt
/// düğümü kapsayıcı kimliğiyle eşleştirilir. İzin gerekmez.
///
/// Yalnızca ses/görüntü sınıfındaki ve pil bildiren cihazlar listelenir
/// (macOS sürümüyle aynı: klavye ve fare elenir). AirPods'un sol/sağ/kutu
/// ayrımı Windows'ta yok; tek değer gelir.
/// </summary>
public sealed class BluetoothMonitor
{
    public Action<IReadOnlyList<BluetoothDevice>>? OnChange { get; set; }
    public Action<BluetoothDevice>? OnConnect { get; set; }
    public IReadOnlyList<BluetoothDevice> Devices { get; private set; } = Array.Empty<BluetoothDevice>();

    private const string BatteryKey = "{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2";
    private const string ConnectedKey = "System.Devices.Aep.IsConnected";
    private const string ContainerKey = "System.Devices.Aep.ContainerId";
    private const string MajorClassKey = "System.Devices.Aep.Bluetooth.Cod.Major";

    /// <summary>Bluetooth klasik protokol kimliği.</summary>
    private const string Selector =
        "System.Devices.Aep.ProtocolId:=\"{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}\" AND System.Devices.Aep.IsPaired:=System.StructuredQueryType.Boolean#True";

    private DeviceWatcher? _watcher;
    private readonly Dictionary<string, DeviceInformation> _endpoints = new();
    private readonly DispatcherTimer _settle = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly DispatcherTimer _slowRefresh = new() { Interval = TimeSpan.FromMinutes(5) };
    private bool _announcePending;
    private bool _readOnce;

    public BluetoothMonitor()
    {
        // Pil değeri bağlanmadan bir iki saniye sonra yayınlanıyor; hemen okunursa boş gelir.
        _settle.Tick += (_, _) => { _settle.Stop(); _ = Refresh(_announcePending); _announcePending = false; };
        _slowRefresh.Tick += (_, _) => _ = Refresh(false);
    }

    public void Start()
    {
        if (_watcher != null) return;
        try
        {
            _watcher = DeviceInformation.CreateWatcher(Selector,
                new[] { ConnectedKey, ContainerKey, MajorClassKey }, DeviceInformationKind.AssociationEndpoint);
            _watcher.Added += (_, info) => Ui(() => { _endpoints[info.Id] = info; Schedule(_readOnce); });
            _watcher.Updated += (_, update) => Ui(() =>
            {
                if (_endpoints.TryGetValue(update.Id, out var info)) { info.Update(update); Schedule(true); }
            });
            _watcher.Removed += (_, update) => Ui(() => { _endpoints.Remove(update.Id); Schedule(false); });
            _watcher.EnumerationCompleted += (_, _) => Ui(() => { _readOnce = true; Schedule(false); });
            _watcher.Start();
            _slowRefresh.Start();
        }
        catch
        {
            _watcher = null;
        }
    }

    public void Stop()
    {
        _settle.Stop();
        _slowRefresh.Stop();
        if (_watcher != null)
        {
            try { _watcher.Stop(); } catch { }
            _watcher = null;
        }
        _endpoints.Clear();
        _readOnce = false;
        if (Devices.Count > 0)
        {
            Devices = Array.Empty<BluetoothDevice>();
            OnChange?.Invoke(Devices);
        }
    }

    private static void Ui(Action a) => Application.Current?.Dispatcher.BeginInvoke(a);

    private void Schedule(bool announce)
    {
        _announcePending |= announce;
        _settle.Stop();
        _settle.Start();
    }

    private async Task Refresh(bool announce)
    {
        if (_watcher == null) return;
        var connected = _endpoints.Values
            .Where(d => d.Properties.TryGetValue(ConnectedKey, out var c) && c is true)
            .Where(d => !d.Properties.TryGetValue(MajorClassKey, out var m) || m == null || Convert.ToInt32(m) == 4) // 4 = Ses/Görüntü
            .ToList();

        var fresh = new List<BluetoothDevice>();
        foreach (var endpoint in connected)
        {
            if (!endpoint.Properties.TryGetValue(ContainerKey, out var container) || container is not Guid id) continue;
            var battery = await ReadBattery(id);
            if (battery != null) fresh.Add(new BluetoothDevice(endpoint.Name, Single: battery));
        }

        var previous = Devices;
        if (fresh.SequenceEqual(previous)) return;
        Devices = fresh;
        OnChange?.Invoke(fresh);
        if (!announce) return;
        var previousNames = previous.Select(d => d.Name).ToHashSet();
        var arrived = fresh.FirstOrDefault(d => !previousNames.Contains(d.Name));
        if (arrived != null) OnConnect?.Invoke(arrived);
    }

    /// <summary>Kapsayıcıya ait aygıt düğümlerinden birinde yayınlanan pil yüzdesi.</summary>
    private static async Task<int?> ReadBattery(Guid container)
    {
        try
        {
            var nodes = await DeviceInformation.FindAllAsync(
                $"System.Devices.ContainerId:=\"{{{container}}}\"", new[] { BatteryKey }, DeviceInformationKind.Device);
            foreach (var node in nodes)
            {
                if (node.Properties.TryGetValue(BatteryKey, out var value) && value != null)
                {
                    var pct = Convert.ToInt32(value);
                    if (pct is >= 0 and <= 100) return pct;
                }
            }
        }
        catch { }
        return null;
    }
}
