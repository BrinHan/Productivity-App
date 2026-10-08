import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'island_controller.dart';
import 'island_widgets.dart';
import 'stock_service.dart';
import 'stocks_page.dart';

const _upFill = Color(0xFF1E9E55), _downFill = Color(0xFFE5484D);
const _upLine = Color(0xFF30D158), _downLine = Color(0xFFFF453A);
const _dim = TextStyle(fontSize: 11, color: Color(0x99FFFFFF));

String _price(double v) => v < 5 ? v.toStringAsFixed(4) : v.toStringAsFixed(2);

/// Stocks tab: opens on your watchlist; tapping a row pushes the detail
/// view (chart, analysis, news). Back returns along the same path.
class StocksPage extends StatefulWidget {
  const StocksPage({super.key, required this.c});
  final IslandController c;

  @override
  State<StocksPage> createState() => _StocksPageState();
}

class _StocksPageState extends State<StocksPage> with SingleTickerProviderStateMixin {
  // survives leaving the tab, so the list paints instantly next time
  static final Map<String, StockData> _cache = {};
  static final _push = SpringDescription.withDampingRatio(mass: 1, stiffness: 247, ratio: 1.0);

  final Map<String, String> _errors = {};
  late final AnimationController _nav = AnimationController(vsync: this);
  bool _detail = false;
  Timer? _refresh, _undoTimer;

  bool _adding = false, _busy = false;
  String? _addError;
  final _addCtl = TextEditingController();
  ({String sym, int index})? _undo;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => _loadAll());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _undoTimer?.cancel();
    _nav.dispose();
    _addCtl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() => Future.wait([for (final s in List<String>.of(widget.c.watchlist)) _loadOne(s)]);

  Future<void> _loadOne(String s) async {
    try {
      _cache[s] = await StockService.fetch(s, '1d');
      _errors.remove(s);
    } catch (e) {
      _errors[s] = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() {});
  }

  /// Interruptible: re-targets from the live value and velocity.
  void _go(bool detail) {
    _detail = detail;
    _nav.animateWith(SpringSimulation(_push, _nav.value, detail ? 1.0 : 0.0, _nav.velocity));
    setState(() {});
  }

  void _open(String sym) {
    widget.c.setStockSymbol(sym);
    _go(true);
  }

  Future<void> _submitAdd() async {
    final s = _addCtl.text.trim().toUpperCase();
    if (s.isEmpty || _busy) return;
    if (widget.c.watchlist.contains(s)) {
      setState(() => _addError = '$s is already in your watchlist');
      return;
    }
    setState(() {
      _busy = true;
      _addError = null;
    });
    try {
      _cache[s] = await StockService.fetch(s, '1d');
      widget.c.addWatch(s);
      _addCtl.clear();
      if (mounted) setState(() => _adding = false);
    } catch (e) {
      if (mounted) setState(() => _addError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(String sym) {
    final i = widget.c.watchlist.indexOf(sym);
    if (i < 0) return;
    widget.c.removeWatch(sym);
    _undoTimer?.cancel();
    setState(() => _undo = (sym: sym, index: i));
    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _undo = null);
    });
  }

  void _restore() {
    final u = _undo;
    if (u == null) return;
    widget.c.insertWatch(u.index, u.sym);
    _undoTimer?.cancel();
    setState(() => _undo = null);
  }

  // -------------------------------------------------------------- views

  Widget _list() {
    final syms = widget.c.watchlist;
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 12, 4),
          child: Row(children: [
            const Text('Watchlist', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const Spacer(),
            IslandPressable(
              onTap: () => setState(() {
                _adding = !_adding;
                _addError = null;
              }),
              child: Container(
                width: 30,
                height: 28,
                decoration: BoxDecoration(
                  color: _adding ? const Color(0x2EFFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_adding ? Icons.close_rounded : Icons.add_rounded, size: 19, color: Colors.white),
              ),
            ),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _adding
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _addCtl,
                        autofocus: true,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _submitAdd(),
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0x14FFFFFF),
                          hintText: 'Ticker, e.g. AAPL  (Enter to add)',
                          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0x66FFFFFF)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 17, color: Color(0x99FFFFFF)),
                          prefixIconConstraints: const BoxConstraints(minWidth: 34),
                          suffixIcon: _busy
                              ? const Padding(
                                  padding: EdgeInsets.all(9),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    if (_addError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(_addError!, style: const TextStyle(fontSize: 11, color: Color(0xFFFF8A80))),
                      ),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: syms.isEmpty
              ? const Center(child: Text('Your watchlist is empty.\nTap + to add a ticker.', textAlign: TextAlign.center, style: _dim))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  physics: const ClampingScrollPhysics(),
                  itemCount: syms.length,
                  itemBuilder: (_, i) => _WatchRow(
                    key: ValueKey(syms[i]),
                    sym: syms[i],
                    data: _cache[syms[i]],
                    error: _errors[syms[i]],
                    last: i == syms.length - 1,
                    onTap: () => _open(syms[i]),
                    onRemove: () => _remove(syms[i]),
                  ),
                ),
        ),
      ]),
      if (_undo != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Removed ${_undo!.sym}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                IslandPressable(
                  onTap: _restore,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: const Text('Undo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
                  ),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _nav,
        builder: (context, _) {
          final p = _nav.value.clamp(0.0, 1.0).toDouble();
          final sym = widget.c.stockSymbol;
          return ClipRect(
            child: Stack(children: [
              if (p < 1)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: _detail,
                    child: Opacity(
                      opacity: 1 - p,
                      child: FractionalTranslation(translation: Offset(-0.22 * p, 0), child: _list()),
                    ),
                  ),
                ),
              if (p > 0 || _detail)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_detail,
                    child: Opacity(
                      opacity: p,
                      child: FractionalTranslation(
                        translation: Offset(1 - p, 0),
                        child: StockDetailPage(
                          key: ValueKey(sym),
                          c: widget.c,
                          onBack: () => _go(false),
                          watched: widget.c.watchlist.contains(sym),
                          onToggleWatch: () {
                            if (widget.c.watchlist.contains(sym)) {
                              widget.c.removeWatch(sym);
                            } else {
                              widget.c.addWatch(sym);
                              _loadOne(sym);
                            }
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          );
        },
      );
}

class _WatchRow extends StatefulWidget {
  const _WatchRow({
    super.key,
    required this.sym,
    required this.data,
    required this.error,
    required this.last,
    required this.onTap,
    required this.onRemove,
  });
  final String sym;
  final StockData? data;
  final String? error;
  final bool last;
  final VoidCallback onTap, onRemove;

  @override
  State<_WatchRow> createState() => _WatchRowState();
}

class _WatchRowState extends State<_WatchRow> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final up = (d?.change ?? 0) >= 0;
    final tint = up ? _upLine : _downLine;
    return Column(children: [
      MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          // Only scale and colour change on hover. Nothing in the layout moves.
          child: AnimatedScale(
            scale: _down ? 0.985 : (_hover ? 1.03 : 1.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(8, 9, 4, 9),
              decoration: BoxDecoration(
                color: _hover ? tint.withValues(alpha: 0.11) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.sym,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                    const SizedBox(height: 1),
                    Text(
                      d?.name.isNotEmpty == true ? d!.name : (widget.error ?? ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: Color(0x80FFFFFF)),
                    ),
                  ]),
                ),
                SizedBox(
                  width: 110,
                  height: 34,
                  child: d == null
                      ? const SizedBox.shrink()
                      : TweenAnimationBuilder<double>(
                          key: ValueKey('${d.symbol}|${d.candles.length}'),
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          builder: (_, p, _) => CustomPaint(
                            painter: _SparkPainter([for (final c in d.candles) c.c], d.prevClose, p),
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 84,
                  child: d == null
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Text(widget.error == null ? '…' : '—', style: _dim),
                        )
                      : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_price(d.price),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: up ? _upFill : _downFill, borderRadius: BorderRadius.circular(6)),
                            child: Text('${up ? '+' : '-'}${d.pct.abs().toStringAsFixed(2)}%',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                ),
                // Remove: slot is always reserved, only its opacity changes.
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: IgnorePointer(
                    ignoring: !_hover,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onRemove,
                      child: const SizedBox(
                        width: 26,
                        height: 30,
                        child: Icon(Icons.close_rounded, size: 15, color: Color(0xB3FFFFFF)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      if (!widget.last)
        Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8), color: const Color(0x14FFFFFF)),
    ]);
  }
}

/// Day sparkline: green above the previous close, red below, a dotted
/// baseline at the previous close and a dot on the latest price.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.base, this.progress);
  final List<double> v;
  final double base, progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    var lo = math.min(v.reduce(math.min), base), hi = math.max(v.reduce(math.max), base);
    if (hi - lo < 1e-9) hi = lo + 1;
    const padY = 4.0;
    double y(double val) => padY + (1 - (val - lo) / (hi - lo)) * (size.height - 2 * padY);
    final by = y(base);
    final n = v.length;
    final line = Path();
    for (var i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      i == 0 ? line.moveTo(x, y(v[i])) : line.lineTo(x, y(v[i]));
    }
    final fill = Path.from(line)
      ..lineTo(size.width, by)
      ..lineTo(0, by)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    void side(Rect clip, Color c, bool above) {
      canvas.save();
      canvas.clipRect(clip);
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, above ? 0 : size.height),
            Offset(0, by),
            [c.withValues(alpha: 0.32), c.withValues(alpha: 0.0)],
          ),
      );
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..color = c,
      );
      canvas.restore();
    }

    side(Rect.fromLTRB(0, 0, size.width, by), _upLine, true);
    side(Rect.fromLTRB(0, by, size.width, size.height), _downLine, false);
    canvas.restore();

    final dash = Paint()
      ..color = const Color(0xA6FFFFFF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawLine(Offset(x, by), Offset(math.min(x + 2, size.width), by), dash);
    }
    if (progress >= 0.98) {
      canvas.drawCircle(Offset(size.width, y(v.last)), 3, Paint()..color = v.last >= base ? _upLine : _downLine);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.progress != progress || o.v != v || o.base != base;
}
