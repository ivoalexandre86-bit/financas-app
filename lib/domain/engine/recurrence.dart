import '../../core/dates.dart';
import '../models/entities.dart';

/// Geração de datas de ocorrência para regras recorrentes.
///
/// As datas são calculadas sempre a partir da âncora (data inicial + k
/// passos), nunca acumulando a partir da ocorrência anterior, para não haver
/// "deriva" de dias (ex.: 31/01 → 28/02 → 31/03, e não 28/03).
class Recurrence {
  Recurrence._();

  static const _maxOccurrences = 5000;

  /// Passo da regra em (meses, dias). Exatamente um dos dois é > 0.
  static (int months, int days) step(RecurringRule r) {
    final n = r.interval < 1 ? 1 : r.interval;
    switch (r.frequency) {
      case RecurrenceFrequency.weekly:
        return (0, 7);
      case RecurrenceFrequency.monthly:
        return (1, 0);
      case RecurrenceFrequency.quarterly:
        return (3, 0);
      case RecurrenceFrequency.yearly:
        return (12, 0);
      case RecurrenceFrequency.custom:
        switch (r.unit) {
          case RecurrenceUnit.days:
            return (0, n);
          case RecurrenceUnit.weeks:
            return (0, 7 * n);
          case RecurrenceUnit.months:
            return (n, 0);
        }
    }
  }

  /// Primeira data efetiva da regra (ajustada ao dia do mês, se definido).
  static DateTime firstOccurrence(RecurringRule r) {
    final start = Dates.dateOnly(r.startDate);
    final (months, _) = step(r);
    if (months > 0 && r.dayOfMonth != null) {
      final candidate = Dates.clampedDate(
        start.year,
        start.month,
        r.dayOfMonth!,
      );
      if (candidate.isBefore(start)) {
        final nm = YearMonth.of(start).next;
        return Dates.clampedDate(nm.year, nm.month, r.dayOfMonth!);
      }
      return candidate;
    }
    return start;
  }

  /// Ocorrências da regra no intervalo fechado [from, to], respeitando data
  /// final e períodos de pausa.
  static List<DateTime> occurrences(
    RecurringRule r,
    DateTime from,
    DateTime to,
  ) {
    final result = <DateTime>[];
    final first = firstOccurrence(r);
    final f = Dates.dateOnly(from);
    var t = Dates.dateOnly(to);
    if (r.endDate != null && r.endDate!.isBefore(t)) {
      t = Dates.dateOnly(r.endDate!);
    }
    if (t.isBefore(first) || t.isBefore(f)) return result;

    final (months, days) = step(r);
    final anchorDay = r.dayOfMonth ?? first.day;

    // Pula direto para perto de `from` para não iterar desde o início.
    var k = 0;
    if (f.isAfter(first)) {
      if (months > 0) {
        k = (YearMonth.of(first).monthsUntil(YearMonth.of(f)) ~/ months) - 1;
      } else {
        k = (_daysBetween(first, f) ~/ days) - 1;
      }
      if (k < 0) k = 0;
    }

    for (var guard = 0; guard < _maxOccurrences; guard++, k++) {
      final DateTime d = months > 0
          ? Dates.addMonths(first, k * months, anchorDay: anchorDay)
          : DateTime(first.year, first.month, first.day + k * days);
      if (d.isAfter(t)) break;
      if (d.isBefore(f)) continue;
      if (r.pauses.any((p) => p.covers(d))) continue;
      result.add(d);
    }
    return result;
  }

  /// Próxima ocorrência a partir de [from] (inclusive), ou `null`.
  static DateTime? nextOccurrence(RecurringRule r, DateTime from) {
    final list = occurrences(
      r,
      from,
      Dates.addMonths(from, 24, anchorDay: from.day),
    );
    return list.isEmpty ? null : list.first;
  }

  /// Valor mensal equivalente (aproximado) da regra, útil para indicadores.
  static int monthlyEquivalentCents(RecurringRule r) {
    final (months, days) = step(r);
    if (months > 0) return r.amount.cents ~/ months;
    return (r.amount.cents * 30) ~/ days;
  }

  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}
