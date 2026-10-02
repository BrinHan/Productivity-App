import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class Candle {
  const Candle(this.time, this.o, this.h, this.l, this.c);
  final DateTime time;
  final double o, h, l, c;
}

class StockData {
  const StockData({
    required this.symbol,
    required this.name,
    required this.currency,
    required this.price,
    required this.prevClose,
    required this.candles,
  });
  final String symbol, name, currency;
  final double price, prevClose;
  final List<Candle> candles;

  double get change => price - prevClose;
  double get pct => prevClose == 0 ? 0 : change / prevClose * 100;
}

class StockService {
  /// range: '1d' | '5d' | '1mo'
  static Future<StockData> fetch(String symbol, String range) async {
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) throw Exception('Enter a ticker');
    final interval = range == '5d' ? '30m' : (range == '1mo' ? '1d' : '5m');
    final uri = Uri.https('query1.finance.yahoo.com', '/v8/finance/chart/$sym', {
      'range': range,
      'interval': interval,
    });
    final res = await http.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) throw Exception('Unknown ticker "$sym"');
    if (res.statusCode != 200) throw Exception('Yahoo returned ${res.statusCode}');

    final root = jsonDecode(res.body) as Map<String, dynamic>;
    final chart = root['chart'] as Map<String, dynamic>?;
    final results = chart?['result'];
    if (results is! List || results.isEmpty) throw Exception('No data for "$sym"');
    final r = results.first as Map<String, dynamic>;
    final meta = (r['meta'] as Map<String, dynamic>?) ?? {};
    final ts = (r['timestamp'] as List?) ?? const [];
    final quote = (((r['indicators'] as Map?)?['quote']) as List?)?.first as Map?;
    if (quote == null || ts.isEmpty) throw Exception('No price data for "$sym"');

    final o = quote['open'] as List, h = quote['high'] as List;
    final l = quote['low'] as List, c = quote['close'] as List;
    final candles = <Candle>[];
    for (var i = 0; i < ts.length; i++) {
      if (i >= o.length || i >= h.length || i >= l.length || i >= c.length) break;
      if (o[i] == null || h[i] == null || l[i] == null || c[i] == null) continue;
      candles.add(Candle(
        DateTime.fromMillisecondsSinceEpoch((ts[i] as num).toInt() * 1000),
        (o[i] as num).toDouble(),
        (h[i] as num).toDouble(),
        (l[i] as num).toDouble(),
        (c[i] as num).toDouble(),
      ));
    }
    if (candles.isEmpty) throw Exception('No price data for "$sym"');

    final price = (meta['regularMarketPrice'] as num?)?.toDouble() ?? candles.last.c;
    final prev = (meta['chartPreviousClose'] as num?)?.toDouble() ??
        (meta['previousClose'] as num?)?.toDouble() ??
        candles.first.o;
    return StockData(
      symbol: (meta['symbol'] as String?) ?? sym,
      name: ((meta['shortName'] ?? meta['longName'] ?? meta['exchangeName']) as String?) ?? '',
      currency: (meta['currency'] as String?) ?? 'USD',
      price: price,
      prevClose: prev,
      candles: candles,
    );
  }
}

/// Merges neighbouring candles so at most [maxCount] remain.
List<Candle> aggregateCandles(List<Candle> src, int maxCount) {
  if (src.length <= maxCount) return src;
  final group = (src.length / maxCount).ceil();
  final out = <Candle>[];
  for (var i = 0; i < src.length; i += group) {
    final part = src.sublist(i, math.min(i + group, src.length));
    out.add(Candle(
      part.first.time,
      part.first.o,
      part.map((e) => e.h).reduce(math.max),
      part.map((e) => e.l).reduce(math.min),
      part.last.c,
    ));
  }
  return out;
}
