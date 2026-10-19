import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/asset.dart';
import '../models/entities.dart';
import 'billing_cycle.dart';
import 'financial_engine.dart';

/// Composição do patrimônio líquido, bloco a bloco.
class NetWorth {
  /// Saldo das contas ativas.
  final Money accounts;

  /// Bens registrados (imóveis, veículos, investimentos…).
  final Money assets;

  /// Dívidas registradas à mão (financiamentos, empréstimos…).
  final Money liabilities;

  /// Saldo devedor das faturas já abertas ou fechadas.
  final Money cardInvoices;

  /// Parcelas a vencer: em conta (não pagas) e no cartão (faturas futuras).
  final Money installments;

  const NetWorth({
    required this.accounts,
    required this.assets,
    required this.liabilities,
    required this.cardInvoices,
    required this.installments,
  });

  Money get total =>
      accounts + assets - liabilities - cardInvoices - installments;
}

/// Ponto do gráfico de evolução (fim de cada mês).
class NetWorthPoint {
  final YearMonth month;
  final Money value;
  const NetWorthPoint(this.month, this.value);
}

class NetWorthEngine {
  final FinancialEngine engine;
  const NetWorthEngine(this.engine);

  FinanceData get data => engine.data;

  NetWorth compute(List<Asset> items) {
    var assets = Money.zero, liabilities = Money.zero;
    for (final a in items) {
      if (a.isLiability) {
        liabilities += a.value;
      } else {
        assets += a.value;
      }
    }
    return NetWorth(
      accounts: engine.currentBalance,
      assets: assets,
      liabilities: liabilities,
      cardInvoices: openInvoices,
      installments: remainingInstallments,
    );
  }

  /// Faturas até a atual (as futuras entram em [remainingInstallments]).
  Money get openInvoices {
    var total = Money.zero;
    for (final card in data.cards) {
      final current = BillingCycle.currentInvoice(card, engine.today);
      for (final inv in engine.invoicesForCard(card, until: current)) {
        if (inv.month <= current) total += inv.remaining;
      }
    }
    return total;
  }

  /// Parcelas ainda não pagas em conta e parcelas de cartão em faturas
  /// futuras.
  Money get remainingInstallments {
    var total = Money.zero;
    for (final t in data.transactions) {
      if (!t.isInstallment || t.status == TransactionStatus.cancelled) {
        continue;
      }
      final card = data.cardById[t.cardId];
      if (card != null) {
        final current = BillingCycle.currentInvoice(card, engine.today);
        if (BillingCycle.invoiceForTransaction(card, t) > current) {
          total += t.type == TransactionType.income ? -t.amount : t.amount;
        }
      } else if (t.cardId == null &&
          t.type == TransactionType.expense &&
          t.status != TransactionStatus.completed) {
        total += t.amount;
      }
    }
    return total;
  }

  /// Saldo das contas ativas no fim de [date] (só movimentações concluídas).
  Money accountsAt(DateTime date) {
    final active = {
      for (final a in data.accounts)
        if (a.active) a.id,
    };
    var bal = Money.zero;
    for (final a in data.accounts) {
      if (a.active) bal += a.initialBalance;
    }
    for (final t in data.transactions) {
      if (t.status != TransactionStatus.completed || t.date.isAfter(date)) {
        continue;
      }
      final from = active.contains(t.accountId);
      switch (t.type) {
        case TransactionType.income:
          if (from) bal += t.amount;
        case TransactionType.expense:
          if (from) bal -= t.amount;
        case TransactionType.transfer:
          if (from) bal -= t.amount;
          if (active.contains(t.destinationAccountId)) bal += t.amount;
      }
    }
    for (final p in data.invoicePayments) {
      if (active.contains(p.accountId) && !p.date.isAfter(date)) {
        bal -= p.amount;
      }
    }
    return bal;
  }

  /// Evolução mensal (até [maxMonths] meses): meses anteriores somam contas
  /// e bens/dívidas pelo histórico; o mês atual é o patrimônio completo.
  List<NetWorthPoint> history(List<Asset> items, {int maxMonths = 12}) {
    final now = engine.currentMonth;
    var first = now;
    for (final a in items) {
      if (a.history.isEmpty) continue;
      final m = YearMonth.of(a.history.first.date);
      if (m < first) first = m;
    }
    final oldest = now.add(-(maxMonths - 1));
    if (first < oldest) first = oldest;
    return [
      for (final m in YearMonth.range(first, now))
        NetWorthPoint(
          m,
          m == now ? compute(items).total : _pastTotal(items, m.lastDay),
        ),
    ];
  }

  Money _pastTotal(List<Asset> items, DateTime end) {
    var v = accountsAt(end);
    for (final a in items) {
      final x = a.valueAt(end);
      if (x != null) v += a.isLiability ? -x : x;
    }
    return v;
  }
}
