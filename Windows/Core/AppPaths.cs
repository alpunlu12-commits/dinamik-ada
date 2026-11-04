using System;
using System.IO;

namespace DinamikAda.Core;

/// <summary>Uygulamanın diske yazdığı her şey: %APPDATA%\DinamikAda.</summary>
public static class AppPaths
{
    public static string Root
    {
        get
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DinamikAda");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string File(string name) => Path.Combine(Root, name);

    /// <summary>Önce geçici dosyaya yaz, sonra yer değiştir: yarım dosya kalmasın.</summary>
    public static void WriteAtomic(string path, byte[] data)
    {
        var tmp = path + ".tmp";
        System.IO.File.WriteAllBytes(tmp, data);
        System.IO.File.Move(tmp, path, overwrite: true);
    }
}
