import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_catalog.dart';
import 'island_controller.dart';
import 'island_home.dart';
import 'island_widgets.dart';
import 'stocks_home.dart';
import 'today_page.dart';

// Layout constants shared with the Pip flight (the seat is a hole in the card).
const double kTabBarH = 38, kHomePadL = 12, kHomePadT = 8, kHomePadB = 12;
const double kCardPad = 10, kSeatW = 78, kCardW = 196;

const Size kOpenHome = Size(600, 182);
const Size kOpenStocks = Size(560, 440);
const Size kOpenToday = Size(600, 456);
const Size kOpenMusic = Size(560, 214);
const Size kOpenSettings = Size(500, 340);

Size openSizeFor(IslandPage p) {
  switch (p) {
    case IslandPage.stocks:
      return kOpenStocks;
    case IslandPage.today:
      return kOpenToday;
    case IslandPage.settings:
      return kOpenSettings;
    case IslandPage.music:
      return kOpenMusic;
    case IslandPage.home:
      return kOpenHome;
  }
}

/// Centre of Pip's seat, in the open content's coordinates.
Offset homeSeatCenter(Size content) => Offset(
  kHomePadL + kCardPad + kSeatW / 2,
  kTabBarH +
      kHomePadT +
      kCardPad +
      (content.height - kTabBarH - kHomePadT - kHomePadB - 2 * kCardPad) / 2,
);

const kShortcutIcons = <String, IconData>{
  'show_chart': Icons.show_chart,
  'code': Icons.code,
  'public': Icons.public,
  'checklist': Icons.checklist,
  'language': Icons.language,
  'terminal': Icons.terminal,
  'mail': Icons.mail_outline,
  'folder': Icons.folder_open,
  'music': Icons.music_note,
  'bolt': Icons.bolt,
  'chat': Icons.chat_bubble_outline,
  'cart': Icons.shopping_bag_outlined,
};

const kShortcutColors = <Color>[
  Color(0xFF7B5CFF),
  Color(0xFF3B8BFF),
  Color(0xFFFF8A3D),
  Color(0xFF34C77B),
  Color(0xFFFF5C7A),
  Color(0xFF22C3D6),
  Color(0xFFFFC857),
];

/// A shortcut's face: the app's own icon when it has one, else its icon
/// on its colour.
class ShortcutGlyph extends StatelessWidget {
  const ShortcutGlyph(this.s, {super.key, required this.size, required this.radius, required this.iconSize});
  final IslandShortcut s;
  final double size, radius, iconSize;

  Widget _tile() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(radius)),
    child: Icon(kShortcutIcons[s.icon] ?? Icons.bolt, size: iconSize, color: Colors.white),
  );

  @override
  Widget build(BuildContext context) => s.image.isEmpty
      ? _tile()
      : Image.file(
          File(s.image),
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _tile(),
        );
}

class IslandOpenContent extends StatelessWidget {
  const IslandOpenContent({
    super.key,
    required this.c,
    required this.onShortcut,
  });
  final IslandController c;
  final void Function(IslandShortcut)? onShortcut;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (c.page) {
      case IslandPage.home:
        body = IslandHomePage(c: c, onShortcut: onShortcut);
      case IslandPage.music:
        body = _MusicPage(c: c);
      case IslandPage.stocks:
        body = StocksPage(c: c);
      case IslandPage.today:
        body = TodayPage(c: c);
      case IslandPage.settings:
        body = _SettingsPage(c: c);
    }
    return Column(
      children: [
        _TopBar(c: c),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(key: ValueKey(c.page), child: body),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.c});
  final IslandController c;

  Widget _tab(IconData icon, IslandPage p) {
    final on = c.page == p;
    return IslandPressable(
      onTap: () => c.setPage(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 28,
        decoration: BoxDecoration(
          color: on ? const Color(0x2EFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          size: 16,
          color: on ? Colors.white : const Color(0x99FFFFFF),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
    child: SizedBox(
      height: 28,
      child: Row(
        children: [
          _tab(Icons.home_rounded, IslandPage.home),
          const SizedBox(width: 6),
          _tab(Icons.music_note_rounded, IslandPage.music),
          const SizedBox(width: 6),
          _tab(Icons.candlestick_chart_rounded, IslandPage.stocks),
          const SizedBox(width: 6),
          _tab(Icons.event_note_rounded, IslandPage.today),
          const Spacer(),
          if (c.startAnnotate != null) ...[
            IslandPressable(
              onTap: c.startAnnotate!,
              child: const SizedBox(
                width: 40,
                height: 28,
                child: Icon(Icons.draw_rounded, size: 16, color: Color(0x99FFFFFF)),
              ),
            ),
            const SizedBox(width: 6),
          ],
          _tab(Icons.settings_rounded, IslandPage.settings),
        ],
      ),
    ),
  );
}

// ----------------------------------------------------------------- music

class _MusicPage extends StatelessWidget {
  const _MusicPage({required this.c});
  final IslandController c;

  static const _accent = Color(0xFF8FB3C9);

  Widget _ctl(IconData icon, VoidCallback onTap, {double size = 32, Color color = Colors.white}) => IslandPressable(
        onTap: onTap,
        child: SizedBox(width: 46, height: 42, child: Icon(icon, size: size, color: color)),
      );

  /// Windows' sound settings, where the output device is picked.
  static void _soundSettings() =>
      Process.start('explorer.exe', ['ms-settings:sound'], mode: ProcessStartMode.detached).ignore();

  @override
  Widget build(BuildContext context) {
    final np = c.nowPlaying;
    final playing = np?.playing ?? false;
    final title = np == null ? 'Nothing playing' : (np.title.isEmpty ? 'Unknown track' : np.title);
    final artist = np == null ? 'Play something in any app' : (np.artist.isEmpty ? 'Unknown artist' : np.artist);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      child: Column(
        children: [
          Row(
            children: [
              IslandArt(path: np?.art, size: 58, radius: 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IslandMarquee(
                      text: title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                        fontFamilyFallback: islandFontFallback,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: Color(0x8CFFFFFF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Live levels of what is playing: sub-bass, bass, low-mid,
              // high-mid and treble, left to right.
              IslandWaveform(active: playing, bands: c.bands, color: _accent),
            ],
          ),
          const SizedBox(height: 14),
          _Progress(np: np, color: _accent),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(width: 46, child: Center(child: IslandAppBadge(app: np?.app ?? '', size: 24))),
              _ctl(Icons.fast_rewind_rounded, () => c.sendMusic?.call('prev'), size: 34),
              _ctl(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, () => c.sendMusic?.call('toggle'), size: 42),
              _ctl(Icons.fast_forward_rounded, () => c.sendMusic?.call('next'), size: 34),
              _ctl(Icons.laptop_rounded, _soundSettings, size: 24, color: const Color(0x8CFFFFFF)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Elapsed time, a thin progress track and the time left. Ticks while the
/// track plays; a player that gives no length shows an empty track.
class _Progress extends StatefulWidget {
  const _Progress({required this.np, required this.color});
  final NowPlaying? np;
  final Color color;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && (widget.np?.playing ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final np = widget.np;
    final len = np?.length ?? Duration.zero;
    final known = len > Duration.zero;
    final pos = known ? np!.positionNow : Duration.zero;
    final f = known ? pos.inMilliseconds / len.inMilliseconds : 0.0;
    const time = TextStyle(fontSize: 11.5, color: Color(0x8CFFFFFF), fontFeatures: [FontFeature.tabularFigures()]);
    return Row(
      children: [
        SizedBox(width: 40, child: Text(known ? _fmt(pos) : '', style: time)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0x24FFFFFF))),
                  FractionallySizedBox(
                    widthFactor: f.clamp(0.0, 1.0),
                    heightFactor: 1,
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(color: widget.color),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(known ? '-${_fmt(len - pos)}' : '', textAlign: TextAlign.right, style: time),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- settings

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.c});
  final IslandController c;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _ticker = TextEditingController(
    text: widget.c.stockSymbol,
  );
  Timer? _debounce;

  /// Showing the app picker in place of the settings.
  bool _picking = false;

  static const _label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
  static const _dim = TextStyle(fontSize: 11, color: Color(0x99FFFFFF));

  @override
  void dispose() {
    _debounce?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  Widget _seg(String text, bool on, VoidCallback onTap) => IslandPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: on ? Colors.white : const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: on ? Colors.black : Colors.white,
        ),
      ),
    ),
  );

  Widget _addButton(IconData icon, String text, VoidCallback onTap) => IslandPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: const Color(0x99FFFFFF)),
          const SizedBox(width: 5),
          Text(text, style: _dim),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    if (_picking) {
      return _AppPicker(
        onPick: (app) {
          c.addAppShortcut(app);
          setState(() => _picking = false);
        },
        onClose: () => setState(() => _picking = false),
      );
    }
    final picked = c.pipColor.toARGB32();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      children: [
        Row(
          children: [
            const Text('Open island on', style: _label),
            const Spacer(),
            _seg('Click', !c.openOnHover, () => c.setOpenOnHover(false)),
            const SizedBox(width: 6),
            _seg('Hover', c.openOnHover, () => c.setOpenOnHover(true)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Quiet notch in Chrome', style: _label),
            const Spacer(),
            _seg('On', c.quietInChrome, () => c.setQuietInChrome(true)),
            const SizedBox(width: 6),
            _seg('Off', !c.quietInChrome, () => c.setQuietInChrome(false)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Pop up on song change', style: _label),
            const Spacer(),
            _seg('On', c.popOnTrackChange, () => c.setPopOnTrackChange(true)),
            const SizedBox(width: 6),
            _seg('Off', !c.popOnTrackChange, () => c.setPopOnTrackChange(false)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('Idle size', style: _label),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: const Color(0x33FFFFFF),
                  thumbColor: Colors.white,
                  overlayColor: const Color(0x1FFFFFFF),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: c.idleWidth,
                  min: 180,
                  max: 360,
                  onChanged: c.setIdleWidth,
                ),
              ),
            ),
            Text('${c.idleWidth.round()}', style: _dim),
          ],
        ),
        Row(
          children: [
            const Text('Character', style: _label),
            const Spacer(),
            for (final col in kPipColors)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: IslandPressable(
                  onTap: () => c.setPipColor(col),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: picked == col.toARGB32()
                            ? Colors.white
                            : const Color(0x33FFFFFF),
                        width: picked == col.toARGB32() ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Stock ticker', style: _label),
            const Spacer(),
            SizedBox(
              width: 110,
              height: 30,
              child: TextField(
                controller: _ticker,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                cursorColor: Colors.white,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 700),
                    () => c.setStockSymbol(v),
                  );
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0x14FFFFFF),
                  hintText: 'AAPL',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0x66FFFFFF),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Shortcuts', style: _label),
        const SizedBox(height: 8),
        for (final s in c.shortcuts)
          _ShortcutEditor(key: ObjectKey(s), s: s, c: c),
        if (c.shortcuts.length < 6)
          Row(
            children: [
              Expanded(child: _addButton(Icons.apps_rounded, 'Add app', () => setState(() => _picking = true))),
              const SizedBox(width: 6),
              Expanded(child: _addButton(Icons.language_rounded, 'Add website', c.addShortcut)),
            ],
          ),
      ],
    );
  }
}

class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({super.key, required this.s, required this.c});
  final IslandShortcut s;
  final IslandController c;

  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late final TextEditingController _label = TextEditingController(
    text: widget.s.label,
  );
  late final TextEditingController _target = TextEditingController(
    text: widget.s.target,
  );

  static const _kindNames = {
    ShortcutKind.web: 'Website',
    ShortcutKind.app: 'App',
    ShortcutKind.screensaver: 'Screensaver',
    ShortcutKind.planner: 'Planner',
  };

  @override
  void dispose() {
    _label.dispose();
    _target.dispose();
    super.dispose();
  }

  void _cycleColor() {
    final s = widget.s;
    final i = kShortcutColors.indexWhere(
      (c) => c.toARGB32() == s.color.toARGB32(),
    );
    s.color = kShortcutColors[(i + 1) % kShortcutColors.length];
    widget.c.shortcutsChanged();
  }

  void _cycleIcon() {
    final s = widget.s;
    final keys = kShortcutIcons.keys.toList();
    s.icon = keys[(keys.indexOf(s.icon) + 1) % keys.length];
    widget.c.shortcutsChanged();
  }

  void _cycleKind() {
    final s = widget.s;
    s.kind =
        ShortcutKind.values[(s.kind.index + 1) % ShortcutKind.values.length];
    widget.c.shortcutsChanged();
  }

  Widget _field(
    TextEditingController ctl,
    String hint,
    ValueChanged<String> onChanged,
  ) => SizedBox(
    height: 30,
    child: TextField(
      controller: ctl,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 12, color: Colors.white),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    // Picked from the Start menu: it wears the app's icon and opens by id,
    // so there is no icon, colour or path to set.
    final picked = s.image.isNotEmpty && s.kind == ShortcutKind.app;
    final needsTarget =
        !picked && (s.kind == ShortcutKind.web || s.kind == ShortcutKind.app);
    final glyph = ShortcutGlyph(s, size: 30, radius: 9, iconSize: 16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          picked ? glyph : IslandPressable(onTap: _cycleIcon, child: glyph),
          const SizedBox(width: 6),
          if (picked)
            const SizedBox(width: 14)
          else
            IslandPressable(
              onTap: _cycleColor,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: s.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: _field(_label, 'Name', (v) {
              s.label = v;
              widget.c.shortcutsChanged();
            }),
          ),
          const SizedBox(width: 6),
          IslandPressable(
            onTap: _cycleKind,
            child: Container(
              width: 78,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x1FFFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _kindNames[s.kind]!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: needsTarget
                ? _field(
                    _target,
                    s.kind == ShortcutKind.web
                        ? 'https://…'
                        : 'code, or path to .exe',
                    (v) {
                      s.target = v;
                      widget.c.shortcutsChanged();
                    },
                  )
                : picked
                ? const SizedBox(
                    height: 30,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('Start menu app', style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF))),
                      ),
                    ),
                  )
                : const SizedBox(height: 30),
          ),
          const SizedBox(width: 4),
          IslandPressable(
            onTap: () => widget.c.removeShortcut(s),
            child: const SizedBox(
              width: 24,
              height: 30,
              child: Icon(Icons.close, size: 14, color: Color(0x99FFFFFF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable list of the Start menu's apps; tap one (or press Enter for
/// the top match) to add it as a shortcut.
class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.onPick, required this.onClose});
  final ValueChanged<InstalledApp> onPick;
  final VoidCallback onClose;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  final _query = TextEditingController();
  List<InstalledApp> _apps = AppCatalog.cached;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppCatalog.load(onUpdate: (a) {
      if (mounted) setState(() => _apps = a);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Names that start with the query first, then ones that contain it.
  List<InstalledApp> get _matches {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _apps;
    final starts = <InstalledApp>[], contains = <InstalledApp>[];
    for (final a in _apps) {
      final n = a.name.toLowerCase();
      if (n.startsWith(q)) {
        starts.add(a);
      } else if (n.contains(q)) {
        contains.add(a);
      }
    }
    return [...starts, ...contains];
  }

  Widget _icon(InstalledApp a) {
    const fallback = Icon(Icons.apps_rounded, size: 18, color: Color(0x66FFFFFF));
    if (a.icon.isEmpty) return fallback;
    return Image.file(
      File(a.icon),
      width: 22,
      height: 22,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _matches;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 14, 8),
          child: Row(
            children: [
              IslandPressable(
                onTap: widget.onClose,
                child: const SizedBox(
                  width: 28,
                  height: 30,
                  child: Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xCCFFFFFF)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (shown.isNotEmpty) widget.onPick(shown.first);
                    },
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0x14FFFFFF),
                      hintText: 'Search apps',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 15, color: Color(0x66FFFFFF)),
                      prefixIconConstraints: const BoxConstraints(minWidth: 30),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    _loading ? 'Finding your apps\u2026' : 'No apps match',
                    style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 14, 10),
                  itemCount: shown.length,
                  itemExtent: 34,
                  itemBuilder: (_, i) {
                    final a = shown[i];
                    return IslandPressable(
                      onTap: () => widget.onPick(a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          // Enter picks the top match; mark it.
                          color: i == 0 && _query.text.isNotEmpty ? const Color(0x14FFFFFF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 22, height: 22, child: Center(child: _icon(a))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
