import 'package:intl/intl.dart';

/// Valor monetário em centavos (inteiro).
///
/// Nunca usamos ponto flutuante binário para valores persistidos: todos os
/// cálculos são feitos em centavos inteiros, o que garante somas exatas.
class Money implements Comparable<Money> {
  final int cents;
  const Money(this.cents);

  /// Constrói a partir de reais e centavos inteiros (ex.: `Money.fromParts(55, 90)`).
  factory Money.fromParts(int reais, [int centavos = 0]) =>
      Money(reais * 100 + (reais < 0 ? -centavos : centavos));

  static const Money zero = Money(0);

  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
  Money operator -() => Money(-cents);
  Money operator *(int factor) => Money(cents * factor);
  bool operator <(Money o) => cents < o.cents;
  bool operator >(Money o) => cents > o.cents;
  bool operator <=(Money o) => cents <= o.cents;
  bool operator >=(Money o) => cents >= o.cents;

  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  Money abs() => Money(cents.abs());

  /// Divide em [parts] parcelas que somam exatamente o total. Os centavos
  /// restantes vão para as primeiras parcelas (ex.: 1000,00 / 3 =
  /// 333,34 + 333,33 + 333,33).
  List<Money> split(int parts) {
    if (parts <= 0) throw ArgumentError.value(parts, 'parts');
    final base = cents ~/ parts;
    final remainder = cents - base * parts;
    final sign = remainder.sign;
    return List.generate(
      parts,
      (i) => Money(base + (i < remainder.abs() ? sign : 0)),
    );
  }

  /// Interpreta textos digitados no padrão brasileiro: "1.234,56",
  /// "1234,5", "R$ 55,90", "-10". Retorna `null` se inválido.
  static Money? tryParse(String input) {
    var s = input.replaceAll('R\$', '').replaceAll(' ', '').trim();
    if (s.isEmpty) return null;
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', '');
    }
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (m == null) return null;
    final reais = int.parse(m.group(1)!);
    final frac = (m.group(2) ?? '').padRight(2, '0');
    final total = reais * 100 + int.parse(frac);
    return Money(negative ? -total : total);
  }

  /// Como [tryParse], mas aceita também uma conta, como numa calculadora:
  /// "10*100" → 1.000,00; "1.234,56 + 10" → 1.244,56; "(50+25)/3" → 25,00.
  /// Operadores: + - * x × / ÷ e parênteses. O resultado é arredondado
  /// para centavos. Retorna `null` se a conta for inválida.
  static Money? tryEval(String input) {
    final s = input.replaceAll('R\$', '').trim();
    if (!isExpression(s)) return tryParse(s);
    final v = _Calc(s).parse();
    if (v == null || !v.isFinite) return null;
    return Money((v * 100).round());
  }

  /// `true` quando o texto é uma conta (tem um operador após um número).
  static bool isExpression(String input) =>
      RegExp(r'[\d)]\s*[-+*/x×÷]').hasMatch(input.replaceAll('R\$', '').trim());

  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );
  static final NumberFormat _plain = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: '',
    decimalDigits: 2,
  );
  static final NumberFormat _compact = NumberFormat.decimalPattern('pt_BR');

  /// "R$ 1.234,56" (centavos formatados via inteiros, sem arredondamento).
  String format() => _fmt(_currency);

  /// "1.234,56"
  String formatPlain() => _fmt(_plain).trim();

  /// Valor sem centavos para tabelas densas: "1.235".
  String formatCompact() {
    final reais = (cents.abs() + 50) ~/ 100;
    return '${cents < 0 ? '-' : ''}${_compact.format(reais)}';
  }

  String _fmt(NumberFormat f) {
    // Formatamos parte inteira e centavos separadamente para não depender de
    // double em nenhum momento.
    final abs = cents.abs();
    final reais = abs ~/ 100;
    final cent = (abs % 100).toString().padLeft(2, '0');
    final intPart = NumberFormat.decimalPattern('pt_BR').format(reais);
    final symbol = identical(f, _currency) ? 'R\$ ' : '';
    return '${cents < 0 ? '-' : ''}$symbol$intPart,$cent';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);
  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;
  @override
  int get hashCode => cents.hashCode;
  @override
  String toString() => format();
}

extension MoneySum on Iterable<Money> {
  Money sum() => fold(Money.zero, (a, b) => a + b);
}

/// Avaliador de contas simples (descendente recursivo), com números no
/// padrão brasileiro ("1.234,56").
class _Calc {
  final String src;
  int pos = 0;
  _Calc(String s) : src = s.replaceAll(' ', '');

  double? parse() {
    final v = _expr();
    if (v == null || pos != src.length) return null;
    return v;
  }

  String? get _peek => pos < src.length ? src[pos] : null;

  double? _expr() {
    var v = _term();
    while (v != null && (_peek == '+' || _peek == '-')) {
      final op = src[pos++];
      final r = _term();
      if (r == null) return null;
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double? _term() {
    var v = _factor();
    while (v != null && const ['*', 'x', 'X', '×', '/', '÷'].contains(_peek)) {
      final op = src[pos++];
      final r = _factor();
      if (r == null) return null;
      if (op == '/' || op == '÷') {
        if (r == 0) return null;
        v = v / r;
      } else {
        v = v * r;
      }
    }
    return v;
  }

  double? _factor() {
    final c = _peek;
    if (c == null) return null;
    if (c == '-' || c == '+') {
      pos++;
      final v = _factor();
      return v == null ? null : (c == '-' ? -v : v);
    }
    if (c == '(') {
      pos++;
      final v = _expr();
      if (v == null || _peek != ')') return null;
      pos++;
      return v;
    }
    final m = RegExp(r'[\d.,]+').matchAsPrefix(src, pos);
    if (m == null) return null;
    pos = m.end;
    return _number(m.group(0)!);
  }

  static double? _number(String s) {
    var n = s;
    if (n.contains(',')) {
      n = n.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(n)) {
      n = n.replaceAll('.', '');
    }
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(n)) return null;
    return double.tryParse(n);
  }
}
