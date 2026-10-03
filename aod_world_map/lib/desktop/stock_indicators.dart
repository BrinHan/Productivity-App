/// Plain math for the analysis card. No Flutter, no network.
double? smaLast(List<double> v, int n) {
  if (v.length < n) return null;
  var s = 0.0;
  for (var i = v.length - n; i < v.length; i++) {
    s += v[i];
  }
  return s / n;
}

List<double> emaSeries(List<double> v, int n) {
  if (v.isEmpty) return [];
  final k = 2 / (n + 1);
  final out = <double>[v.first];
  for (var i = 1; i < v.length; i++) {
    out.add(v[i] * k + out.last * (1 - k));
  }
  return out;
}

/// Wilder's RSI.
double? rsi(List<double> v, [int n = 14]) {
  if (v.length <= n) return null;
  var gain = 0.0, loss = 0.0;
  for (var i = 1; i <= n; i++) {
    final d = v[i] - v[i - 1];
    gain += d > 0 ? d : 0;
    loss += d < 0 ? -d : 0;
  }
  gain /= n;
  loss /= n;
  for (var i = n + 1; i < v.length; i++) {
    final d = v[i] - v[i - 1];
    gain = (gain * (n - 1) + (d > 0 ? d : 0)) / n;
    loss = (loss * (n - 1) + (d < 0 ? -d : 0)) / n;
  }
  if (loss == 0) return 100;
  return 100 - 100 / (1 + gain / loss);
}

/// MACD (12, 26, 9): the last MACD and signal values.
({double macd, double signal})? macd(List<double> v) {
  if (v.length < 35) return null;
  final e12 = emaSeries(v, 12), e26 = emaSeries(v, 26);
  final line = [for (var i = 0; i < v.length; i++) e12[i] - e26[i]];
  final sig = emaSeries(line, 9);
  return (macd: line.last, signal: sig.last);
}
