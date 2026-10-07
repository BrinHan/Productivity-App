import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'date_names.dart';
import 'island_controller.dart';
import 'island_pages.dart';
import 'island_widgets.dart';
import 'stock_service.dart';
import 'today_calendar.dart';

const _dim = TextStyle(fontSize: 11, color: Color(0x99FFFFFF));
const _up = Color(0xFF30D158), _down = Color(0xFFFF453A);

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '$h$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The island's home: Pip with the time and date (or what is playing), this
/// week, a few stocks, and the quick-launch icons.
class IslandHomePage extends StatefulWidget {
  const IslandHomePage({super.key, required this.c, required this.onShortcut});
  final IslandController c;
  final void Function(IslandShortcut)? onShortcut;

  @override
  State<IslandHomePage> createState() => _IslandHomePageState();
}

class _IslandHomePageState extends State<IslandHomePage> {
  /// Quotes survive leaving the page, so the preview paints at once.
  static final Map<String, StockData> _quotes = {};
  static const _previewCount = 3;
  Timer? _stocks;

  @override
  void initState() {
    super.initState();
    final c = widget.c;
    // Both skip the network when what they have is recent.
    c.agenda.refresh(c.calendarFeeds);
    c.google.refresh();
    _loadQuotes();
    _stocks = Timer.periodic(const Duration(seconds: 60), (_) => _loadQuotes());
  }

  @override
  void dispose() {
    _stocks?.cancel();
    super.dispose();
  }

  Future<void> _loadQuotes() => Future.wait([
    for (final s in widget.c.watchlist.take(_previewCount))
      StockService.fetch(s, '1d')
          .then((d) {
            _quotes[s] = d;
            if (mounted) setState(() {});
          })
          .catchError((_) {}),
  ]);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kHomePadL, kHomePadT, 12, kHomePadB),
      child: Row(
        children: [
          SizedBox(
            width: kCardW,
            child: _Card(child: c.musicPlaying ? _MiniMusic(c: c) : const _PipCorner()),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ListenableBuilder(
                    listenable: Listenable.merge([c.agenda, c.google]),
                    builder: (context, _) => _Card(
                      child: _DayScroller(events: calendarEvents(c), onOpen: () => c.setPage(IslandPage.today)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _Card(
                    onTap: () => c.setPage(IslandPage.stocks),
                    child: _StocksPreview(symbols: c.watchlist.take(_previewCount).toList(), quotes: _quotes),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Launcher(shortcuts: c.shortcuts, onTap: widget.onShortcut),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(kCardPad),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(18)),
      child: child,
    );
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card),
    );
  }
}

/// Pip's seat (the flying Pip lands here, drawn by the island) beside the
/// time and date.
class _PipCorner extends StatelessWidget {
  const _PipCorner();

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    return Row(
      children: [
        const SizedBox(width: kSeatW),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ClockText(),
              const SizedBox(height: 4),
              Text(
                '${dayShort[n.weekday - 1]}, ${monthShort[n.month - 1]} ${n.day}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _dim,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClockText extends StatefulWidget {
  const _ClockText();

  @override
  State<_ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<_ClockText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$h:${n.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
          ),
          TextSpan(
            text: n.hour < 12 ? ' AM' : ' PM',
            style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF)),
          ),
        ],
      ),
    );
  }
}

/// What is playing, in Pip's corner: big art beside the title, album and
/// artist, with the player's badge and plain controls underneath. The art
/// opens the Music tab.
class _MiniMusic extends StatelessWidget {
  const _MiniMusic({required this.c});
  final IslandController c;

  Widget _ctl(IconData icon, String cmd, {double size = 21}) => IslandPressable(
    onTap: () => c.sendMusic?.call(cmd),
    child: SizedBox(
      width: 24,
      height: 26,
      child: Icon(icon, size: size, color: Colors.white),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final np = c.nowPlaying;
    final title = np == null || np.title.isEmpty ? 'Unknown track' : np.title;
    final artist = np == null || np.artist.isEmpty ? 'Unknown artist' : np.artist;
    final album = np?.album ?? '';
    return Center(
      child: Row(
        children: [
          IslandPressable(
            onTap: () => c.setPage(IslandPage.music),
            child: IslandArt(path: np?.art, size: 64, radius: 12),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.2,
                    color: Colors.white,
                    fontFamilyFallback: islandFontFallback,
                  ),
                ),
                const SizedBox(height: 2),
                if (album.isNotEmpty && album != title)
                  Text(
                    album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF)),
                  ),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Color(0x80FFFFFF)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IslandAppBadge(app: np?.app ?? ''),
                    const SizedBox(width: 4),
                    _ctl(Icons.skip_previous_rounded, 'prev'),
                    _ctl(np?.playing ?? false ? Icons.pause_rounded : Icons.play_arrow_rounded, 'toggle', size: 23),
                    _ctl(Icons.skip_next_rounded, 'next'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A strip of dates that works like a picker: whichever date sits in the
/// middle is picked, and everything planned for it shows below. Drag or use
/// the wheel to move through the days; it settles on a date when you stop.
class _DayScroller extends StatefulWidget {
  const _DayScroller({required this.events, required this.onOpen});
  final List<DayEvent> events;
  final VoidCallback onOpen;

  @override
  State<_DayScroller> createState() => _DayScrollerState();
}

class _DayScrollerState extends State<_DayScroller> {
  static const _itemW = 32.0, _days = 42;
  static const _blue = Color(0xFF0A84FF), _red = Color(0xFFFF453A);

  /// This month's six-week grid: the days whose events are loaded.
  final DateTime _start = () {
    final first = DateTime(DateTime.now().year, DateTime.now().month);
    return DateTime(first.year, first.month, 1 - first.weekday % 7);
  }();
  late int _picked = _day(DateTime.now()).difference(_start).inDays.clamp(0, _days - 1);
  late final ScrollController _scroll = ScrollController(initialScrollOffset: _picked * _itemW)..addListener(_follow);
  double _wheel = 0; // wheel travel not yet turned into a day
  int? _wheelTo;

  DateTime _dateAt(int i) => DateTime(_start.year, _start.month, _start.day + i);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The date in the middle is the picked one.
  void _follow() {
    final i = (_scroll.offset / _itemW).round().clamp(0, _days - 1);
    if (i != _picked) setState(() => _picked = i);
  }

  void _goTo(int i) {
    _wheelTo = i.clamp(0, _days - 1);
    _scroll.animateTo(_wheelTo! * _itemW, duration: const Duration(milliseconds: 180), curve: Curves.easeOutCubic);
  }

  /// When a drag or fling stops between dates, settle on the nearest one.
  bool _onScrollEnd(ScrollEndNotification n) {
    final target = (_scroll.offset / _itemW).round() * _itemW;
    if ((target - _scroll.offset).abs() > 0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOutCubic);
        }
      });
    }
    _wheelTo = null;
    return false;
  }

  /// Each wheel notch (or trackpad equivalent) moves one day.
  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _wheel += e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
      var steps = 0;
      while (_wheel.abs() >= 40) {
        steps += _wheel.sign.toInt();
        _wheel -= _wheel.sign * 40;
      }
      if (steps != 0) _goTo((_wheelTo ?? _picked) + steps);
    });
  }

  Widget _date(int i, DateTime today) {
    final d = _dateAt(i);
    final picked = i == _picked, isToday = d == today;
    final has = widget.events.any((e) => e.on(d));
    final Color num;
    if (isToday) {
      num = _red;
    } else if (picked) {
      num = _blue;
    } else if (d.isBefore(today)) {
      num = const Color(0x66FFFFFF);
    } else {
      num = Colors.white;
    }
    return GestureDetector(
      onTap: () => _goTo(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          children: [
            Text(
              dayShort[d.weekday - 1].toUpperCase(),
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: isToday
                    ? _red.withValues(alpha: picked ? 1 : 0.7)
                    : (picked ? const Color(0xCCFFFFFF) : const Color(0x4DFFFFFF)),
              ),
            ),
            const SizedBox(height: 1),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              // Merged so the island's Inter carries through.
              style: DefaultTextStyle.of(context).style.merge(TextStyle(
                fontSize: picked ? 17 : 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: num,
              )),
              child: Text(d.day.toString().padLeft(2, '0')),
            ),
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: has ? (picked ? num : const Color(0x99FFFFFF)) : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final day = _dateAt(_picked);
    final list =
        [
          for (final e in widget.events)
            if (e.on(day)) e,
        ]..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          return a.start.compareTo(b.start);
        });
    final String dayName;
    if (day == today) {
      dayName = 'today';
    } else if (day == DateTime(today.year, today.month, today.day + 1)) {
      dayName = 'tomorrow';
    } else {
      dayName = '${dayShort[day.weekday - 1]} ${day.day}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              // The month of the picked day; opens the Today tab.
              GestureDetector(
                onTap: widget.onOpen,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: SizedBox(
                    width: 40,
                    child: Text(
                      monthShort[day.month - 1],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Room either side so the first and last days can reach the middle.
                    final side = math.max(0.0, (box.maxWidth - _itemW) / 2);
                    return Listener(
                      onPointerSignal: _onWheel,
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: _onScrollEnd,
                        child: ScrollConfiguration(
                          behavior: const _DragAnywhere(),
                          child: ShaderMask(
                            // Soft edges so dates slide in and out of view.
                            shaderCallback: (r) => const LinearGradient(
                              colors: [Color(0x00FFFFFF), Colors.white, Colors.white, Color(0x00FFFFFF)],
                              stops: [0, 0.18, 0.82, 1],
                            ).createShader(r),
                            blendMode: BlendMode.dstIn,
                            child: ListView.builder(
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(horizontal: side),
                              itemCount: _days,
                              itemExtent: _itemW,
                              itemBuilder: (_, i) => _date(i, today),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_available_rounded, size: 15, color: Color(0x66FFFFFF)),
                      const SizedBox(width: 6),
                      Text('Nothing for $dayName', style: _dim),
                    ],
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    for (final e in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Opacity(
                          opacity: !e.allDay && e.end.isBefore(DateTime.now()) ? 0.45 : 1,
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 13,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2)),
                              ),
                              SizedBox(
                                width: 58,
                                child: Text(
                                  e.allDay ? 'All day' : _clock(e.start),
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  e.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Color(0xCCFFFFFF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Lets the mouse drag the date strip, not just touch.
class _DragAnywhere extends MaterialScrollBehavior {
  const _DragAnywhere();
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// The first few watchlist tickers: symbol, price and the day's change.
class _StocksPreview extends StatelessWidget {
  const _StocksPreview({required this.symbols, required this.quotes});
  final List<String> symbols;
  final Map<String, StockData> quotes;

  @override
  Widget build(BuildContext context) {
    if (symbols.isEmpty) {
      return const Center(
        child: Text('No stocks in your watchlist', style: _dim, textAlign: TextAlign.center),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (final s in symbols) _row(s, quotes[s])],
    );
  }

  Widget _row(String sym, StockData? d) {
    final up = (d?.change ?? 0) >= 0;
    // Price under the ticker, so both fit the narrow card.
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sym,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.15),
              ),
              Text(
                d == null ? '...' : (d.price < 5 ? d.price.toStringAsFixed(4) : d.price.toStringAsFixed(2)),
                style: const TextStyle(fontSize: 10, color: Color(0x99FFFFFF), height: 1.15),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: d == null ? const Color(0x14FFFFFF) : (up ? _up : _down).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            d == null ? '' : '${up ? '+' : '-'}${d.pct.abs().toStringAsFixed(2)}%',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: up ? _up : _down),
          ),
        ),
      ],
    );
  }
}

/// Quick-launch shortcuts as a slim column of icons; hover for the name.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.shortcuts, required this.onTap});
  final List<IslandShortcut> shortcuts;
  final void Function(IslandShortcut)? onTap;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(14)),
    child: shortcuts.isEmpty
        ? const Center(child: Icon(Icons.add_rounded, size: 16, color: Color(0x66FFFFFF)))
        : Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final s in shortcuts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Tooltip(
                        message: s.label,
                        waitDuration: const Duration(milliseconds: 400),
                        preferBelow: false,
                        child: IslandPressable(
                          onTap: () => onTap?.call(s),
                          child: ShortcutGlyph(s, size: 23, radius: 7, iconSize: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
  );
}
