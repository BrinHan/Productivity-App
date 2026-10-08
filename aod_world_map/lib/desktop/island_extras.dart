import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'agenda_service.dart' show meetingAppOf;
import 'island_controller.dart';
import 'island_services.dart';
import 'island_widgets.dart';

// The island's newer pages: quick capture, the timer, weather and clipboard,
// plus the pills for a running timer and a meeting that starts soon.

const _dim = Color(0x8CFFFFFF), _faint = Color(0x59FFFFFF), _fill = Color(0x14FFFFFF);
const _tab = [FontFeature.tabularFigures()];

String _hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _left(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

Widget _chip(String label, VoidCallback onTap, {bool on = false, IconData? icon}) => IslandPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: on ? Colors.black : Colors.white),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.black : Colors.white)),
        ]),
      ),
    );

Widget _iconBtn(IconData icon, String label, VoidCallback onTap, {double size = 16, Color color = _dim}) =>
    IslandPressable(
      onTap: onTap,
      label: label,
      child: SizedBox(width: 28, height: 28, child: Icon(icon, size: size, color: color)),
    );

InputDecoration _field(String hint, {IconData? icon}) => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: _fill,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0x66FFFFFF)),
      prefixIcon: icon == null ? null : Icon(icon, size: 16, color: const Color(0x99FFFFFF)),
      prefixIconConstraints: const BoxConstraints(minWidth: 32),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );

/// Rebuilds once a second while shown.
mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

// ----------------------------------------------------------- quick capture

/// What a quick-capture line asks for: "call mum 15m tomorrow" is a 15
/// minute task for tomorrow called "call mum".
({String title, int minutes, int days}) parseCapture(String raw) {
  var text = ' ${raw.trim()} ';
  var minutes = 30, days = 0;
  final dur = RegExp(r'\s(\d{1,3})\s?(m|min|mins|h|hr|hrs)(?=\s)', caseSensitive: false).firstMatch(text);
  if (dur != null) {
    final n = int.parse(dur.group(1)!);
    minutes = dur.group(2)!.toLowerCase().startsWith('h') ? n * 60 : n;
    text = text.replaceRange(dur.start, dur.end, ' ');
  }
  final day = RegExp(r'\s(today|tomorrow|tmrw)(?=\s)', caseSensitive: false).firstMatch(text);
  if (day != null) {
    days = day.group(1)!.toLowerCase() == 'today' ? 0 : 1;
    text = text.replaceRange(day.start, day.end, ' ');
  }
  return (title: text.replaceAll(RegExp(r'\s+'), ' ').trim(), minutes: minutes.clamp(5, 600).toInt(), days: days);
}

class IslandCapturePage extends StatefulWidget {
  const IslandCapturePage({super.key, required this.c});
  final IslandController c;

  @override
  State<IslandCapturePage> createState() => _IslandCapturePageState();
}

class _IslandCapturePageState extends State<IslandCapturePage> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final p = parseCapture(_text.text);
    final planner = widget.c.planner;
    if (p.title.isNotEmpty && planner != null) {
      planner.add(DateTime.now().add(Duration(days: p.days)), p.title, minutes: p.minutes);
    }
    widget.c.endCapture();
  }

  @override
  Widget build(BuildContext context) {
    final p = parseCapture(_text.text);
    final when = p.days == 0 ? 'today' : 'tomorrow';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.c.endCapture},
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _add(),
              style: const TextStyle(fontSize: 14, color: Colors.white),
              cursorColor: Colors.white,
              decoration: _field('Add a task…  try "email Sam 15m tomorrow"', icon: Icons.add_task_rounded),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          p.title.isEmpty ? 'Enter to add · Esc to cancel' : 'Adds "${p.title}" to $when · ${p.minutes}m',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: _dim),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------- timer

const kTimerOrange = Color(0xFFFF9F0A);

/// mm:ss, or h:mm:ss from an hour up.
String timerText(Duration d) => _left(Duration(seconds: (d.inMilliseconds / 1000).ceil()));

/// The Clock tab: one timer, set on a dial like the iPhone's. Drag or scroll
/// the ruler to pick a length, then Start. While it runs the ruler follows
/// the time left, and the pill shows it when the island closes.
class IslandClockPage extends StatefulWidget {
  const IslandClockPage({super.key, required this.c});
  final IslandController c;

  @override
  State<IslandClockPage> createState() => _IslandClockPageState();
}

class _IslandClockPageState extends State<IslandClockPage> with SingleTickerProviderStateMixin {
  static const _maxMinutes = 180.0;

  /// The dial position in minutes, fractional while it moves.
  late double _value = widget.c.timers.pick.inSeconds / 60;
  late final AnimationController _fling = AnimationController.unbounded(vsync: this)..addListener(_onFling);
  bool _snapping = false;

  TimerModel get _t => widget.c.timers;

  @override
  void dispose() {
    _fling.dispose();
    super.dispose();
  }

  void _set(double minutes) {
    _value = minutes.clamp(0.0, _maxMinutes);
    _t.setPick(Duration(minutes: _value.round()));
    setState(() {});
  }

  void _onFling() {
    _set(_fling.value);
    if ((_value <= 0 || _value >= _maxMinutes) && !_snapping) _fling.stop();
  }

  void _drag(DragUpdateDetails d) {
    _fling.stop();
    _set(_value - d.delta.dx / TimerDialPainter.pxPerMinute);
  }

  void _release(DragEndDetails d) {
    final v = -d.velocity.pixelsPerSecond.dx / TimerDialPainter.pxPerMinute;
    _snapping = false;
    _fling.value = _value;
    _fling.animateWith(FrictionSimulation(0.05, _value, v)).whenComplete(_snap);
  }

  /// Settle on the nearest whole minute.
  void _snap() {
    if (!mounted || _snapping) return;
    _snapping = true;
    _fling.value = _value;
    _fling
        .animateTo(_value.roundToDouble(), duration: const Duration(milliseconds: 180), curve: Curves.easeOut)
        .whenComplete(() => _snapping = false);
  }

  void _scroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _t.running) return;
    final d = e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs() ? e.scrollDelta.dx : e.scrollDelta.dy;
    _fling.stop();
    _set(_value.roundToDouble() + (d > 0 ? 1 : -1));
  }

  Widget _button(String label, VoidCallback onTap, {bool primary = true}) => IslandPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: primary ? const Color(0x40FF9F0A) : const Color(0x24FFFFFF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: primary ? kTimerOrange : Colors.white)),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.c, _t]),
        builder: (context, _) {
          final t = _t;
          final running = t.running;
          final shown = running ? t.remaining : Duration(minutes: _value.round());
          final dial = running ? t.remaining.inMilliseconds / 60000 : _value;
          final rang = widget.c.rangAt;
          final justRang = !running && rang != null && DateTime.now().difference(rang) < const Duration(minutes: 1);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 18, 12),
            child: Column(children: [
              Expanded(
                child: Listener(
                  onPointerSignal: _scroll,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragDown: running ? null : (_) => _fling.stop(),
                    onHorizontalDragUpdate: running ? null : _drag,
                    onHorizontalDragEnd: running ? null : _release,
                    child: MouseRegion(
                      cursor: running ? SystemMouseCursors.basic : SystemMouseCursors.resizeLeftRight,
                      child: CustomPaint(
                        painter: TimerDialPainter(dial, dim: running && t.paused),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                if (!running) ...[
                  _button(justRang ? 'Restart' : 'Start Timer', () {
                    _fling.stop();
                    _set(_value.roundToDouble());
                    t.start();
                  }),
                  if (justRang) ...[
                    const SizedBox(width: 10),
                    const Text('Done', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTimerOrange)),
                  ],
                ] else ...[
                  _button(t.paused ? 'Resume' : 'Pause', t.togglePause),
                  const SizedBox(width: 8),
                  _button('Cancel', t.cancel, primary: false),
                ],
                const Spacer(),
                Text(
                  timerText(shown),
                  style: TextStyle(
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -1,
                    fontFeatures: _tab,
                    color: running && t.paused ? const Color(0x99FF9F0A) : kTimerOrange,
                  ),
                ),
              ]),
            ]),
          );
        },
      );
}

/// The ruler: a tick every half minute, a longer one and a number every
/// five, sliding under a fixed pointer in the middle. Ticks fade out
/// towards both ends.
class TimerDialPainter extends CustomPainter {
  TimerDialPainter(this.minutes, {this.dim = false});
  final double minutes;
  final bool dim;

  static const pxPerMinute = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const labelH = 16.0, pointerH = 9.0;
    final tickTop = labelH + 4, tickBottom = size.height - pointerH - 4;
    final tickH = tickBottom - tickTop;
    final color = dim ? const Color(0x99FF9F0A) : kTimerOrange;
    final from = (minutes - cx / pxPerMinute).floor() - 1, to = (minutes + cx / pxPerMinute).ceil() + 1;
    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var half = from * 2; half <= to * 2; half++) {
      final m = half / 2;
      if (m < 0) continue;
      final x = cx + (m - minutes) * pxPerMinute;
      if (x < -2 || x > size.width + 2) continue;
      final fade = (1 - ((x - cx).abs() / cx)).clamp(0.0, 1.0);
      final a = Curves.easeOut.transform(fade);
      final major = half % 10 == 0;
      final h = major ? tickH : tickH * 0.62;
      tick.color = color.withValues(alpha: a * (major ? 1 : 0.75));
      canvas.drawLine(Offset(x, tickBottom - h), Offset(x, tickBottom), tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${m.toInt()}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: islandFontFallback,
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5 * a),
              fontFeatures: _tab,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 0));
        tp.dispose();
      }
    }
    // The pointer, just under the ticks.
    canvas.drawPath(
      Path()
        ..moveTo(cx, tickBottom + 3)
        ..lineTo(cx + 6, tickBottom + 3 + pointerH)
        ..lineTo(cx - 6, tickBottom + 3 + pointerH)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(TimerDialPainter old) => old.minutes != minutes || old.dim != dim;
}

/// The timer while the island rests: an orange timer glyph and the time
/// left, like the iPhone's. Tapping opens the Clock tab.
class IslandTimerContent extends StatelessWidget {
  const IslandTimerContent({super.key, required this.c});
  final IslandController c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c.timers,
        builder: (context, _) {
          final t = c.timers;
          final total = t.total?.inMilliseconds ?? 1;
          final done = 1 - t.remaining.inMilliseconds / total;
          final color = t.paused ? const Color(0x99FF9F0A) : kTimerOrange;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: done.clamp(0.0, 1.0),
                    strokeWidth: 3,
                    backgroundColor: const Color(0x33FF9F0A),
                    color: color,
                  ),
                  Icon(t.paused ? Icons.pause_rounded : Icons.timer_outlined, size: 13, color: color),
                ]),
              ),
              const Spacer(),
              Text(
                timerText(t.remaining),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, fontFeatures: _tab, color: color),
              ),
            ]),
          );
        },
      );
}

/// The weather under the time on the island's home: icon, temperature and
/// what it's doing. Tapping opens the full weather.
class IslandWeatherLine extends StatelessWidget {
  const IslandWeatherLine({super.key, required this.c});
  final IslandController c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c.weather,
        builder: (context, _) {
          final w = c.weather.now;
          if (w == null) return const SizedBox.shrink();
          final t = c.fahrenheit ? w.temp * 9 / 5 + 32 : w.temp;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => c.setPage(IslandPage.weather),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(weatherIcon(w.code, day: w.day), size: 13, color: const Color(0xFFFFD27A)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${t.round()}°  ${weatherLabel(w.code)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF)),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

// ----------------------------------------------------------------- weather

class IslandWeatherPage extends StatefulWidget {
  const IslandWeatherPage({super.key, required this.c});
  final IslandController c;

  @override
  State<IslandWeatherPage> createState() => _IslandWeatherPageState();
}

class _IslandWeatherPageState extends State<IslandWeatherPage> {
  @override
  void initState() {
    super.initState();
    widget.c.weather.refresh();
  }

  String _deg(double celsius) {
    final v = widget.c.fahrenheit ? celsius * 9 / 5 + 32 : celsius;
    return '${v.round()}°';
  }

  static String _daylight(Duration d) => '${d.inHours}h ${d.inMinutes % 60}m';

  Widget _sun(IconData icon, String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: _fill, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(icon, size: 18, color: const Color(0xFFFFB86B)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 10.5, color: _dim)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: _tab)),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.c, widget.c.weather]),
        builder: (context, _) {
          final s = widget.c.weather;
          final w = s.now;
          if (w == null) {
            return Center(
              child: s.loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _dim))
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(s.error ?? 'No weather yet.', style: const TextStyle(fontSize: 13, color: _dim)),
                      const SizedBox(height: 8),
                      _chip('Try again', () => s.refresh(force: true), icon: Icons.refresh_rounded),
                    ]),
            );
          }
          final f = widget.c.fahrenheit;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 18, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(weatherIcon(w.code, day: w.day), size: 46, color: const Color(0xFFFFD27A)),
                const SizedBox(width: 14),
                Text(_deg(w.temp),
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w300, letterSpacing: -1.5, height: 1)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(weatherLabel(w.code), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      [if (w.place.isNotEmpty) w.place, 'feels ${_deg(w.feels)}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _dim),
                    ),
                    Text('H ${_deg(w.hi)}  L ${_deg(w.lo)}', style: const TextStyle(fontSize: 12, color: _dim)),
                  ]),
                ),
                Column(children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _chip('°C', () => widget.c.setFahrenheit(false), on: !f),
                    const SizedBox(width: 4),
                    _chip('°F', () => widget.c.setFahrenheit(true), on: f),
                  ]),
                  const SizedBox(height: 4),
                  if (s.loading)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: _dim)),
                      ),
                    )
                  else
                    _iconBtn(Icons.refresh_rounded, 'Refresh', () => s.refresh(force: true)),
                ]),
              ]),
              const Spacer(),
              Row(children: [
                if (w.sunrise case final rise?) _sun(Icons.wb_twilight_rounded, 'Sunrise', _hm(rise)),
                const SizedBox(width: 8),
                if (w.sunset case final set?) _sun(Icons.nights_stay_rounded, 'Sunset', _hm(set)),
                const SizedBox(width: 8),
                if (w.sunrise != null && w.sunset != null)
                  _sun(Icons.light_mode_outlined, 'Daylight', _daylight(w.sunset!.difference(w.sunrise!))),
              ]),
            ]),
          );
        },
      );
}

// --------------------------------------------------------------- clipboard

class IslandClipboardPage extends StatefulWidget {
  const IslandClipboardPage({super.key, required this.c});
  final IslandController c;

  @override
  State<IslandClipboardPage> createState() => _IslandClipboardPageState();
}

class _IslandClipboardPageState extends State<IslandClipboardPage> {
  final _search = TextEditingController();
  String? _copied;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _search.dispose();
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String s) async {
    await widget.c.clipboard.copy(s);
    if (!mounted) return;
    setState(() => _copied = s);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  Widget _item(ClipboardHistory h, String s) {
    final copied = _copied == s;
    return IslandPressable(
      onTap: () => _copy(s),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
        decoration: BoxDecoration(
          color: copied ? const Color(0x2630D158) : _fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              s.trim().replaceAll(RegExp(r'\s+'), ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.3),
            ),
          ),
          if (copied)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('Copied', style: TextStyle(fontSize: 11, color: Color(0xFF30D158))),
            )
          else
            _iconBtn(Icons.close_rounded, 'Remove', () => h.remove(s), size: 14, color: _faint),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.c.clipboard,
        builder: (context, _) {
          final h = widget.c.clipboard;
          final q = _search.text.trim().toLowerCase();
          final items = [for (final s in h.items) if (q.isEmpty || s.toLowerCase().contains(q)) s];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 12.5, color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: _field('Search what you copied', icon: Icons.search_rounded),
                    ),
                  ),
                ),
                if (h.items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _chip('Clear', h.clear),
                ],
              ]),
              const SizedBox(height: 6),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          h.items.isEmpty
                              ? 'Copy some text and it shows up here.\nKept in memory only, never saved.'
                              : 'Nothing matches.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: _faint, height: 1.4),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) => _item(h, items[i]),
                      ),
              ),
            ]),
          );
        },
      );
}

// --------------------------------------------------------- meeting soon pill

/// Something starts in a few minutes: count down, and offer Join for a
/// call or Focus for a planner task.
class IslandUpcomingContent extends StatefulWidget {
  const IslandUpcomingContent({super.key, required this.c});
  final IslandController c;

  @override
  State<IslandUpcomingContent> createState() => _IslandUpcomingContentState();
}

class _IslandUpcomingContentState extends State<IslandUpcomingContent> with _Ticking {
  @override
  Widget build(BuildContext context) {
    final e = widget.c.soon;
    if (e == null) return const SizedBox.shrink();
    final until = e.start.difference(DateTime.now());
    final when = until.inSeconds > 0 ? 'Starts in ${_left(until)}' : 'Started ${_left(-until)} ago';
    final task = e.feed == IslandController.kTaskFeed;
    final call = e.link.isNotEmpty;
    final where = call ? meetingAppOf(e.link) : e.location.split('\n').first.trim();
    final (String? action, VoidCallback? onAction, Color actionColor) = call
        ? ('Join', widget.c.joinSoon, const Color(0xFF30D158))
        : task && widget.c.soonTask != null
            ? ('Focus', widget.c.focusSoon, const Color(0xFF0A84FF))
            : (null, null, Colors.transparent);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(13)),
          child: Icon(
            call ? Icons.videocam_rounded : task ? Icons.task_alt_rounded : Icons.event_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(where.isEmpty ? when : '$when · $where',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Color(0x99FFFFFF), fontFeatures: _tab)),
          ]),
        ),
        _iconBtn(Icons.close_rounded, 'Dismiss', widget.c.dismissSoon, color: const Color(0x99FFFFFF)),
        if (action != null) ...[
          const SizedBox(width: 6),
          IslandPressable(
            onTap: onAction!,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(color: actionColor, borderRadius: BorderRadius.circular(18)),
              child: Text(action, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}
