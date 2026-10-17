// Shared parsing for recipe scaling and shopping totals. Unknown text is preserved.
class _Number {
  _Number(this.n, this.d);
  final BigInt n, d;
  _Number operator +(_Number other) =>
      _Number(n * other.d + other.n * d, d * other.d);
  _Number operator *(_Number other) => _Number(n * other.n, d * other.d);
  String get text => _formatFraction(n, d);
}

_Number? _number(String text) {
  final pieces = text.replaceAll(RegExp(r'\s+'), '').split('と');
  if (pieces.length == 2) {
    final a = _number(pieces[0]), b = _number(pieces[1]);
    return a == null || b == null ? null : a + b;
  }
  if (text.length > 40) return null;
  final raw = text.replaceAll(RegExp(r'\s+'), '');
  if (raw.contains('/')) {
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    final n = BigInt.tryParse(parts[0]), d = BigInt.tryParse(parts[1]);
    return n == null || d == null || d <= BigInt.zero ? null : _Number(n, d);
  }
  final parts = raw.split('.');
  final n = BigInt.tryParse(parts.join());
  if (n == null) return null;
  return _Number(
    n,
    BigInt.from(10).pow(parts.length == 2 ? parts[1].length : 0),
  );
}

class _Quantity {
  _Quantity(this.low, this.high, this.unit, this.prefix);
  final _Number low, high;
  final String unit;
  final bool prefix;
  String format() {
    final a = low.text, b = high.text;
    final amount = a == b ? a : '$a〜$b';
    return prefix ? '$unit$amount' : '$amount$unit';
  }
}

_Quantity? _parseQuantity(String source) {
  final value = source
      .trim()
      .replaceAllMapped(
        RegExp('[０-９]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xfee0),
      )
      .replaceAll('．', '.')
      .replaceAll('／', '/');
  const n = r'(?:\d+\s*/\s*\d+|\d+(?:\.\d+)?)';
  const number = '(?:$nと$n|$n)';
  const span = '($number)(?:\\s*[〜～~–—-]\\s*($number))?';
  final prefix = RegExp('^(大さじ|小さじ|カップ)\\s*$span\$').firstMatch(value);
  final suffix = RegExp(
    '^$span\\s*(kg|mg|g|ml|mL|L|個|本|枚|束|袋|片|缶|パック|玉|丁|合|人前|人分)?\$',
  ).firstMatch(value);
  if (prefix == null && suffix == null) return null;
  final low = _number(prefix != null ? prefix[2]! : suffix![1]!);
  final highText = prefix != null ? prefix[3] : suffix![2];
  final high = highText == null ? low : _number(highText);
  if (low == null || high == null || low.n * high.d > high.n * low.d)
    return null;
  return _Quantity(
    low,
    high,
    (prefix != null ? prefix[1]! : suffix![3] ?? '').replaceAll('mL', 'ml'),
    prefix != null,
  );
}

String scaleRecipeQuantity(String source, double multiplier) {
  if (!multiplier.isFinite || multiplier <= 0) return source;
  final quantity = _parseQuantity(source);
  final factor = _number(multiplier.toStringAsFixed(6));
  if (quantity == null || factor == null) return source;
  return _Quantity(
    quantity.low * factor,
    quantity.high * factor,
    quantity.unit,
    quantity.prefix,
  ).format();
}

String _formatFraction(BigInt numerator, BigInt denominator) {
  final gcd = numerator.gcd(denominator);
  final n = numerator ~/ gcd, d = denominator ~/ gcd;
  if (d == BigInt.one) return '$n';
  var remaining = d;
  while (remaining % BigInt.two == BigInt.zero) {
    remaining ~/= BigInt.two;
  }
  while (remaining % BigInt.from(5) == BigInt.zero) {
    remaining ~/= BigInt.from(5);
  }
  if (remaining != BigInt.one) return '$n/$d';
  // Render terminating decimals with integer arithmetic, never rounding quantities.
  final whole = n ~/ d;
  var remainder = n % d;
  final decimals = StringBuffer();
  while (remainder != BigInt.zero) {
    remainder *= BigInt.from(10);
    decimals.write(remainder ~/ d);
    remainder %= d;
  }
  return '$whole.$decimals';
}

String combineShoppingQuantities(Iterable<String> quantities) {
  final groups = <String, _Quantity>{};
  final output = <String>[];
  final texts = <String>{};
  for (final term in quantities.expand((q) => q.split(RegExp(r'\s*[＋+]\s*')))) {
    final value = term.trim().isEmpty ? '分量記載なし' : term.trim();
    final parsed = _parseQuantity(value);
    if (parsed == null) {
      if (texts.add(value)) output.add(value);
      continue;
    }
    final key = '${parsed.prefix}:${parsed.unit}';
    final old = groups[key];
    if (old == null) {
      groups[key] = parsed;
      output.add('\u0000$key');
    } else {
      groups[key] = _Quantity(
        old.low + parsed.low,
        old.high + parsed.high,
        old.unit,
        old.prefix,
      );
    }
  }
  return output
      .map((v) => v.startsWith('\u0000') ? groups[v.substring(1)]!.format() : v)
      .join(' ＋ ');
}
