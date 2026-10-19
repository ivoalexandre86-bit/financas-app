import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/entities.dart';
import '../models/planning.dart';
import 'financial_engine.dart';
import 'recurrence.dart';

/// Origem de uma assinatura na lista.
enum SubscriptionSource {
  recurring('Recorrência'),
  detected('Detectada');

  final String label;
  const SubscriptionSource(this.label);
}

/// Cobrança recorrente: uma regra de despesa recorrente ou um gasto avulso
/// que se repete todo mês com valor parecido.
class Subscription {
  final String name;

  /// Valor mensal típico (equivalente mensal, para regras não mensais).
  final Money monthly;

  /// Última cobrança até hoje (nula se ainda não houve).
  final DateTime? lastDate;

  /// Valor da última cobrança e da anterior (para detectar aumento).
  final Money? lastAmount;
  final Money? previousAmount;

  /// Meses (da janela analisada) com cobrança.
  final int monthsSeen;
  final SubscriptionSource source;
  final RecurringRule? rule;
  final String? categoryId;
  final String? accountId;
  final String? cardId;

  const Subscription({
    required this.name,
    required this.monthly,
    required this.source,
    this.lastDate,
    this.lastAmount,
    this.previousAmount,
    this.monthsSeen = 0,
    this.rule,
    this.categoryId,
    this.accountId,
    this.cardId,
  });

  Money get annual => monthly * 12;

  /// Última cobrança mais de 5% acima da anterior.
  bool get priceIncreased =>
      lastAmount != null &&
      previousAmount != null &&
      previousAmount!.cents > 0 &&
      lastAmount!.cents * 100 > previousAmount!.cents * 105;

  /// Aumento percentual da última cobrança sobre a anterior.
  double get increasePercent => priceIncreased
      ? (lastAmount!.cents - previousAmount!.cents) *
            100 /
            previousAmount!.cents
      : 0;

  bool get isDetected => source == SubscriptionSource.detected;
}

/// Detecção de assinaturas (puro: só lê os dados do motor).
class SubscriptionDetector {
  SubscriptionDetector._();

  /// Meses analisados (o atual e os anteriores).
  static const windowMonths = 6;

  /// Meses mínimos com cobrança parecida para considerar recorrente.
  static const minMonths = 3;

  /// Tolerância de valor em relação ao valor típico (±15%).
  static const tolerancePercent = 15;

  static List<Subscription> detect(FinancialEngine e) {
    final today = e.today;
    final current = YearMonth.of(today);
    final from = current.add(-(windowMonths - 1));
    final upToToday = e.transactionsUntil(today);
    final out = <Subscription>[];
    final ruleNames = <String>{};

    // Regras recorrentes de despesa ativas.
    for (final r in e.data.recurringRules) {
      if (r.type != TransactionType.expense || r.isPaused) continue;
      if (r.endDate != null && r.endDate!.isBefore(today)) continue;
      ruleNames.add(CategoryRule.normalize(r.description));
      final occ =
          upToToday
              .where(
                (t) =>
                    t.recurringId == r.id &&
                    t.status != TransactionStatus.cancelled,
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      final months = {
        for (final t in occ)
          if (YearMonth.of(t.date) >= from) YearMonth.of(t.date),
      };
      out.add(
        Subscription(
          name: r.description,
          monthly: Money(Recurrence.monthlyEquivalentCents(r)),
          source: SubscriptionSource.recurring,
          lastDate: occ.isEmpty ? null : occ.last.date,
          lastAmount: occ.isEmpty ? null : occ.last.amount,
          previousAmount: occ.length < 2 ? null : occ[occ.length - 2].amount,
          monthsSeen: months.length,
          rule: r,
          categoryId: r.categoryId,
          accountId: r.accountId,
          cardId: r.cardId,
        ),
      );
    }

    // Gastos avulsos agrupados pela descrição normalizada.
    final groups = <String, List<FinTransaction>>{};
    for (final t in e.data.transactions) {
      if (t.type != TransactionType.expense || t.isVirtual) continue;
      if (t.isRecurring || t.isInstallment) continue;
      if (t.status == TransactionStatus.cancelled) continue;
      if (t.date.isAfter(today) || YearMonth.of(t.date) < from) continue;
      final key = CategoryRule.normalize(t.description);
      if (key.isEmpty || ruleNames.contains(key)) continue;
      groups.putIfAbsent(key, () => []).add(t);
    }
    for (final txs in groups.values) {
      final s = _fromGroup(txs);
      if (s != null) out.add(s);
    }

    out.sort((a, b) {
      final c = b.monthly.compareTo(a.monthly);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return out;
  }

  static Subscription? _fromGroup(List<FinTransaction> txs) {
    final byMonth = <YearMonth, int>{};
    for (final t in txs) {
      byMonth.update(
        YearMonth.of(t.date),
        (v) => v + t.amount.cents,
        ifAbsent: () => t.amount.cents,
      );
    }
    if (byMonth.length < minMonths) return null;
    final typical = _median(byMonth.values.toList());
    bool similar(int v) =>
        (v - typical).abs() * 100 <= typical * tolerancePercent;
    final good = byMonth.entries.where((m) => similar(m.value)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (good.length < minMonths) return null;
    final months = byMonth.keys.toList()..sort();
    txs.sort((a, b) => a.date.compareTo(b.date));
    final last = txs.last;
    return Subscription(
      name: last.description.trim(),
      monthly: Money(_median([for (final m in good) m.value])),
      source: SubscriptionSource.detected,
      lastDate: last.date,
      lastAmount: Money(byMonth[months.last]!),
      previousAmount: months.length < 2
          ? null
          : Money(byMonth[months[months.length - 2]]!),
      monthsSeen: byMonth.length,
      categoryId: last.categoryId,
      accountId: last.accountId,
      cardId: last.cardId,
    );
  }

  static int _median(List<int> v) {
    v.sort();
    final n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) ~/ 2;
  }

  /// Totais mensal e anual da lista.
  static ({Money monthly, Money annual}) totals(List<Subscription> l) {
    final m = l.map((s) => s.monthly).sum();
    return (monthly: m, annual: m * 12);
  }
}
