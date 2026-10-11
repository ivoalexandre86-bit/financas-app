import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../data/cloud/shared_api.dart';
import '../domain/engine/financial_engine.dart';
import '../domain/engine/shared_engine.dart';
import '../domain/models/entities.dart';
import '../domain/models/shared.dart';
import 'finance_controller.dart';

/// Estado das despesas compartilhadas do usuário logado.
///
/// O servidor é a fonte da verdade (grupos, divisões, pagamentos). Este
/// controlador:
/// * baixa o estado ([refresh]);
/// * envia ao servidor o que mudou nas despesas que eu compartilhei
///   (valor/data editados, lançamento excluído, ocorrências recorrentes);
/// * alinha o meu orçamento ([FinanceController.applyShared]).
class SharedController extends ChangeNotifier {
  final SharedApi? api;
  final FinanceController finance;

  SharedController(this.api, this.finance) {
    if (api != null) {
      finance.addListener(_onFinance);
      // Orçamento já carregado: começa já.
      if (!finance.loading) scheduleMicrotask(_onFinance);
    }
  }

  /// Disponível só com a conta na nuvem (é lá que os usuários se encontram).
  bool get available => api != null;

  SharedState state = SharedState.empty;
  bool loading = false;
  bool loaded = false;
  String? error;

  bool _disposed = false;
  Future<void>? _running;
  Timer? _debounce;
  FinanceData? _lastData;

  String get me => state.userId;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    finance.removeListener(_onFinance);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _onFinance() {
    if (finance.loading || identical(finance.data, _lastData)) return;
    _lastData = finance.data;
    if (!loaded) {
      // Primeira carga assim que o orçamento estiver pronto.
      unawaited(refresh());
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!_disposed) unawaited(_reconcile());
    });
  }

  /// Baixa o estado, propaga mudanças das minhas despesas e alinha o
  /// orçamento. Chamadas simultâneas são agrupadas.
  Future<void> refresh() => _running ??= _refresh().whenComplete(() {
    _running = null;
  });

  Future<void> _refresh() async {
    final api = this.api;
    if (api == null) return;
    loading = true;
    notifyListeners();
    try {
      state = await api.state();
      error = null;
      loaded = true;
      if (await _push()) state = await api.state();
      await finance.applyShared(state);
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _reconcile() async {
    if (_running != null || !loaded) return;
    final (ups, dels) = OwnerReconcile.plan(
      state: state,
      engine: finance.engine,
    );
    if (ups.isEmpty && dels.isEmpty && paidInBudget().isEmpty) return;
    await refresh();
  }

  /// Envia as mudanças do meu orçamento. Retorna se enviou algo.
  Future<bool> _push() async {
    final api = this.api;
    if (api == null || !finance.cloudSynced || finance.loading) return false;
    // Parte marcada como paga direto no orçamento (lista de transações):
    // vira pagamento registrado no grupo.
    final payments = paidInBudget();
    for (final p in payments) {
      await api.addPayment(
        p.expense.id,
        userId: p.userId,
        amount: p.amount,
        date: p.date,
        note: 'Marcado como pago no orçamento',
      );
    }
    final (ups, dels) = OwnerReconcile.plan(
      state: state,
      engine: finance.engine,
    );
    for (final s in ups) {
      await api.upsertExpense(s.toJson());
    }
    for (final id in dels) {
      await api.deleteExpense(id);
    }
    return payments.isNotEmpty || ups.isNotEmpty || dels.isNotEmpty;
  }

  /// Lançamentos derivados em aberto (`sh_pr_` / `sh_rr_`) que o usuário
  /// marcou como concluídos no orçamento.
  List<({SharedExpense expense, String userId, int amount, DateTime date})>
  paidInBudget() {
    final out =
        <({SharedExpense expense, String userId, int amount, DateTime date})>[];
    for (final t in finance.data.transactions) {
      if (t.status != TransactionStatus.completed) continue;
      final String userId;
      final String expenseId;
      if (t.id.startsWith('sh_pr_')) {
        userId = me;
        expenseId = t.id.substring(6);
      } else if (t.id.startsWith('sh_rr_')) {
        final rest = t.id.substring(6);
        final i = rest.indexOf('_');
        if (i < 0) continue;
        expenseId = rest.substring(0, i);
        userId = rest.substring(i + 1);
      } else {
        continue;
      }
      final e = state.expense(expenseId);
      final open = e?.shareOf(userId)?.outstanding ?? 0;
      if (e == null || e.isDeleted || open <= 0) continue;
      final amount = t.amount.cents < open ? t.amount.cents : open;
      out.add((
        expense: e,
        userId: userId,
        amount: amount,
        date: Dates.today(),
      ));
    }
    return out;
  }

  /// Executa uma ação no servidor e recarrega.
  Future<T> _act<T>(Future<T> Function(SharedApi api) fn) async {
    final api = this.api;
    if (api == null) {
      throw StateError('Disponível apenas com a conta na nuvem');
    }
    final r = await fn(api);
    await refresh();
    return r;
  }

  // Consultas ------------------------------------------------------------------

  List<ShareGroup> get groups =>
      state.groups.where((g) => !g.archived).toList();

  ShareGroup? group(String? id) => state.group(id);

  /// Despesa compartilhada a partir de um lançamento meu (id da transação ou
  /// ocorrência recorrente).
  SharedExpense? expenseForTx(FinTransaction t) {
    if (SharedBudgetSync.isDerived(t.id)) {
      final id = SharedBudgetSync.expenseIdOf(t.id, state);
      return id == null ? null : state.expense(id);
    }
    final keys = {
      t.id,
      if (t.recurringId != null && t.occurrenceDate != null)
        for (final r in state.groups.expand((g) => g.recurrences))
          if (r.ownerId == me &&
              r.sourceRuleId != null &&
              OwnerReconcile.ruleChain(
                r.sourceRuleId!,
                finance.data.recurringRules,
              ).contains(t.recurringId))
            OwnerReconcile.recurringKey(r.sourceRuleId!, t.occurrenceDate!),
    };
    return state.allExpenses
        .where(
          (e) => !e.isDeleted && e.ownerId == me && keys.contains(e.sourceKey),
        )
        .firstOrNull;
  }

  /// Recorrência compartilhada de uma regra minha.
  ShareRecurrence? recurrenceForRule(RecurringRule r) {
    for (final g in state.groups) {
      for (final x in g.recurrences) {
        if (x.ownerId != me || x.sourceRuleId == null) continue;
        if (OwnerReconcile.ruleChain(
          x.sourceRuleId!,
          finance.data.recurringRules,
        ).contains(r.id)) {
          return x;
        }
      }
    }
    return null;
  }

  /// Grupos em que posso lançar despesas.
  List<ShareGroup> get managedGroups =>
      groups.where((g) => g.myRole.canManage).toList();

  /// Categoria do grupo sugerida para uma categoria do meu orçamento:
  /// última escolha, mesmo nome, ou "Outras despesas".
  ShareCategory? suggestCategory(ShareGroup g, String? budgetCategoryId) {
    final cats = g.activeCategories;
    final mapped = g.category(g.categoryMap[budgetCategoryId]);
    if (mapped != null && !mapped.archived) return mapped;
    final name = finance.data.categories
        .where((c) => c.id == budgetCategoryId)
        .firstOrNull
        ?.name;
    if (name != null) {
      final hit = cats
          .where((c) => SharedBudgetSync.sameName(c.name, name))
          .firstOrNull;
      if (hit != null) return hit;
    }
    return cats
            .where((c) => SharedBudgetSync.sameName(c.name, 'Outras despesas'))
            .firstOrNull ??
        cats.firstOrNull;
  }

  // Grupos e participantes -----------------------------------------------------

  Future<String> createGroup(String name, GroupKind kind) =>
      _act((a) => a.createGroup(name, kind));

  Future<void> updateGroup(
    ShareGroup g, {
    String? name,
    GroupKind? kind,
    bool? archived,
  }) => _act(
    (a) => a.updateGroup(g.id, name: name, kind: kind, archived: archived),
  );

  Future<void> invite(ShareGroup g, String email, ShareRole role) =>
      _act((a) => a.invite(g.id, email.trim(), role));

  Future<void> respondInvite(ShareInvite i, bool accept) =>
      _act((a) => a.respondInvite(i.groupId, accept));

  Future<void> setRole(ShareGroup g, String userId, ShareRole role) =>
      _act((a) => a.setRole(g.id, userId, role));

  Future<void> removeMember(ShareGroup g, String userId) =>
      _act((a) => a.removeMember(g.id, userId));

  // Categorias -------------------------------------------------------------------

  Future<void> saveCategory(
    ShareGroup g, {
    ShareCategory? category,
    required String name,
    required Map<String, int> percentages,
  }) {
    final err = ShareMath.checkPercentages(percentages, g.activeIds);
    if (err != null) throw ArgumentError(err);
    return _act(
      (a) => category == null
          ? a.createCategory(g.id, name, percentages)
          : a.updateCategory(category.id, name: name, percentages: percentages),
    );
  }

  Future<void> archiveCategory(ShareCategory c, bool archived) =>
      _act((a) => a.updateCategory(c.id, archived: archived));

  Future<int> recalculate(ShareGroup g, {String? categoryId}) =>
      _act((a) => a.recalculate(g.id, categoryId: categoryId));

  // Despesas -------------------------------------------------------------------

  /// Compartilha um lançamento meu num grupo.
  Future<void> shareTransaction(
    FinTransaction t, {
    required ShareGroup group,
    required ShareCategory category,
    Map<String, int>? override,
    bool updateDefault = false,
    String notes = '',
  }) {
    if (override != null) {
      final err = ShareMath.checkPercentages(override, group.activeIds);
      if (err != null) throw ArgumentError(err);
    }
    if (t.type != TransactionType.expense) {
      throw ArgumentError('Só despesas podem ser compartilhadas');
    }
    final src = OwnerReconcile.sourceOf(finance.engine, t, groupId: group.id);
    return _act(
      (a) => a.upsertExpense({
        ...src.toJson(),
        'categoryId': category.id,
        'override': ?override,
        'updateDefault': updateDefault,
        'notes': notes,
        'budgetCategoryId': ?t.categoryId,
      }),
    );
  }

  /// Compartilha uma regra recorrente: as ocorrências (passadas deste mês em
  /// diante e as próximas) entram no grupo automaticamente.
  Future<void> shareRule(
    RecurringRule r, {
    required ShareGroup group,
    required ShareCategory category,
    Map<String, int>? override,
  }) async {
    if (override != null) {
      final err = ShareMath.checkPercentages(override, group.activeIds);
      if (err != null) throw ArgumentError(err);
    }
    await _act(
      (a) => a.createRecurrence({
        'groupId': group.id,
        'categoryId': category.id,
        'sourceRuleId': r.id,
        'description': r.description,
        'override': ?override,
      }),
    );
  }

  Future<void> setRecurrencePaused(ShareRecurrence r, bool paused) =>
      _act((a) => a.updateRecurrence(r.id, {'paused': paused}));

  Future<void> updateRecurrence(
    ShareRecurrence r, {
    String? categoryId,
    Map<String, int>? override,
    bool clearOverride = false,
  }) => _act(
    (a) => a.updateRecurrence(r.id, {
      'categoryId': ?categoryId,
      if (override != null || clearOverride) 'override': override,
    }),
  );

  Future<void> cancelRecurrence(ShareRecurrence r) =>
      _act((a) => a.cancelRecurrence(r.id, Dates.today()));

  Future<void> updateExpense(
    SharedExpense e, {
    String? categoryId,
    String? notes,
    Map<String, int>? override,
    bool resetOverride = false,
    bool updateDefault = false,
  }) => _act(
    (a) => a.updateExpense(e.id, {
      'categoryId': ?categoryId,
      'notes': ?notes,
      if (resetOverride) 'override': null else 'override': ?override,
      if (updateDefault) 'updateDefault': true,
    }),
  );

  Future<void> deleteExpense(SharedExpense e) =>
      _act((a) => a.deleteExpense(e.id));

  // Pagamentos e acertos -------------------------------------------------------

  Future<void> addPayment(
    SharedExpense e, {
    required String userId,
    required int amount,
    required DateTime date,
    String note = '',
  }) => _act(
    (a) => a.addPayment(
      e.id,
      userId: userId,
      amount: amount,
      date: date,
      note: note,
    ),
  );

  Future<void> deletePayment(SharePayment p) =>
      _act((a) => a.deletePayment(p.id));

  Future<void> settle(
    ShareGroup g, {
    required String fromUserId,
    required String toUserId,
    required int amount,
    required DateTime date,
    String note = '',
  }) => _act(
    (a) => a.settle(
      g.id,
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
      date: date,
      note: note,
    ),
  );

  Future<void> deleteSettlement(ShareSettlement s) =>
      _act((a) => a.deleteSettlement(s.id));

  Future<List<ShareAuditEntry>> history(ShareGroup g) {
    final api = this.api;
    if (api == null) return Future.value(const []);
    return api.history(g.id);
  }
}
