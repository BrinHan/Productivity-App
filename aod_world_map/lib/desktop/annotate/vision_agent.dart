import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../process_link.dart' show appDataDir;
import 'annotation_model.dart';

/// One screen grab ready to send: the monitor with your annotations drawn
/// on it, downscaled. [toLogical] maps image pixels back to the overlay.
class ScreenCapture {
  const ScreenCapture({
    required this.png,
    required this.width,
    required this.height,
    required this.toLogical,
    required this.overlay,
    required this.annotations,
    this.app,
  });
  final Uint8List png;
  final int width, height;
  final double toLogical;
  final Size overlay;
  final List<Map<String, dynamic>> annotations; // already in image pixels
  final String? app;
}

const _model = 'claude-sonnet-5-5';
const _endpoint = 'https://api.anthropic.com/v1/messages';

const _system = '''
You are a visual assistant living in a transparent overlay on the user's Windows desktop.
Each question comes with a screenshot of their monitor (with anything they drew on it) and a JSON list of their annotations.
All coordinates, theirs and yours, are pixels in that screenshot: x to the right, y down, origin top-left.

Answer briefly and concretely (a few sentences, or a short numbered list for how-to questions).
Use the drawing tools to point at what you're talking about, the way a person would mark up a shared screen:
- draw_box around a control or area you mention; keep labels to a few words.
- render_arrow from empty space toward a small target.
- point_at for "click here".
- highlight_region to spotlight one area and dim the rest (at most one per answer).
- For step-by-step instructions, place_stamp kind "step" with step numbers matching your list, next to each control.
Draw only what helps; 1-6 marks is typical. Be precise: put boxes tightly around the actual pixels of the thing.
If the user circled or marked something, they are probably asking about that.
Write your text answer first, then make the drawing calls.''';

const _xy = {
  'x': {'type': 'number'},
  'y': {'type': 'number'},
};
const _box = {
  ..._xy,
  'w': {'type': 'number'},
  'h': {'type': 'number'},
};

const _tools = [
  {
    'name': 'draw_box',
    'description': 'Draw a rectangle (or ellipse) around a region, optionally labelled.',
    'input_schema': {
      'type': 'object',
      'properties': {
        ..._box,
        'label': {'type': 'string'},
        'shape': {
          'type': 'string',
          'enum': ['rect', 'ellipse'],
        },
      },
      'required': ['x', 'y', 'w', 'h'],
    },
  },
  {
    'name': 'render_arrow',
    'description': 'Draw an arrow from one point to another, optionally labelled at its tail.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'from_x': {'type': 'number'},
        'from_y': {'type': 'number'},
        'to_x': {'type': 'number'},
        'to_y': {'type': 'number'},
        'label': {'type': 'string'},
      },
      'required': ['from_x', 'from_y', 'to_x', 'to_y'],
    },
  },
  {
    'name': 'highlight_region',
    'description': 'Spotlight one region: everything else on screen is dimmed.',
    'input_schema': {
      'type': 'object',
      'properties': _box,
      'required': ['x', 'y', 'w', 'h'],
    },
  },
  {
    'name': 'point_at',
    'description': 'A pulsing marker at a point, e.g. where to click.',
    'input_schema': {
      'type': 'object',
      'properties': _xy,
      'required': ['x', 'y'],
    },
  },
  {
    'name': 'place_stamp',
    'description': 'Place a stamp centred at a point. kind "step" shows a numbered badge.',
    'input_schema': {
      'type': 'object',
      'properties': {
        ..._xy,
        'kind': {
          'type': 'string',
          'enum': ['step', 'check', 'cross', 'question', 'star'],
        },
        'step': {'type': 'integer'},
      },
      'required': ['x', 'y', 'kind'],
    },
  },
  {
    'name': 'add_label',
    'description': 'A short text note with its top-left at a point.',
    'input_schema': {
      'type': 'object',
      'properties': {
        ..._xy,
        'text': {'type': 'string'},
      },
      'required': ['x', 'y', 'text'],
    },
  },
  {
    'name': 'clear_ai_layer',
    'description': 'Remove everything you drew earlier.',
    'input_schema': {'type': 'object', 'properties': <String, dynamic>{}},
  },
];

/// Asks the vision model about the screen and draws its answer onto the AI
/// layer as it streams in.
class VisionAgent extends ChangeNotifier {
  VisionAgent(this.store);
  final AnnotationStore store;

  String question = '';
  String answer = '';
  String? error;
  bool busy = false;
  String? _key;
  http.Client? _client;
  final List<Map<String, dynamic>> _history = [];

  bool get hasKey => _key != null;

  /// The key lives in %APPDATA%\AodWorldMap\anthropic.key (one line), unless
  /// ANTHROPIC_API_KEY is set.
  static File get _keyFile => File('${appDataDir.path}${Platform.pathSeparator}anthropic.key');

  Future<void> loadKey() async {
    final env = Platform.environment['ANTHROPIC_API_KEY'];
    if (env != null && env.trim().isNotEmpty) {
      _key = env.trim();
    } else {
      try {
        final k = (await _keyFile.readAsString()).trim();
        if (k.isNotEmpty) _key = k;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveKey(String key) async {
    key = key.trim();
    if (key.isEmpty) return;
    _key = key;
    error = null;
    try {
      await _keyFile.parent.create(recursive: true);
      await _keyFile.writeAsString(key);
    } catch (_) {}
    notifyListeners();
  }

  /// New conversation; also clears what the AI drew.
  void reset() {
    cancel();
    _history.clear();
    question = answer = '';
    error = null;
    store.dismissAi();
    notifyListeners();
  }

  void fail(String msg) {
    error = msg;
    notifyListeners();
  }

  void cancel() {
    _client?.close();
    _client = null;
    if (busy) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> ask(String q, ScreenCapture cap) async {
    if (_key == null) {
      error = 'Add an Anthropic API key first.';
      notifyListeners();
      return;
    }
    cancel();
    // A cancelled turn can leave a question with no answer; start clean.
    if (_history.isNotEmpty && _history.last['role'] == 'user') _history.clear();
    question = q;
    answer = '';
    error = null;
    busy = true;
    store.dismissAi();
    notifyListeners();

    // Older screenshots are stale; keep the words, drop the pixels.
    for (final m in _history) {
      final c = m['content'];
      if (c is List) {
        for (var i = 0; i < c.length; i++) {
          if (c[i] is Map && c[i]['type'] == 'image') c[i] = {'type': 'text', 'text': '[earlier screenshot omitted]'};
        }
      }
    }
    _history.add({
      'role': 'user',
      'content': [
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': 'image/png', 'data': base64Encode(cap.png)},
        },
        {
          'type': 'text',
          'text': 'Screenshot: ${cap.width}x${cap.height} px.'
              '${cap.app != null ? ' Foreground app: ${cap.app}.' : ''}'
              '\nMy annotations: ${jsonEncode(cap.annotations)}'
              '\n\nQuestion: $q',
        },
      ],
    });

    final client = _client = http.Client();
    try {
      for (var round = 0; round < 4; round++) {
        final stop = await _stream(client, cap);
        if (!identical(_client, client)) return; // cancelled or superseded
        if (stop != 'tool_use') break;
        // Tell the model its marks are on screen so it can finish its turn.
        final calls = [
          for (final b in (_history.last['content'] as List))
            if (b['type'] == 'tool_use') b['id'] as String,
        ];
        _history.add({
          'role': 'user',
          'content': [
            for (final id in calls) {'type': 'tool_result', 'tool_use_id': id, 'content': 'drawn'},
          ],
        });
      }
    } catch (e) {
      if (identical(_client, client)) error = '$e';
    } finally {
      if (identical(_client, client)) {
        client.close();
        _client = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  /// One streamed request. Text shows up as it arrives; each drawing call is
  /// drawn the moment its block completes. Returns the stop reason.
  Future<String?> _stream(http.Client client, ScreenCapture cap) async {
    final req = http.Request('POST', Uri.parse(_endpoint))
      ..headers.addAll({
        'x-api-key': _key!,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      })
      ..body = jsonEncode({
        'model': _model,
        'max_tokens': 1500,
        'stream': true,
        'system': [
          {
            'type': 'text',
            'text': _system,
            'cache_control': {'type': 'ephemeral'},
          },
        ],
        'tools': _tools,
        'messages': _history,
      });
    final res = await client.send(req);
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      var msg = 'HTTP ${res.statusCode}';
      try {
        msg = '${jsonDecode(body)['error']['message']}';
      } catch (_) {}
      throw msg;
    }

    final blocks = <int, Map<String, dynamic>>{};
    final json = <int, StringBuffer>{};
    String? stop;
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final Map<String, dynamic> ev;
      try {
        ev = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (ev['type']) {
        case 'content_block_start':
          final i = ev['index'] as int;
          final b = Map<String, dynamic>.from(ev['content_block'] as Map);
          blocks[i] = b;
          if (b['type'] == 'tool_use') json[i] = StringBuffer();
          if (b['type'] == 'text' && answer.isNotEmpty && !answer.endsWith('\n')) answer += '\n\n';
        case 'content_block_delta':
          final i = ev['index'] as int;
          final d = ev['delta'] as Map;
          if (d['type'] == 'text_delta') {
            final t = d['text'] as String;
            blocks[i]!['text'] = '${blocks[i]!['text'] ?? ''}$t';
            answer += t;
            notifyListeners();
          } else if (d['type'] == 'input_json_delta') {
            json[i]?.write(d['partial_json']);
          }
        case 'content_block_stop':
          final i = ev['index'] as int;
          final b = blocks[i];
          if (b != null && b['type'] == 'tool_use') {
            var input = <String, dynamic>{};
            try {
              final s = json[i].toString();
              if (s.isNotEmpty) input = jsonDecode(s) as Map<String, dynamic>;
            } catch (_) {}
            b['input'] = input;
            _draw('${b['name']}', input, cap);
          }
        case 'message_delta':
          stop = (ev['delta'] as Map)['stop_reason'] as String? ?? stop;
        case 'error':
          throw '${(ev['error'] as Map?)?['message'] ?? 'stream error'}';
      }
    }
    _history.add({
      'role': 'assistant',
      'content': [
        for (final i in (blocks.keys.toList()..sort()))
          if (blocks[i]!['type'] == 'text' && '${blocks[i]!['text'] ?? ''}'.isNotEmpty)
            {'type': 'text', 'text': blocks[i]!['text']}
          else if (blocks[i]!['type'] == 'tool_use')
            {'type': 'tool_use', 'id': blocks[i]!['id'], 'name': blocks[i]!['name'], 'input': blocks[i]!['input'] ?? {}},
      ],
    });
    return stop;
  }

  static const _maxShapes = 40;

  /// Validates one drawing call and maps it from image pixels to the overlay.
  void _draw(String name, Map<String, dynamic> a, ScreenCapture cap) {
    if (name == 'clear_ai_layer') {
      store.dismissAi();
      return;
    }
    if (store.shapes(Layer.ai).length >= _maxShapes) return;
    final k = cap.toLogical;
    final w = cap.overlay.width, h = cap.overlay.height;
    double n(String key) => (a[key] is num) ? (a[key] as num).toDouble() : double.nan;
    bool ok(Offset p) => p.dx.isFinite && p.dy.isFinite;
    Offset pt(String x, String y) {
      final p = Offset(n(x) * k, n(y) * k);
      return ok(p) ? Offset(p.dx.clamp(0, w), p.dy.clamp(0, h)) : p;
    }

    Rect? box() {
      final r = Rect.fromLTWH(n('x') * k, n('y') * k, n('w') * k, n('h') * k);
      if (!r.isFinite || r.width < 2 || r.height < 2) return null;
      return r.intersect(Offset.zero & cap.overlay);
    }

    String? label() {
      final l = a['label'] ?? a['text'];
      if (l is! String || l.trim().isEmpty) return null;
      final s = l.trim();
      return s.length > 80 ? '${s.substring(0, 79)}…' : s;
    }

    final p = pt('x', 'y');
    final Shape? shape = switch (name) {
      'draw_box' => switch (box()) {
          final r? =>
            RectShape(color: kAiColor, width: 3, rect: r, ellipse: a['shape'] == 'ellipse', label: label(), rounded: true),
          null => null,
        },
      'render_arrow' => () {
          final from = pt('from_x', 'from_y'), to = pt('to_x', 'to_y');
          return ok(from) && ok(to)
              ? LineShape(color: kAiColor, width: 4, a: from, b: to, arrow: true, label: label())
              : null;
        }(),
      'highlight_region' => switch (box()) {
          final r? => SpotlightShape(rect: r),
          null => null,
        },
      'point_at' => ok(p) ? PulseShape(at: p) : null,
      'place_stamp' => ok(p)
          ? StampShape(
              color: kAiColor,
              at: p,
              size: 30,
              kind: StampKind.values.where((s) => s.name == a['kind']).firstOrNull ?? StampKind.step,
              step: (a['step'] as num?)?.toInt() ?? 1,
            )
          : null,
      'add_label' => ok(p) && label() != null
          ? TextShape(color: kAiColor, at: p, text: label()!, fontSize: 15, boxed: true)
          : null,
      _ => null,
    };
    if (shape != null) store.aiAdd(shape);
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
