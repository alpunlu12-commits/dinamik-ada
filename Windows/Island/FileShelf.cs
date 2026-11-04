using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using DinamikAda.Core;
using DinamikAda.Monitors;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

namespace DinamikAda.Island;

/// <summary>
/// Adaya bırakılan dosyalar. En fazla 6, en yenisi başta; uygulama kapanıp
/// açılsa da kalırlar. Yollar saklanır: raf zaten geçici — taşınmış ya da
/// silinmiş bir dosya sessizce raftan düşer.
/// </summary>
public sealed class FileShelf
{
    public Action<IReadOnlyList<ShelfItem>>? OnChange { get; set; }
    public List<ShelfItem> Items { get; private set; } = new();
    public const int Capacity = 6;

    private readonly string _path = AppPaths.File("shelf.json");

    public FileShelf() => Load();

    public void Add(IEnumerable<string> paths)
    {
        var changed = false;
        foreach (var raw in paths)
        {
            var full = System.IO.Path.GetFullPath(raw);
            if (!File.Exists(full) && !Directory.Exists(full)) continue;
            Items.RemoveAll(i => string.Equals(i.Path, full, StringComparison.OrdinalIgnoreCase));
            Items.Insert(0, new ShelfItem(full));
            changed = true;
        }
        if (!changed) return;
        if (Items.Count > Capacity) Items.RemoveRange(Capacity, Items.Count - Capacity);
        Commit();
    }

    public void Remove(IEnumerable<ShelfItem> items)
    {
        var ids = items.Select(i => i.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (Items.RemoveAll(i => ids.Contains(i.Id)) > 0) Commit();
    }

    public void Clear()
    {
        if (Items.Count == 0) return;
        Items.Clear();
        Commit();
    }

    /// <summary>Panoya dosya olarak (Gezgin'de yapıştırılabilir) ve yol metni olarak.</summary>
    public static void Copy(IReadOnlyCollection<ShelfItem> items)
    {
        if (items.Count == 0) return;
        var data = new DataObject();
        var files = new StringCollection();
        files.AddRange(items.Select(i => i.Path).ToArray());
        data.SetFileDropList(files);
        data.SetText(string.Join(Environment.NewLine, items.Select(i => i.Path)));
        try { System.Windows.Clipboard.SetDataObject(data, true); } catch { }
    }

    public static void Open(ShelfItem item)
    {
        try { Process.Start(new ProcessStartInfo(item.Path) { UseShellExecute = true }); } catch { }
    }

    /// <summary>Dosyaları Gezgin'de seçili göster (aynı klasördekiler tek pencerede).</summary>
    public static void Reveal(IReadOnlyCollection<ShelfItem> items)
    {
        foreach (var group in items.GroupBy(i => System.IO.Path.GetDirectoryName(i.Path) ?? ""))
            Native.ShowInExplorer(group.Key, group.Select(i => i.Path).ToList());
    }

    /// <summary>
    /// Windows paylaşım penceresi — macOS'taki AirDrop'un karşılığı (Yakındaki
    /// paylaşım, e-posta, uygulamalar).
    /// </summary>
    public static void Share(IReadOnlyCollection<ShelfItem> items, IntPtr window)
    {
        if (items.Count == 0 || window == IntPtr.Zero) return;
        try
        {
            var manager = DataTransferManagerInterop.GetForWindow(window);
            void Handler(DataTransferManager sender, DataRequestedEventArgs args)
            {
                sender.DataRequested -= Handler;
                var request = args.Request;
                request.Data.Properties.Title = items.Count == 1 ? items.First().Name : Strings.Files(items.Count);
                var deferral = request.GetDeferral();
                _ = Task.Run(async () =>
                {
                    try
                    {
                        var storage = new List<IStorageItem>();
                        foreach (var i in items)
                        {
                            if (Directory.Exists(i.Path)) storage.Add(await StorageFolder.GetFolderFromPathAsync(i.Path));
                            else storage.Add(await StorageFile.GetFileFromPathAsync(i.Path));
                        }
                        request.Data.SetStorageItems(storage);
                    }
                    catch (Exception e)
                    {
                        request.FailWithDisplayText(e.Message);
                    }
                    finally
                    {
                        deferral.Complete();
                    }
                });
            }
            manager.DataRequested += Handler;
            DataTransferManagerInterop.ShowShareUIForWindow(window);
        }
        catch (Exception e)
        {
            Debug.WriteLine("DinamikAda: paylaşım açılamadı — " + e.Message);
        }
    }

    /// <summary>
    /// Hedefi sorarak taşı. Çakışan ad Gezgin gibi "rapor 2.pdf" olur (asla üzerine
    /// yazılmaz) ve yalnızca gerçekten taşınan dosya raftan düşer.
    /// </summary>
    public void Move(IReadOnlyCollection<ShelfItem> items, Action<List<ShelfItem>, string?> completion)
    {
        if (items.Count == 0) return;
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = Strings.MoveMessage(items.Count) };
        if (dialog.ShowDialog() != true) return;
        var destination = dialog.FolderName;
        var moved = new List<ShelfItem>();
        string? failure = null;
        foreach (var item in items)
        {
            var target = AvailablePath(destination, item.Name);
            try
            {
                if (Directory.Exists(item.Path)) Directory.Move(item.Path, target);
                else File.Move(item.Path, target);
                moved.Add(item);
            }
            catch (Exception e)
            {
                failure = e.Message;
            }
        }
        Remove(moved);
        completion(moved, failure);
    }

    public static string AvailablePath(string directory, string name)
    {
        var candidate = System.IO.Path.Combine(directory, name);
        if (!File.Exists(candidate) && !Directory.Exists(candidate)) return candidate;
        var stem = System.IO.Path.GetFileNameWithoutExtension(name);
        var ext = System.IO.Path.GetExtension(name);
        for (var n = 2; n < 1000; n++)
        {
            var next = System.IO.Path.Combine(directory, $"{stem} {n}{ext}");
            if (!File.Exists(next) && !Directory.Exists(next)) return next;
        }
        return System.IO.Path.Combine(directory, $"{stem} {Guid.NewGuid():N}{ext}");
    }

    private void Commit()
    {
        try { AppPaths.WriteAtomic(_path, JsonSerializer.SerializeToUtf8Bytes(Items.Select(i => i.Path).ToList())); } catch { }
        OnChange?.Invoke(Items.ToList());
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_path)) return;
            var paths = JsonSerializer.Deserialize<List<string>>(File.ReadAllBytes(_path)) ?? new();
            Items = paths.Where(p => File.Exists(p) || Directory.Exists(p)).Select(p => new ShelfItem(p)).ToList();
            if (Items.Count != paths.Count) Commit();
        }
        catch { }
    }
}
