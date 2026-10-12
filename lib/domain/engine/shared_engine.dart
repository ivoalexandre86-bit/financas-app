import '../../core/dates.dart';
import '../../core/money.dart';
import '../models/entities.dart';
import '../models/shared.dart';
import 'financial_engine.dart';
import 'other_entries_engine.dart';

/// Cálculos das despesas compartilhadas (mesmas regras do servidor).
class ShareMath {
  /// Divide [total] conforme [shares] (userId → pontos-base) sem perder
  /// centavos: piso de cada parte + centavos restantes para as maiores
  /// frações (empate: ordem de [order], ou de inserção).
  static List<ShareAllocation> allocate(
    int total,
    Map<String, int> shares, {
    List<String>? order,
  }) {
    final ids = [
      ...?order?.where((id) => (shares[id] ?? 0) > 0),
      ...shares.keys.where(
        (id) => (shares[id] ?? 0) > 0 && !(order?.contains(id) ?? false),
      ),
    ];
    final amounts = <String, int>{};
    final rests = <String, int>{};
    for (final id in ids) {
      final exact = total * shares[id]!;
      amounts[id] = exact ~/ fullBp;
      rests[id] = exact % fullBp;
    }
    var left = total - amounts.values.fold(0, (a, b) => a + b);
    final byRest = [...ids]
      ..sort((a, b) {
        final c = rests[b]!.compareTo(rests[a]!);
        return c != 0 ? c : ids.indexOf(a).compareTo(ids.indexOf(b));
      });
    for (final id in byRest) {
      if (left <= 0) break;
      amounts[id] = amounts[id]! + 1;
      left--;
    }
    return [
      for (final id in ids) ShareAllocation(id, shares[id]!, amounts[id]!),
    ];
  }

  /// Mensagem de erro, ou `null` quando a configuração é válida.
  static String? checkPercentages(Map<String, int> p, List<String> activeIds) {
    var sum = 0;
    for (final e in p.entries) {
      if (e.value < 0 || e.value > fullBp) return 'Percentual inválido';
      if (e.value == 0) continue;
      if (!activeIds.contains(e.key)) {
        return 'Só participantes do grupo (ou convidados) podem ter percentual';
      }
      sum += e.value;
    }
    if (sum != fullBp) {
      return 'A soma dos percentuais deve ser 100% (está em ${bpLabel(sum)})';
    }
    return null;
  }

  /// Partes iguais entre [ids] (centésimos que sobram vão para os primeiros).
  static Map<String, int> equal(List<String> ids) {
    if (ids.isEmpty) return {};
    final base = fullBp ~/ ids.length;
    var rest = fullBp - base * ids.length;
    return {for (final id in ids) id: base + (rest-- > 0 ? 1 : 0)};
  }
}

String _norm(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Integração das despesas compartilhadas com o orçamento de cada usuário.
///
/// A despesa original fica **uma vez** no orçamento de quem a pagou. Os
/// demais recebem só a sua parte; quem pagou recebe os reembolsos. Os ids são
/// fixos (`sh_…`), então recalcular é idempotente e nunca duplica:
///
/// * participante: `sh_pr_<despesa>` = parte em aberto (pendente, no
///   vencimento) e `sh_pp_<pagamento>` = cada pagamento feito (concluído).
/// * quem pagou: `sh_rr_<despesa>_<pessoa>` = reembolso a receber (previsto)
///   e `sh_rp_<pagamento>` = reembolso recebido (concluído).
///
/// Acertos não geram lançamentos próprios: eles só quitam partes (viram
/// pagamentos), evitando contar o mesmo dinheiro duas vezes.
class SharedBudgetSync {
  static const sharedCategoryId = 'cat_shared_expenses';
  static const reimbursementCategoryId = OtherSync.reimbursementCategoryId;

  static bool isDerived(String id) => id.startsWith('sh_');

  /// Id da despesa compartilhada de um lançamento derivado.
  static String? expenseIdOf(String txId, SharedState s) {
    if (txId.startsWith('sh_pr_')) return txId.substring(6);
    if (txId.startsWith('sh_rr_')) {
      final rest = txId.substring(6);
      final i = rest.indexOf('_');
      return i < 0 ? rest : rest.substring(0, i);
    }
    if (txId.startsWith('sh_pp_') || txId.startsWith('sh_rp_')) {
      final pid = txId.substring(6);
      for (final e in s.allExpenses) {
        if (e.payments.any((p) => p.id == pid)) return e.id;
      }
    }
    return null;
  }

  static List<FinCategory> missingCategories(List<FinCategory> existing) {
    final ids = existing.map((c) => c.id).toSet();
    return [
      if (!ids.contains(sharedCategoryId))
        FinCategory(
          id: sharedCategoryId,
          name: 'Despesas compartilhadas',
          kind: CategoryKind.expense,
          icon: 'people',
          color: 0xFF5C6BC0,
        ),
      if (!ids.contains(reimbursementCategoryId))
        FinCategory(
          id: reimbursementCategoryId,
          name: 'Reembolsos',
          kind: CategoryKind.income,
          color: 0xFF7CB342,
        ),
    ];
  }

  /// Mesmo nome, ignorando maiúsculas, acentos e espaços extras.
  static bool sameName(String a, String b) => _norm(a) == _norm(b);

  /// Categoria do meu orçamento com o mesmo nome da categoria do grupo.
  static String categoryFor(String groupCategory, List<FinCategory> mine) {
    final n = _norm(groupCategory);
    return mine
            .where((c) => c.kind == CategoryKind.expense && _norm(c.name) == n)
            .firstOrNull
            ?.id ??
        sharedCategoryId;
  }

  static List<FinTransaction> desired({
    required SharedState state,
    required List<FinCategory> categories,
    required String accountId,
  }) {
    final me = state.userId;
    final out = <FinTransaction>[];
    for (final g in state.groups) {
      for (final e in g.expenses) {
        if (e.ownerId == me) {
          for (final s in e.shares) {
            if (s.isPayer) continue;
            final name = g.nameOf(s.userId);
            for (final p in e.payments.where((p) => p.userId == s.userId)) {
              out.add(
                FinTransaction(
                  id: 'sh_rp_${p.id}',
                  type: TransactionType.income,
                  amount: Money(p.amount),
                  description: 'Reembolso $name – ${e.description}',
                  categoryId: reimbursementCategoryId,
                  date: p.date,
                  accountId: accountId,
                  notes:
                      'Despesa compartilhada · ${g.name}'
                      '${p.note.isEmpty ? '' : ' · ${p.note}'}',
                  status: TransactionStatus.completed,
                ),
              );
            }
            if (!e.isDeleted && s.outstanding > 0) {
              out.add(
                FinTransaction(
                  id: 'sh_rr_${e.id}_${s.userId}',
                  type: TransactionType.income,
                  amount: Money(s.outstanding),
                  description: 'A receber de $name – ${e.description}',
                  categoryId: reimbursementCategoryId,
                  date: e.cashDate,
                  accountId: accountId,
                  notes:
                      'Despesa compartilhada · ${g.name} · '
                      '${bpLabel(s.bp)} de ${Money(e.total).format()}',
                  status: TransactionStatus.planned,
                ),
              );
            }
          }
        } else {
          final s = e.shareOf(me);
          if (s == null) continue;
          final cat = categoryFor(e.categoryName, categories);
          final payer = g.nameOf(e.ownerId);
          for (final p in e.payments.where((p) => p.userId == me)) {
            out.add(
              FinTransaction(
                id: 'sh_pp_${p.id}',
                type: TransactionType.expense,
                amount: Money(p.amount),
                description: '${e.description} (minha parte)',
                categoryId: cat,
                date: p.date,
                accountId: accountId,
                notes:
                    'Despesa compartilhada · ${g.name} · paga a $payer'
                    '${p.note.isEmpty ? '' : ' · ${p.note}'}',
                status: TransactionStatus.completed,
              ),
            );
          }
          if (!e.isDeleted && s.outstanding > 0) {
            out.add(
              FinTransaction(
                id: 'sh_pr_${e.id}',
                type: TransactionType.expense,
                amount: Money(s.outstanding),
                description: '${e.description} (minha parte)',
                categoryId: cat,
                date: e.cashDate,
                dueDate: e.cashDate,
                accountId: accountId,
                notes:
                    'Despesa compartilhada · ${g.name} · ${bpLabel(s.bp)} de '
                    '${Money(e.total).format()} · a pagar a $payer',
                status: TransactionStatus.pending,
              ),
            );
          }
        }
      }
    }
    return out;
  }

  /// (gravar, excluir) para alinhar o orçamento com [desired]. Lançamentos
  /// já concluídos de grupos que deixei de ver ficam (o dinheiro já saiu).
  static (List<FinTransaction>, List<String>) diff({
    required List<FinTransaction> existing,
    required List<FinTransaction> desired,
  }) {
    final current = {
      for (final t in existing)
        if (isDerived(t.id)) t.id: t,
    };
    final puts = <FinTransaction>[];
    for (final t in desired) {
      final old = current.remove(t.id);
      if (old == null) {
        puts.add(t);
      } else if (!_same(old, t)) {
        puts.add(
          FinTransaction.fromJson({
            ...t.toJson(),
            'createdAt': old.createdAt.toIso8601String(),
          }),
        );
      }
    }
    final deletes = [
      for (final t in current.values)
        if (!(t.status == TransactionStatus.completed &&
            (t.id.startsWith('sh_pp_') || t.id.startsWith('sh_rp_'))))
          t.id,
    ];
    return (puts, deletes);
  }

  static bool _same(FinTransaction a, FinTransaction b) {
    Map<String, Object?> k(FinTransaction t) => Map.of(t.toJson())
      ..remove('createdAt')
      ..remove('updatedAt');
    final ka = k(a), kb = k(b);
    return ka.length == kb.length && ka.keys.every((x) => ka[x] == kb[x]);
  }
}

/// Dados de uma despesa a enviar ao servidor (criação ou atualização).
class ShareSource {
  final String groupId;
  final String sourceKey;
  final String description;
  final int total;
  final DateTime date;
  final DateTime? dueDate;
  final String source;
  final String? recurrenceId;
  final DateTime? occurrenceDate;
  const ShareSource({
    required this.groupId,
    required this.sourceKey,
    required this.description,
    required this.total,
    required this.date,
    this.dueDate,
    required this.source,
    this.recurrenceId,
    this.occurrenceDate,
  });

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'sourceKey': sourceKey,
    'description': description,
    'total': total,
    'date': Dates.toIso(date),
    'dueDate': dueDate == null ? null : Dates.toIso(dueDate!),
    'source': source,
    'recurrenceId': ?recurrenceId,
    'occurrenceDate': occurrenceDate == null
        ? null
        : Dates.toIso(occurrenceDate!),
  };

  bool sameAs(SharedExpense e) =>
      e.total == total &&
      e.description == description &&
      Dates.toIso(e.date) == Dates.toIso(date) &&
      (e.dueDate == null ? null : Dates.toIso(e.dueDate!)) ==
          (dueDate == null ? null : Dates.toIso(dueDate!));
}

/// O que mudou no meu orçamento e precisa subir para as despesas que eu
/// compartilhei: valor/data editados, lançamento excluído, novas ocorrências
/// de recorrências compartilhadas.
class OwnerReconcile {
  /// Meses à frente em que as ocorrências recorrentes já ficam lançadas
  /// (aparecem na projeção de todos os participantes).
  static const horizonMonths = 12;

  static String recurringKey(String ruleId, DateTime d) =>
      'r:$ruleId:${Dates.toIso(d)}';

  /// Dados de origem de um lançamento meu.
  static ShareSource sourceOf(
    FinancialEngine engine,
    FinTransaction t, {
    required String groupId,
    String? sourceKey,
    String? recurrenceId,
  }) {
    final cash = engine.cashDate(t);
    return ShareSource(
      groupId: groupId,
      sourceKey: sourceKey ?? t.id,
      description: t.description,
      total: t.amount.cents,
      date: t.date,
      dueDate: t.isCardTransaction ? cash : (t.shownDueDate ?? cash),
      source: recurrenceId != null
          ? 'recurring'
          : t.isCardTransaction
          ? 'card'
          : t.externalId != null
          ? 'import'
          : 'account',
      recurrenceId: recurrenceId,
      occurrenceDate: recurrenceId != null ? t.occurrenceDate : null,
    );
  }

  /// Regras recorrentes que descendem de [ruleId] (edições "só futuras"
  /// criam uma nova versão da regra).
  static Set<String> ruleChain(String ruleId, List<RecurringRule> rules) {
    final ids = {ruleId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final r in rules) {
        if (r.previousRuleId != null &&
            ids.contains(r.previousRuleId) &&
            ids.add(r.id)) {
          grew = true;
        }
      }
    }
    return ids;
  }

  /// (criar/atualizar, excluir ids das despesas).
  static (List<ShareSource>, List<String>) plan({
    required SharedState state,
    required FinancialEngine engine,
    DateTime? today,
  }) {
    final me = state.userId;
    final now = Dates.dateOnly(today ?? engine.today);
    final until = YearMonth.of(now).add(horizonMonths).lastDay;
    final txs = engine.transactionsUntil(until);
    final byId = {for (final t in engine.data.transactions) t.id: t};
    final upserts = <ShareSource>[];
    final deletes = <String>[];
    for (final g in state.groups) {
      if (!g.myRole.canManage) continue;
      final mine = g.liveExpenses.where(
        (e) => e.ownerId == me && e.sourceKey != null,
      );
      final byKey = {for (final e in mine) e.sourceKey!: e};
      // Lançamentos avulsos.
      for (final e in mine.where((e) => e.recurrenceId == null)) {
        final t = byId[e.sourceKey];
        if (t == null || t.status == TransactionStatus.cancelled) {
          deletes.add(e.id);
          continue;
        }
        final s = sourceOf(engine, t, groupId: g.id);
        if (!s.sameAs(e)) upserts.add(s);
      }
      // Recorrências.
      for (final r in g.recurrences) {
        if (r.ownerId != me || r.sourceRuleId == null) continue;
        final chain = ruleChain(r.sourceRuleId!, engine.data.recurringRules);
        final from = YearMonth.of(r.createdAt?.toLocal() ?? now).firstDay;
        final wanted = <String>{};
        for (final t in txs) {
          if (t.recurringId == null || !chain.contains(t.recurringId)) continue;
          final occ = t.occurrenceDate ?? t.date;
          if (occ.isBefore(from) || occ.isAfter(until)) continue;
          if (t.status == TransactionStatus.cancelled) continue;
          final key = recurringKey(r.sourceRuleId!, occ);
          wanted.add(key);
          final s = sourceOf(
            engine,
            t,
            groupId: g.id,
            sourceKey: key,
            recurrenceId: r.id,
          );
          final cur = byKey[key];
          if (cur == null ? !r.paused : !s.sameAs(cur)) upserts.add(s);
        }
        // Ocorrências futuras que deixaram de existir (regra encerrada,
        // ocorrência cancelada) e ainda não têm pagamento.
        for (final e in mine.where((e) => e.recurrenceId == r.id)) {
          if (!wanted.contains(e.sourceKey) &&
              e.date.isAfter(now) &&
              e.payments.isEmpty) {
            deletes.add(e.id);
          }
        }
      }
    }
    return (upserts, deletes);
  }
}

// Relatórios ------------------------------------------------------------------

class SharedFilter {
  final String? groupId;
  final String? ownerId;
  final String? participantId;
  final String? category;
  final YearMonth? from;
  final YearMonth? to;
  final PayStatus? status;
  const SharedFilter({
    this.groupId,
    this.ownerId,
    this.participantId,
    this.category,
    this.from,
    this.to,
    this.status,
  });

  bool get isEmpty =>
      groupId == null &&
      ownerId == null &&
      participantId == null &&
      category == null &&
      from == null &&
      to == null &&
      status == null;

  SharedFilter copyWith({
    Object? groupId = _u,
    Object? ownerId = _u,
    Object? participantId = _u,
    Object? category = _u,
    Object? from = _u,
    Object? to = _u,
    Object? status = _u,
  }) => SharedFilter(
    groupId: groupId == _u ? this.groupId : groupId as String?,
    ownerId: ownerId == _u ? this.ownerId : ownerId as String?,
    participantId: participantId == _u
        ? this.participantId
        : participantId as String?,
    category: category == _u ? this.category : category as String?,
    from: from == _u ? this.from : from as YearMonth?,
    to: to == _u ? this.to : to as YearMonth?,
    status: status == _u ? this.status : status as PayStatus?,
  );

  /// Situação considerada: a do participante filtrado, ou da despesa.
  PayStatus statusOf(SharedExpense e) => participantId == null
      ? e.status
      : e.shareOf(participantId!)?.status ?? PayStatus.paid;

  bool matches(SharedExpense e) {
    if (e.isDeleted) return false;
    if (groupId != null && e.groupId != groupId) return false;
    if (ownerId != null && e.ownerId != ownerId) return false;
    if (participantId != null && e.allocationOf(participantId!) == null) {
      return false;
    }
    if (category != null && e.categoryName != category) return false;
    final m = e.month;
    if (from != null && m < from!) return false;
    if (to != null && m > to!) return false;
    if (status != null && statusOf(e) != status) return false;
    return true;
  }
}

const _u = Object();

/// Totais por participante.
class ParticipantTotals {
  int owed = 0;
  int paid = 0; // inclui a parte de quem pagou a conta
  int outstanding = 0;

  /// Valor que este participante pagou de contas inteiras do grupo.
  int fronted = 0;
}

class SharedTotals {
  int total = 0;
  int count = 0;
  int outstanding = 0;
  final Map<String, ParticipantTotals> byUser = {};
  final Map<String, int> byCategory = {};

  ParticipantTotals user(String id) => byUser[id] ??= ParticipantTotals();

  void add(SharedExpense e) {
    total += e.total;
    count++;
    outstanding += e.outstanding;
    byCategory[e.categoryName] = (byCategory[e.categoryName] ?? 0) + e.total;
    user(e.ownerId).fronted += e.total;
    for (final s in e.shares) {
      final u = user(s.userId);
      u.owed += s.owed;
      u.paid += s.settled;
      u.outstanding += s.outstanding;
    }
  }
}

class SharedReport {
  static List<SharedExpense> filter(SharedState s, SharedFilter f) =>
      s.allExpenses.where(f.matches).toList()
        ..sort((a, b) => a.cashDate.compareTo(b.cashDate));

  static SharedTotals totals(Iterable<SharedExpense> list) {
    final t = SharedTotals();
    list.forEach(t.add);
    return t;
  }

  static Map<YearMonth, SharedTotals> byMonth(Iterable<SharedExpense> list) {
    final out = <YearMonth, SharedTotals>{};
    for (final e in list) {
      (out[e.month] ??= SharedTotals()).add(e);
    }
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Saldo entre pares: quanto [debtor] ainda deve a [creditor] (positivo)
  /// nas despesas pagas por [creditor].
  static int owedBetween(
    Iterable<SharedExpense> list,
    String debtor,
    String creditor,
  ) => list
      .where((e) => !e.isDeleted && e.ownerId == creditor)
      .fold(0, (a, e) => a + (e.shareOf(debtor)?.outstanding ?? 0));
}

// Simulação --------------------------------------------------------------------

/// Nova despesa recorrente hipotética da simulação.
class SimSharedItem {
  final String description;
  final String categoryId;
  final int monthly;
  const SimSharedItem(this.description, this.categoryId, this.monthly);
}

/// Cenário de simulação das despesas compartilhadas. Nada aqui altera dados
/// reais: o resultado é calculado em memória a partir das despesas do grupo.
class SharedScenario {
  /// Percentuais simulados por categoria do grupo (userId → bp). Pessoas
  /// hipotéticas usam ids começando com `sim:`.
  final Map<String, Map<String, int>> percentages;

  /// Participantes (reais ou hipotéticos) do cenário.
  final List<String> participants;

  /// Variação dos valores por categoria (ex.: 1.1 = +10%). Ausente = 1.
  final Map<String, double> scale;
  final double globalScale;
  final List<SimSharedItem> extra;

  const SharedScenario({
    required this.percentages,
    required this.participants,
    this.scale = const {},
    this.globalScale = 1,
    this.extra = const [],
  });

  /// Cenário inicial = configuração atual do grupo.
  factory SharedScenario.of(ShareGroup g) => SharedScenario(
    percentages: {
      for (final c in g.activeCategories) c.id: Map.of(c.percentages),
    },
    participants: g.splitIds,
  );

  String? error(ShareGroup g) {
    for (final c in g.activeCategories) {
      final p = percentages[c.id] ?? const {};
      final e = ShareMath.checkPercentages(p, participants);
      if (e != null) return '${c.name}: $e';
    }
    return null;
  }
}

class SimMonth {
  final YearMonth month;
  int currentTotal = 0;
  int simTotal = 0;
  final Map<String, int> current = {};
  final Map<String, int> sim = {};
  SimMonth(this.month);
}

class SharedSimulation {
  /// Compara, mês a mês, a responsabilidade de cada participante hoje e no
  /// cenário. Despesas com divisão manual mantêm os percentuais delas
  /// (quem saiu do cenário tem a parte redistribuída entre os demais).
  static List<SimMonth> run(
    ShareGroup g,
    SharedScenario sc, {
    required YearMonth from,
    int months = 12,
  }) {
    final out = [for (var i = 0; i < months; i++) SimMonth(from.add(i))];
    SimMonth? slot(YearMonth m) {
      final i = from.monthsUntil(m);
      return i >= 0 && i < months ? out[i] : null;
    }

    final catByName = {for (final c in g.activeCategories) c.name: c.id};
    for (final e in g.liveExpenses) {
      final m = slot(e.month);
      if (m == null) continue;
      m.currentTotal += e.total;
      for (final a in e.allocations) {
        m.current[a.userId] = (m.current[a.userId] ?? 0) + a.amount;
      }
      final catId = e.categoryId ?? catByName[e.categoryName];
      final factor = sc.globalScale * (sc.scale[catId] ?? 1);
      final total = (e.total * factor).round();
      Map<String, int> p;
      if (e.overridden || catId == null || sc.percentages[catId] == null) {
        p = _redistribute({
          for (final a in e.allocations) a.userId: a.bp,
        }, sc.participants);
      } else {
        p = sc.percentages[catId]!;
      }
      m.simTotal += total;
      for (final a in ShareMath.allocate(total, p, order: sc.participants)) {
        m.sim[a.userId] = (m.sim[a.userId] ?? 0) + a.amount;
      }
    }
    for (final x in sc.extra) {
      final p = sc.percentages[x.categoryId];
      if (p == null || x.monthly <= 0) continue;
      for (final m in out) {
        m.simTotal += x.monthly;
        for (final a in ShareMath.allocate(
          x.monthly,
          p,
          order: sc.participants,
        )) {
          m.sim[a.userId] = (m.sim[a.userId] ?? 0) + a.amount;
        }
      }
    }
    return out;
  }

  /// Tira quem não está em [keep] e reparte a parte dele proporcionalmente.
  static Map<String, int> _redistribute(Map<String, int> p, List<String> keep) {
    final kept = {
      for (final e in p.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };
    final sum = kept.values.fold(0, (a, b) => a + b);
    if (sum == fullBp) return kept;
    if (sum == 0) return ShareMath.equal(keep);
    final out = {for (final e in kept.entries) e.key: e.value * fullBp ~/ sum};
    final diff = fullBp - out.values.fold<int>(0, (a, b) => a + b);
    final first = out.keys.first;
    out[first] = out[first]! + diff;
    return out;
  }
}
