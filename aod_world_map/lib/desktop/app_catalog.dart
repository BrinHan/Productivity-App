import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'app_files.dart';
import 'cs_helper.dart';
import 'log.dart';

/// An app from the Start menu. [target] opens it ('shell:AppsFolder\<id>'
/// works for desktop and Store apps alike); [icon] is a PNG of its icon, or
/// empty when there is none.
class InstalledApp {
  const InstalledApp(this.name, this.target, this.icon);
  final String name, target, icon;
}

/// Lists the apps in the Start menu with their icons, for the shortcut
/// picker. Icons are saved once to %APPDATA%\AodWorldMap\icons and reused.
class AppCatalog {
  AppCatalog._();

  static List<InstalledApp>? _cache;
  static List<InstalledApp>? _fixed;

  /// Apps found so far, sorted by name; [onUpdate] fires as more arrive.
  /// A second call while the first is still running shares its results.
  static Future<List<InstalledApp>> load({void Function(List<InstalledApp>)? onUpdate}) async {
    if (!Platform.isWindows) return const [];
    final fixed = _fixed;
    if (fixed != null) {
      onUpdate?.call(fixed);
      return fixed;
    }
    final out = <InstalledApp>[];
    final seen = <String>{};
    void add(InstalledApp a) {
      if (!seen.add(a.name.toLowerCase())) return;
      out
        ..add(a)
        ..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    }

    final exe = await buildCsHelper('aod_apps_v1', _cs, refs: const [r'{fw}\System.Drawing.dll']);
    try {
      if (exe != null) {
        final p = await Process.start(exe, [iconDir.path]);
        unawaited(p.stderr.drain<void>());
        var last = DateTime(2000);
        await for (final line in p.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
          final a = _parse(line);
          if (a == null) continue;
          add(a);
          // Repaint the list a few times a second, not once per app.
          if (DateTime.now().difference(last).inMilliseconds > 150) {
            last = DateTime.now();
            onUpdate?.call(List.of(out));
          }
        }
      } else {
        // No C# compiler: names only, from PowerShell.
        final r = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Get-StartApps | ConvertTo-Json -Compress',
        ]);
        final j = jsonDecode(r.stdout as String);
        for (final e in j is List ? j : [j]) {
          if (e is! Map) continue;
          final name = e['Name'] as String?, id = e['AppID'] as String?;
          if (name != null && id != null && _keep(name, id)) add(InstalledApp(name, 'shell:AppsFolder\\$id', ''));
        }
      }
    } catch (e, st) {
      logError(e, st);
    }
    _cache = out;
    onUpdate?.call(List.of(out));
    return out;
  }

  /// What the last [load] found, to show at once while it runs again.
  static List<InstalledApp> get cached => _cache ?? const [];

  /// Makes [load] and [cached] return [apps] instead of the Start menu, so
  /// screenshots can show a chosen set of apps.
  @visibleForTesting
  static set debugCached(List<InstalledApp> apps) => _cache = _fixed = apps;

  static Directory get iconDir => appDataFolder('icons');

  static InstalledApp? _parse(String line) {
    try {
      final j = jsonDecode(line);
      if (j is! Map) return null;
      final name = j['n'] as String?, id = j['id'] as String?;
      if (name == null || id == null || !_keep(name, id)) return null;
      return InstalledApp(name, 'shell:AppsFolder\\$id', (j['icon'] as String?) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Drops what the Start menu lists beside apps: uninstallers, readmes,
  /// help files and web links.
  static bool _keep(String name, String id) {
    final n = name.toLowerCase(), i = id.toLowerCase();
    if (n.isEmpty || n.contains('uninstall')) return false;
    if (i.startsWith('http:') || i.startsWith('https:')) return false;
    const docs = ['.txt', '.chm', '.htm', '.html', '.pdf', '.url', '.rtf', '.ini', '.log', '.md'];
    return !docs.any(i.endsWith);
  }

  /// Walks shell:AppsFolder (the Start menu's "All apps"), saves each app's
  /// icon as a 64 px PNG named after a hash of its id, and prints one JSON
  /// line per app: {"n": name, "id": app id, "icon": png path}.
  static const _cs = r'''
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

static class AppsHelper
{
    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItem
    {
        void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid,
            [MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetAttributes(uint mask, out uint attrs);
        void Compare(IShellItem psi, uint hint, out int order);
    }

    [ComImport, Guid("70629033-e363-4a28-a567-0db78006e6d7"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IEnumShellItems
    {
        [PreserveSig] int Next(uint celt, [MarshalAs(UnmanagedType.Interface)] out IShellItem item, out uint fetched);
        void Skip(uint celt);
        void Reset();
        void Clone(out IEnumShellItems e);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct SIZE { public int cx, cy; }

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItemImageFactory
    {
        [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr hbm);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string path, IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public ushort bmPlanes, bmBitsPixel; public IntPtr bmBits; }

    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFOHEADER
    {
        public uint biSize;
        public int biWidth, biHeight;
        public ushort biPlanes, biBitCount;
        public uint biCompression, biSizeImage;
        public int biXPelsPerMeter, biYPelsPerMeter;
        public uint biClrUsed, biClrImportant;
    }

    [DllImport("gdi32.dll")]
    static extern int GetObject(IntPtr h, int size, out BITMAP bm);

    [DllImport("gdi32.dll")]
    static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, byte[] bits, ref BITMAPINFOHEADER bi, uint usage);

    [DllImport("user32.dll")]
    static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);

    static readonly Guid IID_IShellItem = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");
    static readonly Guid IID_IEnumShellItems = new Guid("70629033-e363-4a28-a567-0db78006e6d7");
    static readonly Guid BHID_EnumItems = new Guid("94f60519-2850-4924-aa5a-d15e84868039");
    const uint SIGDN_NORMALDISPLAY = 0;
    const uint SIGDN_PARENTRELATIVEPARSING = 0x80018001;
    const int SIIGBF_BIGGERSIZEOK = 0x1, SIIGBF_ICONONLY = 0x4;

    [STAThread]
    static void Main(string[] args)
    {
        string dir = args.Length > 0 ? args[0] : Path.GetTempPath();
        Directory.CreateDirectory(dir);
        var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        stdout.AutoFlush = true;

        IShellItem folder;
        SHCreateItemFromParsingName("shell:AppsFolder", IntPtr.Zero, IID_IShellItem, out folder);
        object o;
        folder.BindToHandler(IntPtr.Zero, BHID_EnumItems, IID_IEnumShellItems, out o);
        var items = (IEnumShellItems)o;
        IShellItem item;
        uint got;
        using (var md5 = MD5.Create())
        {
            while (items.Next(1, out item, out got) == 0 && got == 1)
            {
                try
                {
                    string name, id;
                    item.GetDisplayName(SIGDN_NORMALDISPLAY, out name);
                    item.GetDisplayName(SIGDN_PARENTRELATIVEPARSING, out id);
                    string hash = BitConverter.ToString(md5.ComputeHash(Encoding.UTF8.GetBytes(id))).Replace("-", "").ToLowerInvariant();
                    string png = Path.Combine(dir, hash + ".png");
                    if (!File.Exists(png) && !SaveIcon(item, png)) png = "";
                    stdout.WriteLine("{\"n\":" + Json(name) + ",\"id\":" + Json(id) + ",\"icon\":" + Json(png) + "}");
                }
                catch { }
                finally { Marshal.ReleaseComObject(item); }
            }
        }
    }

    static bool SaveIcon(IShellItem item, string path)
    {
        var f = item as IShellItemImageFactory;
        if (f == null) return false;
        IntPtr hbm;
        var size = new SIZE { cx = 64, cy = 64 };
        if (f.GetImage(size, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, out hbm) != 0 || hbm == IntPtr.Zero) return false;
        try
        {
            using (var bmp = WithAlpha(hbm)) bmp.Save(path, ImageFormat.Png);
            return true;
        }
        catch { return false; }
        finally { DeleteObject(hbm); }
    }

    // Copies the icon's pixels out top-down. They come premultiplied; icons
    // with no alpha at all are made opaque.
    static Bitmap WithAlpha(IntPtr hbm)
    {
        BITMAP bm;
        GetObject(hbm, Marshal.SizeOf(typeof(BITMAP)), out bm);
        int w = bm.bmWidth, h = bm.bmHeight;
        var bi = new BITMAPINFOHEADER { biSize = 40, biWidth = w, biHeight = -h, biPlanes = 1, biBitCount = 32 };
        var px = new byte[w * h * 4];
        IntPtr dc = GetDC(IntPtr.Zero);
        try { if (GetDIBits(dc, hbm, 0, (uint)h, px, ref bi, 0) != h) throw new Exception("GetDIBits"); }
        finally { ReleaseDC(IntPtr.Zero, dc); }
        bool anyAlpha = false;
        for (int i = 3; i < px.Length; i += 4) if (px[i] != 0) { anyAlpha = true; break; }
        if (!anyAlpha) for (int i = 3; i < px.Length; i += 4) px[i] = 255;
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        Marshal.Copy(px, 0, data.Scan0, px.Length);
        bmp.UnlockBits(data);
        return bmp;
    }

    static string Json(string s)
    {
        var b = new StringBuilder("\"");
        foreach (char c in s ?? "")
        {
            if (c == '"' || c == '\\') b.Append('\\').Append(c);
            else if (c < 0x20) b.Append("\\u").Append(((int)c).ToString("x4"));
            else b.Append(c);
        }
        return b.Append('"').ToString();
    }
}
''';
}
