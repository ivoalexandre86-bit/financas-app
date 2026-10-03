import 'package:intl/intl.dart';

/// Utilitários de data puros (sem fuso horário: usamos apenas a parte de data).
class Dates {
  Dates._();

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime today() => dateOnly(DateTime.now());

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Data no dia [day] do mês, limitada ao último dia (ex.: 31 em fevereiro
  /// vira 28/29).
  static DateTime clampedDate(int year, int month, int day) {
    final norm = DateTime(year, month, 1);
    final d = day.clamp(1, daysInMonth(norm.year, norm.month));
    return DateTime(norm.year, norm.month, d);
  }

  /// Soma meses preservando o dia desejado ([anchorDay]) e limitando ao fim
  /// do mês. Ex.: 31/01 + 1 mês = 28/02; 28/02 + 1 mês (âncora 31) = 31/03.
  static DateTime addMonths(DateTime d, int months, {int? anchorDay}) {
    final base = DateTime(d.year, d.month + months, 1);
    return clampedDate(base.year, base.month, anchorDay ?? d.day);
  }

  static final DateFormat _br = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final DateFormat _short = DateFormat('dd/MM', 'pt_BR');

  static String format(DateTime d) => _br.format(d);
  static String formatShort(DateTime d) => _short.format(d);

  static DateTime? tryParse(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > daysInMonth(year, month)) return null;
    return DateTime(year, month, day);
  }

  static String toIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime fromIso(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}

/// Mês de competência (ano + mês), imutável e comparável.
class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month;
  const YearMonth._(this.year, this.month);

  factory YearMonth(int year, int month) {
    final d = DateTime(year, month, 1);
    return YearMonth._(d.year, d.month);
  }

  factory YearMonth.of(DateTime d) => YearMonth._(d.year, d.month);
  factory YearMonth.now() => YearMonth.of(DateTime.now());

  /// Aceita "2026-08".
  factory YearMonth.parse(String key) {
    final p = key.split('-');
    return YearMonth(int.parse(p[0]), int.parse(p[1]));
  }

  YearMonth add(int months) => YearMonth(year, month + months);
  YearMonth get next => add(1);
  YearMonth get previous => add(-1);

  DateTime get firstDay => DateTime(year, month, 1);
  DateTime get lastDay => DateTime(year, month + 1, 0);
  int get days => lastDay.day;

  bool contains(DateTime d) => d.year == year && d.month == month;

  /// Número de meses de [this] até [other] (positivo se other é posterior).
  int monthsUntil(YearMonth other) =>
      (other.year - year) * 12 + (other.month - month);

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  static const _abbr = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];
  static const _full = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  /// "Ago/26"
  String get shortLabel =>
      '${_abbr[month - 1]}/${(year % 100).toString().padLeft(2, '0')}';

  /// "Agosto de 2026"
  String get longLabel => '${_full[month - 1]} de $year';

  static Iterable<YearMonth> range(YearMonth from, YearMonth to) sync* {
    var m = from;
    while (m.compareTo(to) <= 0) {
      yield m;
      m = m.next;
    }
  }

  @override
  int compareTo(YearMonth o) =>
      year != o.year ? year.compareTo(o.year) : month.compareTo(o.month);
  bool operator <(YearMonth o) => compareTo(o) < 0;
  bool operator >(YearMonth o) => compareTo(o) > 0;
  bool operator <=(YearMonth o) => compareTo(o) <= 0;
  bool operator >=(YearMonth o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;
  @override
  int get hashCode => year * 12 + month;
  @override
  String toString() => key;
}
