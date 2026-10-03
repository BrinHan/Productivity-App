import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'island_controller.dart';
import 'island_widgets.dart';
import 'stock_insight.dart';
import 'stock_service.dart';

const _up = Color(0xFF30D158), _down = Color(0xFFFF453A), _flat = Color(0xFF98989F);
const _dim = TextStyle(fontSize: 11, color: Color(0x99FFFFFF));
const _tiny = TextStyle(fontSize: 9.5, color: Color(0x80FFFFFF));

Color _signalColor(Signal s) => s == Signal.bullish ? _up : (s == Signal.bearish ? _down : _flat);
String _signalLabel(Signal s) =>
    s == Signal.bullish ? 'Bullish' : (s == Signal.bearish ? 'Bearish' : 'Neutral');

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}

class _SignalPill extends StatelessWidget {
  const _SignalPill(this.signal, {this.big = false});
  final Signal signal;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = _signalColor(signal);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 7, vertical: big ? 4 : 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)),
      child: Text(_signalLabel(signal),
          style: TextStyle(fontSize: big ? 11.5 : 10, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

class StocksPage extends StatefulWidget {
  const StocksPage({super.key, required this.c});
  final IslandController c;

  @override
  State<StocksPage> createState() => _StocksPageState();
}

class _StocksPageState extends State<StocksPage> {
  StockData? _data;
  String? _error;
  bool _loading = false;
  String _key = '';
  StockInsight? _insight;
  bool _insightLoading = false;
  String _insightKey = '';
  int _view = 0; // 0 price, 1 percent, 2 points
  Timer? _refresh, _rotate;

  String get _wantKey => '${widget.c.stockSymbol}|${widget.c.stockRange}';

  @override
  void initState() {
    super.initState();
    _load();
    _loadInsight();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) {
      _load();
      _refreshInsight();
    });
    _rotate = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _view = (_view + 1) % 3);
    });
  }

  @override
  void didUpdateWidget(StocksPage old) {
    super.didUpdateWidget(old);
    if (_key != _wantKey) _load();
    if (_insightKey != widget.c.stockSymbol) {
      _insight = null;
      _loadInsight();
    }
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

  Future<void> _loadInsight() async {
    final sym = widget.c.stockSymbol;
    _insightKey = sym;
    if (mounted) setState(() => _insightLoading = true);
    try {
      final i = await StockInsightService.load(sym);
      if (mounted && _insightKey == sym) setState(() => _insight = i);
    } catch (_) {
      // leave the card in its "unavailable" state
    } finally {
      if (mounted && _insightKey == sym) setState(() => _insightLoading = false);
    }
  }

  void _refreshInsight() {
    final sym = widget.c.stockSymbol;
    StockInsightService.load(sym).then((i) {
      if (mounted && _insightKey == sym) setState(() => _insight = i);
    }).catchError((_) {});
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
    const big = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6);
    final Widget w;
    switch (_view) {
      case 0:
        w = TweenAnimationBuilder<double>(
          key: const ValueKey(0),
          tween: Tween<double>(end: d.price),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text(_money(d, v), style: big.copyWith(color: Colors.white)),
        );
      case 1:
        w = Text('$sign${d.pct.abs().toStringAsFixed(2)}%', key: const ValueKey(1), style: big.copyWith(color: col));
      default:
        w = Text('$sign${d.change.abs().toStringAsFixed(2)} pts',
            key: const ValueKey(2), style: big.copyWith(color: col));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 100),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey(_view);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(0, incoming ? 0.5 : -0.5), end: Offset.zero).animate(anim),
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
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: on ? Colors.black : Colors.white)),
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
        decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: on ? Colors.black : Colors.white70),
      ),
    );
  }

  Widget _status() {
    if (_error == null) return const Text('Loading…', style: _dim);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFFF8A80))),
      const SizedBox(height: 8),
      IslandPressable(
        onTap: _load,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(12)),
          child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }

  Widget _topRow(StockData? d) {
    if (d == null) return Center(child: _status());
    final c = widget.c;
    final up = d.change >= 0;
    final candles = aggregateCandles(d.candles, 44);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0x99FFFFFF))),
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
        child: _Panel(
          child: Stack(children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('${d.symbol}|${c.stockRange}|${c.stockCandles}'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                builder: (_, p, __) => CustomPaint(painter: _ChartPainter(candles, c.stockCandles, d.prevClose, p)),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(color: const Color(0xCC2A2A2D), borderRadius: BorderRadius.circular(9)),
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

  Widget _analysisPanel() {
    final i = _insight;
    final has = i != null && i.sources.isNotEmpty;
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Analysis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (has) _SignalPill(i.verdict, big: true),
        ]),
        const SizedBox(height: 10),
        if (!has)
          Text(_insightLoading ? 'Analyzing…' : 'No analysis available right now', style: _dim)
        else ...[
          _Gauge(score: i.score),
          const SizedBox(height: 12),
          for (final s in i.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                SizedBox(width: 82, child: Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                Expanded(child: Text(s.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: _dim)),
                const SizedBox(width: 8),
                _SignalPill(s.signal),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _newsPanel() {
    final i = _insight;
    final news = i?.news ?? const <NewsItem>[];
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('News', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(_data?.symbol ?? widget.c.stockSymbol, style: _dim),
        ]),
        const SizedBox(height: 6),
        if (i == null)
          Text(_insightLoading ? 'Loading headlines…' : 'Headlines unavailable right now', style: _dim)
        else if (news.isEmpty)
          const Text('No recent headlines', style: _dim)
        else
          for (final n in news.take(6)) _NewsRow(item: n, onTap: () => widget.c.openUrl?.call(n.url)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        physics: const ClampingScrollPhysics(),
        children: [
          SizedBox(height: 150, child: _topRow(_data)),
          const SizedBox(height: 10),
          _analysisPanel(),
          const SizedBox(height: 10),
          _newsPanel(),
          const SizedBox(height: 8),
          const Text(
            'Signals combine analyst ratings, price trend, RSI, MACD and headline tone. '
            'Informational only, not financial advice.',
            style: _tiny,
          ),
        ],
      );
}

/// Bearish -> bullish bar. The marker eases to its new position.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder: (context, c) => TweenAnimationBuilder<double>(
              tween: Tween<double>(end: ((score + 1) / 2).clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, p, __) => Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 3,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(colors: [_down, _flat, _up]),
                    ),
                  ),
                ),
                Positioned(
                  left: (c.maxWidth - 14) * p,
                  top: 0,
                  width: 14,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text('Bearish', style: _tiny), Text('Neutral', style: _tiny), Text('Bullish', style: _tiny)],
        ),
      ]);
}

class _NewsRow extends StatefulWidget {
  const _NewsRow({required this.item, required this.onTap});
  final NewsItem item;
  final VoidCallback onTap;

  @override
  State<_NewsRow> createState() => _NewsRowState();
}

class _NewsRowState extends State<_NewsRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? const Color(0x14FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: _signalColor(n.signal), shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.25)),
                const SizedBox(height: 2),
                Text('${n.publisher} · ${_ago(n.time)}', style: const TextStyle(fontSize: 10.5, color: Color(0x80FFFFFF))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Candles (wick + body) or bars (columns of closing price). Draws in left
/// to right as [progress] goes 0 -> 1.
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
      final p = Paint()
        ..color = (cd.c >= cd.o ? _up : _down).withValues(alpha: a)
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
