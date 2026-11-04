using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DinamikAda.Monitors;

public enum MediaKey { VolumeUp, VolumeDown, Mute }

/// <summary>
/// Ses tuşlarını Windows'tan önce alır, böylece sistemin ses göstergesi çıkmaz
/// ve ada onun yerine geçer. Düşük seviyeli klavye kancası izin istemez
/// (macOS'taki event tap Erişilebilirlik istiyordu).
///
/// Yutulan tuş mutlaka uygulanır: işleyici false dönerse tuş sisteme aynen
/// geçirilir — uygulanamayan bir tuşu yutmak kullanıcıyı ses denetiminden etmek
/// olurdu. Basma/bırakma eşleştirilir: yalnızca basışını yuttuğumuz tuşun
/// bırakması yutulur. Parlaklık tuşları çoğu dizüstünde donanımda işlendiği için
/// buraya hiç gelmez.
/// </summary>
public sealed class MediaKeyMonitor
{
    /// <summary>(tuş, Shift+Alt ile ince adım mı) → uygulandıysa true.</summary>
    public Func<MediaKey, bool, bool>? OnKey { get; set; }

    private IntPtr _hook = IntPtr.Zero;
    private readonly Native.LowLevelKeyboardProc _proc;
    private readonly bool[] _swallowedDown = new bool[3];

    public MediaKeyMonitor() => _proc = HookCallback;

    public bool IsRunning => _hook != IntPtr.Zero;

    public void Start()
    {
        if (_hook != IntPtr.Zero) return;
        using var module = Process.GetCurrentProcess().MainModule;
        _hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _proc, Native.GetModuleHandle(module?.ModuleName), 0);
    }

    public void Stop()
    {
        if (_hook == IntPtr.Zero) return;
        Native.UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
        Array.Clear(_swallowedDown);
    }

    /// <summary>Hızlı olmalı: Windows yavaş kancaları sessizce söker.</summary>
    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var k = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            MediaKey? key = (int)k.vkCode switch
            {
                Native.VK_VOLUME_UP => MediaKey.VolumeUp,
                Native.VK_VOLUME_DOWN => MediaKey.VolumeDown,
                Native.VK_VOLUME_MUTE => MediaKey.Mute,
                _ => null,
            };
            // Başka bir yazılımın taklit ettiği tuşlara dokunma.
            if (key is { } mk && (k.flags & Native.LLKHF_INJECTED) == 0)
            {
                var msg = wParam.ToInt32();
                var down = msg is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN;
                var up = msg is Native.WM_KEYUP or Native.WM_SYSKEYUP;
                if (down)
                {
                    var precise = Native.IsKeyDown(Native.VK_SHIFT) && Native.IsKeyDown(Native.VK_MENU);
                    if (OnKey?.Invoke(mk, precise) == true)
                    {
                        _swallowedDown[(int)mk] = true;
                        return new IntPtr(1);
                    }
                }
                else if (up && _swallowedDown[(int)mk])
                {
                    _swallowedDown[(int)mk] = false;
                    return new IntPtr(1);
                }
            }
        }
        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }
}
