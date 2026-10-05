import 'dart:convert';

import 'package:http/http.dart' as http;

import 'stock_indicators.dart';

enum Signal { bullish, neutral, bearish }

Signal signalOf(double s) => s > 0.25 ? Signal.bullish : (s < -0.25 ? Signal.bearish : Signal.neutral);

class SourceSignal {
  const SourceSignal(this.name, this.detail, this.score, this.weight);
  final String name, detail;
  final double score, weight; // score -1..1
  Signal get signal => signalOf(score);
}

class NewsItem {
  const NewsItem(this.title, this.publisher, this.url, this.time, this.score);
  final String title, publisher, url;
  final DateTime time;
  final double score; // headline tone -1..1
  Signal get signal => signalOf(score);
}

class StockInsight {
  const StockInsight({required this.sources, required this.news, required this.score});
  final List<SourceSignal> sources;
  final List<NewsItem> news;
  final double score;
  Signal get verdict => signalOf(score);
}

class _Analyst {
  const _Analyst(this.strongBuy, this.buy, this.hold, this.sell, this.strongSell, this.target, this.price);
  final int strongBuy, buy, hold, sell, strongSell;
  final double? target, price;
  int get total => strongBuy + buy + hold + sell + strongSell;
}

/// Combines several sources into one bullish / bearish read. Uses Yahoo
/// Finance's unofficial endpoints: anything that fails is simply left out.
class StockInsightService {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
  static final Map<String, ({DateTime at, StockInsight data})> _cache = {};
  static String? _crumb, _cookie;
  static DateTime? _crumbAt;

  static final _bull = [
    for (final w in ['surge', 'soar', 'jump', 'rally', 'beat', 'record', 'upgrade', 'growth', 'gain',
      'rise', 'climb', 'bull', 'outperform', 'strong', 'profit', 'boost', 'raise', 'win', 'approv', 'expand'])
      RegExp(r'\b' + w),
  ];
  static final _bear = [
    for (final w in ['plunge', 'fall', 'drop', 'slump', 'miss', 'downgrade', 'cut', 'lawsuit', 'probe',
      'investigat', 'weak', 'loss', 'warn', 'decline', 'sell', 'recall', 'fine', 'layoff', 'concern',
      'fear', 'bear', 'slide', 'tumble', 'crash', 'risk'])
      RegExp(r'\b' + w),
  ];

  static double _headlineScore(String title) {
    final s = title.toLowerCase();
    final b = _bull.where((r) => r.hasMatch(s)).length;
    final r = _bear.where((r) => r.hasMatch(s)).length;
    return b + r == 0 ? 0 : (b - r) / (b + r);
  }

  static Future<StockInsight> load(String symbol, {bool force = false}) async {
    final sym = symbol.trim().toUpperCase();
    final hit = _cache[sym];
    if (!force && hit != null && DateTime.now().difference(hit.at).inMinutes < 10) return hit.data;

    final res = await Future.wait<Object?>([_closes(sym), _news(sym), _analysts(sym)]);
    final closes = res[0] as List<double>?;
    final news = res[1] as List<NewsItem>?;
    final an = res[2] as _Analyst?;

    final sources = <SourceSignal>[];

    if (an != null && an.total > 0) {
      final score = (2 * an.strongBuy + an.buy - an.sell - 2 * an.strongSell) / (2 * an.total);
      var d = 'Buy ${an.strongBuy + an.buy} · Hold ${an.hold} · Sell ${an.sell + an.strongSell}';
      final t = an.target, p = an.price;
      if (t != null && p != null && p > 0) {
        final pct = (t / p - 1) * 100;
        d += ' · target ${t.toStringAsFixed(0)} (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}%)';
      }
      sources.add(SourceSignal('Analysts', d, score.clamp(-1.0, 1.0).toDouble(), 0.30));
    }

    if (closes != null) {
      final p = closes.last;
      final s50 = smaLast(closes, 50), s200 = smaLast(closes, 200);
      final parts = <double>[];
      final txt = <String>[];
      if (s50 != null) {
        parts.add(p > s50 ? 1 : -1);
        txt.add(p > s50 ? 'above 50-day' : 'below 50-day');
      }
      if (s200 != null) {
        parts.add(p > s200 ? 1 : -1);
        txt.add(p > s200 ? 'above 200-day' : 'below 200-day');
      }
      if (s50 != null && s200 != null) parts.add(s50 > s200 ? 1 : -1);
      if (parts.isEmpty) {
        final s20 = smaLast(closes, 20);
        if (s20 != null) {
          parts.add(p > s20 ? 1 : -1);
          txt.add(p > s20 ? 'above 20-day' : 'below 20-day');
        }
      }
      if (parts.isNotEmpty) {
        sources.add(SourceSignal('Trend', 'Price ${txt.join(', ')}',
            parts.reduce((a, b) => a + b) / parts.length, 0.25));
      }

      final r = rsi(closes);
      if (r != null) {
        double sc;
        String d;
        if (r >= 70) {
          sc = -0.4;
          d = 'overbought';
        } else if (r >= 55) {
          sc = 0.6;
          d = 'strong momentum';
        } else if (r >= 45) {
          sc = 0;
          d = 'neutral';
        } else if (r > 30) {
          sc = -0.6;
          d = 'weak momentum';
        } else {
          sc = 0.4;
          d = 'oversold';
        }
        sources.add(SourceSignal('Momentum', 'RSI ${r.round()} · $d', sc, 0.15));
      }

      final m = macd(closes);
      if (m != null) {
        final above = m.macd > m.signal;
        final sc = above ? (m.macd > 0 ? 1.0 : 0.4) : (m.macd < 0 ? -1.0 : -0.4);
        sources.add(SourceSignal('MACD', above ? 'MACD above signal line' : 'MACD below signal line', sc, 0.15));
      }
    }

    if (news != null && news.isNotEmpty) {
      final avg = news.map((n) => n.score).reduce((a, b) => a + b) / news.length;
      final pos = news.where((n) => n.score > 0.25).length;
      final neg = news.where((n) => n.score < -0.25).length;
      sources.add(SourceSignal('Headlines', '$pos positive · $neg negative of ${news.length}', avg, 0.15));
    }

    var wsum = 0.0, total = 0.0;
    for (final s in sources) {
      total += s.score * s.weight;
      wsum += s.weight;
    }
    final insight = StockInsight(
      sources: sources,
      news: news ?? const [],
      score: wsum == 0 ? 0 : (total / wsum).clamp(-1.0, 1.0).toDouble(),
    );
    if (sources.isNotEmpty || insight.news.isNotEmpty) {
      _cache[sym] = (at: DateTime.now(), data: insight);
    }
    return insight;
  }

  // ---------------------------------------------------------------- sources

  static Future<List<double>?> _closes(String sym) async {
    try {
      final res = await http.get(
        Uri.https('query1.finance.yahoo.com', '/v8/finance/chart/$sym', {'range': '1y', 'interval': '1d'}),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final r = ((jsonDecode(res.body) as Map)['chart'] as Map)['result'] as List;
      final q = (((r.first as Map)['indicators'] as Map)['quote'] as List).first as Map;
      final out = <double>[
        for (final v in (q['close'] as List))
          if (v is num) v.toDouble(),
      ];
      return out.length >= 20 ? out : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<NewsItem>?> _news(String sym) async {
    try {
      final res = await http.get(
        Uri.https('query1.finance.yahoo.com', '/v1/finance/search', {
          'q': sym,
          'quotesCount': '0',
          'listsCount': '0',
          'newsCount': '8',
          'enableFuzzyQuery': 'false',
        }),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = (jsonDecode(res.body) as Map)['news'] as List?;
      if (list == null) return null;
      final out = <NewsItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        final title = ((e['title'] as String?) ?? '').trim();
        final link = (e['link'] as String?) ?? '';
        if (title.isEmpty || link.isEmpty) continue;
        final ts = (e['providerPublishTime'] as num?)?.toInt() ?? 0;
        out.add(NewsItem(
          title,
          (e['publisher'] as String?) ?? 'Yahoo Finance',
          link,
          DateTime.fromMillisecondsSinceEpoch(ts * 1000),
          _headlineScore(title),
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Yahoo wants a cookie + crumb for analyst data. Best effort.
  static Future<bool> _ensureCrumb() async {
    final at = _crumbAt;
    if (_crumb != null && at != null && DateTime.now().difference(at).inMinutes < 50) return true;
    final r1 = await http
        .get(Uri.https('fc.yahoo.com', '/'), headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 8));
    final sc = r1.headers['set-cookie'] ?? '';
    final m = RegExp(r'A3=[^;]+').firstMatch(sc) ?? RegExp(r'A1=[^;]+').firstMatch(sc);
    if (m == null) return false;
    _cookie = m.group(0);
    final r2 = await http.get(
      Uri.https('query1.finance.yahoo.com', '/v1/test/getcrumb'),
      headers: {'User-Agent': _ua, 'Cookie': _cookie!},
    ).timeout(const Duration(seconds: 8));
    final body = r2.body.trim();
    if (r2.statusCode != 200 || body.isEmpty || body.length > 40 || body.contains('<') || body.contains(' ')) {
      return false;
    }
    _crumb = body;
    _crumbAt = DateTime.now();
    return true;
  }

  static Future<_Analyst?> _analysts(String sym) async {
    try {
      if (!await _ensureCrumb()) return null;
      final res = await http.get(
        Uri.https('query2.finance.yahoo.com', '/v10/finance/quoteSummary/$sym', {
          'modules': 'recommendationTrend,financialData',
          'crumb': _crumb!,
        }),
        headers: {'User-Agent': _ua, 'Cookie': _cookie!},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        if (res.statusCode == 401 || res.statusCode == 403) _crumb = null;
        return null;
      }
      final list = ((jsonDecode(res.body) as Map)['quoteSummary'] as Map)['result'] as List?;
      if (list == null || list.isEmpty) return null;
      final r = list.first as Map;
      final trend = (r['recommendationTrend'] as Map?)?['trend'] as List?;
      if (trend == null || trend.isEmpty) return null;
      final t0 = trend.firstWhere((e) => e is Map && e['period'] == '0m', orElse: () => trend.first) as Map;
      int n(String k) => (t0[k] as num?)?.toInt() ?? 0;
      final fd = r['financialData'] as Map?;
      double? raw(String k) {
        final v = fd?[k];
        return v is Map ? (v['raw'] as num?)?.toDouble() : null;
      }

      return _Analyst(n('strongBuy'), n('buy'), n('hold'), n('sell'), n('strongSell'),
          raw('targetMeanPrice'), raw('currentPrice'));
    } catch (_) {
      return null;
    }
  }
}
