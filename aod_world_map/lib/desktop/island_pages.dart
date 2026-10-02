import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'island_controller.dart';
import 'island_widgets.dart';
import 'stock_service.dart';

// Layout constants shared with the Pip flight (the seat is a hole in the card).
const double kTabBarH = 38, kHomePadL = 12, kHomePadT = 8, kHomePadB = 12;
const double kCardPad = 10, kSeatW = 78, kCardW = 196;

const Size kOpenHome = Size(500, 156);
const Size kOpenStocks = Size(500, 178);
const Size kOpenSettings = Size(500, 340);

Size openSizeFor(IslandPage p) {
  switch (p) {
    case IslandPage.stocks:
      return kOpenStocks;
    case IslandPage.settings:
      return kOpenSettings;
    case IslandPage.home:
    case IslandPage.music:
      return kOpenHome;
  }
}

/// Centre of Pip's seat, in the open content's coordinates.
Offset homeSeatCenter(Size content) => Offset(
      kHomePadL + kCardPad + kSeatW / 2,
      kTabBarH + kHomePadT + kCardPad +
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

const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _up = Color(0xFF30D158), _down = Color(0xFFFF453A);

String _dateLabel(DateTime d) => '${_dayShort[d.weekday - 1]}, ${_monthShort[d.month - 1]} ${d.day}';

class IslandOpenContent extends StatelessWidget {
  const IslandOpenContent({super.key, required this.c, required this.onShortcut});
  final IslandController c;
  final void Function(IslandShortcut)? onShortcut;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (c.page) {
      case IslandPage.home:
        body = _HomePage(c: c, onShortcut: onShortcut);
      case IslandPage.music:
        body = _MusicPage(c: c);
      case IslandPage.stocks:
        body = _StocksPage(c: c);
      case IslandPage.settings:
        body = _SettingsPage(c: c);
    }
    return Column(
      children: [
        _TopBar(c: c),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
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
        child: Icon(icon, size: 16, color: on ? Colors.white : const Color(0x99FFFFFF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: SizedBox(
          height: 28,
          child: Row(children: [
            _tab(Icons.home_rounded, IslandPage.home),
            const SizedBox(width: 6),
            _tab(Icons.music_note_rounded, IslandPage.music),
            const SizedBox(width: 6),
            _tab(Icons.candlestick_chart_rounded, IslandPage.stocks),
            const Spacer(),
            _tab(Icons.settings_rounded, IslandPage.settings),
          ]),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(kCardPad),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}

// ------------------------------------------------------------------ home

class _HomePage extends StatelessWidget {
  const _HomePage({required this.c, required this.onShortcut});
  final IslandController c;
  final void Function(IslandShortcut)? onShortcut;

  @override
  Widget build(BuildContext context) {
    final np = c.nowPlaying;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kHomePadL, kHomePadT, 12, kHomePadB),
      child: Row(children: [
        SizedBox(
          width: kCardW,
          child: _Card(
            child: Row(children: [
              // Pip's seat: the flying Pip lands here (drawn by the island).
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
                      np != null && np.playing ? '♪ ${np.title}' : _dateLabel(DateTime.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF)),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Card(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              itemCount: c.shortcuts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 34,
              ),
              itemBuilder: (_, i) => _ShortcutPill(
                s: c.shortcuts[i],
                onTap: () => onShortcut?.call(c.shortcuts[i]),
              ),
            ),
          ),
        ),
      ]),
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
    return Text.rich(TextSpan(children: [
      TextSpan(
        text: '$h:${n.minute.toString().padLeft(2, '0')}',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
      TextSpan(
        text: n.hour < 12 ? ' AM' : ' PM',
        style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF)),
      ),
    ]));
  }
}

class _ShortcutPill extends StatelessWidget {
  const _ShortcutPill({required this.s, required this.onTap});
  final IslandShortcut s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IslandPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2D),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(7)),
              child: Icon(kShortcutIcons[s.icon] ?? Icons.bolt, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ]),
        ),
      );
}

// ----------------------------------------------------------------- music

class _MusicPage extends StatelessWidget {
  const _MusicPage({required this.c});
  final IslandController c;

  Widget _ctl(IconData icon, String cmd) => IslandPressable(
        onTap: () => c.sendMusic?.call(cmd),
        child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 26, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    final np = c.nowPlaying;
    final playing = np?.playing ?? false;
    final title = np == null ? 'Nothing playing' : (np.title.isEmpty ? 'Unknown track' : np.title);
    final artist =
        np == null ? 'Play something in any app' : (np.artist.isEmpty ? 'Unknown artist' : np.artist);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(children: [
        IslandArt(path: np?.art, size: 98, radius: 16),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
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
              Text(artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
              const Spacer(),
              Row(children: [
                _ctl(Icons.skip_previous_rounded, 'prev'),
                const SizedBox(width: 8),
                IslandPressable(
                  onTap: () => c.sendMusic?.call('toggle'),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ctl(Icons.skip_next_rounded, 'next'),
                const Spacer(),
                IslandWaveform(active: playing),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- stocks

class _StocksPage extends StatefulWidget {
  const _StocksPage({required this.c});
  final IslandController c;

  @override
  State<_StocksPage> createState() => _StocksPageState();
}

class _StocksPageState extends State<_StocksPage> {
  StockData? _data;
  String? _error;
  bool _loading = false;
  String _key = '';
  int _view = 0; // 0 price, 1 percent, 2 points
  Timer? _refresh, _rotate;

  String get _wantKey => '${widget.c.stockSymbol}|${widget.c.stockRange}';

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => _load());
    _rotate = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _view = (_view + 1) % 3);
    });
  }

  @override
  void didUpdateWidget(_StocksPage old) {
    super.didUpdateWidget(old);
    if (_key != _wantKey) _load();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _rotate?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    _key = _wantKey;
    if (mounted) setState(() => _error = null);
    try {
      final d = await StockService.fetch(widget.c.stockSymbol, widget.c.stockRange);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _loading = false;
    }
    if (mounted && _key != _wantKey) _load();
  }

  String _money(StockData d, double v) {
    const sym = {'USD': r'$', 'EUR': '€', 'GBP': '£', 'JPY': '¥'};
    final s = sym[d.currency];
    return s != null ? '$s${v.toStringAsFixed(2)}' : '${v.toStringAsFixed(2)} ${d.currency}';
  }

  Widget _rotating(StockData d) {
    final up = d.change >= 0;
    final col = up ? _up : _down;
    final sign = up ? '+' : '-';
    final Widget w;
    switch (_view) {
      case 0:
        w = TweenAnimationBuilder<double>(
          key: const ValueKey(0),
          tween: Tween<double>(end: d.price),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text(
            _money(d, v),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: Colors.white),
          ),
        );
      case 1:
        w = Text('$sign${d.pct.abs().toStringAsFixed(2)}%',
            key: const ValueKey(1),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: col));
      default:
        w = Text('$sign${d.change.abs().toStringAsFixed(2)} pts',
            key: const ValueKey(2),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: col));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey(_view);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, incoming ? 0.5 : -0.5),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      layoutBuilder: (cur, prev) => Stack(
        alignment: Alignment.centerLeft,
        children: [...prev, if (cur != null) cur],
      ),
      child: w,
    );
  }

  Widget _rangeChip(String label, String value) {
    final on = widget.c.stockRange == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IslandPressable(
        onTap: () => widget.c.setStockRange(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: on ? Colors.white : const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.black : Colors.white,
              )),
        ),
      ),
    );
  }

  Widget _kindButton(IconData icon, bool candles) {
    final on = widget.c.stockCandles == candles;
    return IslandPressable(
      onTap: () => widget.c.setStockCandles(candles),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 28,
        height: 22,
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: on ? Colors.black : Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final d = _data;
    final Widget body;
    if (d == null) {
      body = Center(
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFFF8A80))),
                const SizedBox(height: 8),
                IslandPressable(
                  onTap: _load,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x1FFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ])
            : const Text('Loading…', style: TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
      );
    } else {
      final up = d.change >= 0;
      final candles = aggregateCandles(d.candles, 44);
      body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 158,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(d.symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              ),
              Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: up ? _up : _down, size: 24),
            ]),
            Text(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Color(0x99FFFFFF))),
            const SizedBox(height: 6),
            SizedBox(height: 30, child: _rotating(d)),
            const SizedBox(height: 4),
            Row(children: [
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 4),
                  width: i == _view ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == _view ? Colors.white : const Color(0x44FFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
            const Spacer(),
            Row(children: [_rangeChip('1D', '1d'), _rangeChip('5D', '5d'), _rangeChip('1M', '1mo')]),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Card(
            child: Stack(children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('${d.symbol}|${c.stockRange}|${c.stockCandles}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 750),
                  curve: Curves.easeOutCubic,
                  builder: (_, p, __) => CustomPaint(
                    painter: _ChartPainter(candles, c.stockCandles, d.prevClose, p),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xCC2A2A2D),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _kindButton(Icons.candlestick_chart_rounded, true),
                    _kindButton(Icons.bar_chart_rounded, false),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]);
    }
    return Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: body);
  }
}

/// Candles (wick + body) or bars (columns of closing price). Draws in
/// left to right as [progress] goes 0 -> 1.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.candles, this.asCandles, this.prevClose, this.progress);
  final List<Candle> candles;
  final bool asCandles;
  final double prevClose, progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    var lo = candles.map((c) => c.l).reduce(math.min);
    var hi = candles.map((c) => c.h).reduce(math.max);
    lo = math.min(lo, prevClose);
    hi = math.max(hi, prevClose);
    if (hi - lo < 1e-9) hi = lo + 1;
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    // dashed previous-close line
    final dash = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    final py = y(prevClose);
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, py), Offset(math.min(x + 4, size.width), py), dash);
    }

    final n = candles.length;
    final slot = size.width / n;
    final bw = math.max(1.6, slot * 0.62);
    final shown = n * progress;
    for (var i = 0; i < n; i++) {
      if (i >= shown) break;
      final a = (shown - i).clamp(0.0, 1.0);
      final cd = candles[i];
      final x = slot * (i + 0.5);
      final col = (cd.c >= cd.o ? _up : _down).withValues(alpha: a);
      final p = Paint()
        ..color = col
        ..isAntiAlias = true;
      if (asCandles) {
        canvas.drawLine(Offset(x, y(cd.h)), Offset(x, y(cd.l)), p..strokeWidth = 1.2);
        final top = y(math.max(cd.o, cd.c));
        final bot = y(math.min(cd.o, cd.c));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x - bw / 2, top, x + bw / 2, math.max(bot, top + 1.4)),
            const Radius.circular(1.2),
          ),
          p,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(x - bw / 2, y(cd.c), x + bw / 2, size.height),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.progress != progress || o.asCandles != asCandles || o.candles != candles;
}

// -------------------------------------------------------------- settings

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.c});
  final IslandController c;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _ticker = TextEditingController(text: widget.c.stockSymbol);
  Timer? _debounce;

  static const _label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white);
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
          child: Text(text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? Colors.black : Colors.white,
              )),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final picked = c.pipColor.toARGB32();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      children: [
        Row(children: [
          const Text('Open island on', style: _label),
          const Spacer(),
          _seg('Click', !c.openOnHover, () => c.setOpenOnHover(false)),
          const SizedBox(width: 6),
          _seg('Hover', c.openOnHover, () => c.setOpenOnHover(true)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Quiet notch in Chrome', style: _label),
          const Spacer(),
          _seg('On', c.quietInChrome, () => c.setQuietInChrome(true)),
          const SizedBox(width: 6),
          _seg('Off', !c.quietInChrome, () => c.setQuietInChrome(false)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
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
              child: Slider(value: c.idleWidth, min: 180, max: 360, onChanged: c.setIdleWidth),
            ),
          ),
          Text('${c.idleWidth.round()}', style: _dim),
        ]),
        Row(children: [
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
                      color: picked == col.toARGB32() ? Colors.white : const Color(0x33FFFFFF),
                      width: picked == col.toARGB32() ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
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
                _debounce = Timer(const Duration(milliseconds: 700), () => c.setStockSymbol(v));
              },
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                hintText: 'AAPL',
                hintStyle: const TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('Shortcuts', style: _label),
        const SizedBox(height: 8),
        for (final s in c.shortcuts) _ShortcutEditor(key: ObjectKey(s), s: s, c: c),
        if (c.shortcuts.length < 6)
          IslandPressable(
            onTap: c.addShortcut,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('+ Add shortcut', style: _dim),
            ),
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
  late final TextEditingController _label = TextEditingController(text: widget.s.label);
  late final TextEditingController _target = TextEditingController(text: widget.s.target);

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
    final i = kShortcutColors.indexWhere((c) => c.toARGB32() == s.color.toARGB32());
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
    s.kind = ShortcutKind.values[(s.kind.index + 1) % ShortcutKind.values.length];
    widget.c.shortcutsChanged();
  }

  Widget _field(TextEditingController ctl, String hint, ValueChanged<String> onChanged) => SizedBox(
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
    final needsTarget = s.kind == ShortcutKind.web || s.kind == ShortcutKind.app;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        IslandPressable(
          onTap: _cycleIcon,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(9)),
            child: Icon(kShortcutIcons[s.icon] ?? Icons.bolt, size: 16, color: Colors.white),
          ),
        ),
        const SizedBox(width: 6),
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
            child: Text(_kindNames[s.kind]!,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 5,
          child: needsTarget
              ? _field(
                  _target,
                  s.kind == ShortcutKind.web ? 'https://…' : 'code, or path to .exe',
                  (v) {
                    s.target = v;
                    widget.c.shortcutsChanged();
                  },
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
      ]),
    );
  }
}
