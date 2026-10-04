import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/default_categories.dart';
import '../data/default_dashboards.dart' as seed;
import '../data/finance_repository.dart';
import '../data/open_finance.dart';
import '../data/sample_data.dart';
import '../domain/engine/billing_cycle.dart';
import '../domain/engine/dashboard_engine.dart';
import '../domain/engine/financial_engine.dart';
import '../domain/engine/installments.dart';
import '../domain/import/expense_import.dart';
import '../domain/models/dashboard.dart';
import '../domain/models/entities.dart';

/// Escopo de alteração de uma regra recorrente.
enum RuleEditScope {
  /// Somente ocorrências futuras (a partir de hoje). Ocorrências já
  /// lançadas/planejadas permanecem como estão.
  futureOnly,

  /// Ocorrências futuras **e** ocorrências planejadas/pendentes já
  /// registradas desta regra.
  futureAndPlanned,
}

/// Fonte única de estado financeiro do usuário logado.
///
/// Todas as mutações passam por aqui: gravamos no repositório e
/// recarregamos a foto ([FinanceData]); o [FinancialEngine] é recriado e
/// todas as telas recalculam automaticamente (projeção, saldos, faturas…).
class FinanceController extends ChangeNotifier {
  final FinanceRepository repo;
  final bool isDemo;
  final OpenFinanceProvider openFinance;

  FinanceController(
    this.repo, {
    this.isDemo = false,
    OpenFinanceProvider? openFinance,
  }) : openFinance = openFinance ?? SandboxOpenFinanceProvider();

  FinanceData data = FinanceData();
  FinancialEngine engine = FinancialEngine(FinanceData());
  List<OpenFinanceConnection> connections = [];
  List<ExternalTransaction> externalTransactions = [];

  /// Painéis personalizados, ordenados.
  List<Dashboard> dashboards = [];

  /// Motor dos gráficos, sempre derivado do [engine] atual — qualquer
  /// mudança nas transações recalcula todos os painéis.
  DashboardEngine get dashboardEngine => _dashEngine?.engine == engine
      ? _dashEngine!
      : (_dashEngine = DashboardEngine(engine));
  DashboardEngine? _dashEngine;

  bool loading = true;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      var d = await repo.load();
      if (d.categories.isEmpty) {
        // Primeiro acesso: categorias padrão (+ dados de exemplo na demo).
        final ops = isDemo
            ? buildSampleData()
            : [
                for (final c in defaultCategories())
                  WriteOp.put(Coll.categories, c.id, c.toJson()),
              ];
        await repo.write(ops);
        if (isDemo) {
          await repo.saveSettings(const AppSettings(isSampleData: true));
        }
        d = await repo.load();
      }
      _set(d);
      connections = await repo.loadConnections();
      externalTransactions = await repo.loadExternalTransactions();
      dashboards = await repo.loadDashboards();
      if (dashboards.isEmpty) {
        final d = seed.defaultDashboard();
        await repo.write([WriteOp.put(Coll.dashboards, d.id, d.toJson())]);
        dashboards = [d];
      }
      _sortDashboards();
    } catch (e) {
      error = 'Falha ao carregar dados: $e';
    }
    loading = false;
    notifyListeners();
  }

  void _set(FinanceData d) {
    data = d;
    engine = FinancialEngine(d);
  }

  Future<void> _commit(List<WriteOp> ops) async {
    await repo.write(ops);
    _set(await repo.load());
    notifyListeners();
  }

  WriteOp _putTx(FinTransaction t) =>
      WriteOp.put(Coll.transactions, t.id, t.toJson());

  // ---------------------------------------------------------------------------
  // Validação

  /// Valida regras de integridade de uma transação. Retorna mensagem de erro
  /// ou `null`.
  String? validateTransaction(FinTransaction t) {
    if (t.amount.cents <= 0) return 'O valor deve ser maior que zero';
    if (t.description.trim().isEmpty) return 'Informe uma descrição';
    if (t.isTransfer) {
      if (t.accountId == null || t.destinationAccountId == null) {
        return 'Selecione as contas de origem e destino';
      }
      if (t.accountId == t.destinationAccountId) {
        return 'Origem e destino devem ser contas diferentes';
      }
      if (t.cardId != null) return 'Transferências não usam cartão';
    } else {
      if ((t.accountId == null) == (t.cardId == null)) {
        return 'Selecione uma conta ou um cartão';
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Transações

  /// Cria ou atualiza. Ocorrências virtuais são materializadas (ganham ID
  /// próprio e mantêm o vínculo regra + data de ocorrência).
  Future<void> saveTransaction(FinTransaction t) async {
    final err = validateTransaction(t);
    if (err != null) throw ArgumentError(err);
    final tx = t.isVirtual ? t.copyWith(id: newId('tx_'), isVirtual: false) : t;
    await _commit([_putTx(tx)]);
  }

  Future<void> setStatus(FinTransaction t, TransactionStatus status) =>
      saveTransaction(t.copyWith(status: status));

  /// Alterna o status direto da lista (Concluída ⇄ Pendente).
  Future<void> toggleCompleted(FinTransaction t, bool completed) async {
    final status = completed
        ? TransactionStatus.completed
        : TransactionStatus.pending;
    if (t.status == status) return;
    await saveInline(t.copyWith(status: status));
  }

  /// Grava uma edição feita direto na grade (status, valor, descrição…).
  ///
  /// A mudança é aplicada de forma otimista na memória — telas, indicadores
  /// e painéis recalculam no mesmo quadro — e em seguida gravada no banco.
  /// Se a gravação falhar, os dados são recarregados do banco (desfaz).
  /// Ocorrências virtuais de recorrência são materializadas: a edição vale
  /// só para aquela ocorrência, como no formulário.
  Future<void> saveInline(FinTransaction t) async {
    final err = validateTransaction(t);
    if (err != null) throw ArgumentError(err);
    final tx = t.isVirtual ? t.copyWith(id: newId('tx_'), isVirtual: false) : t;
    _set(
      data.copyWith(
        transactions: [
          for (final x in data.transactions)
            if (x.id != tx.id) x,
          tx,
        ],
      ),
    );
    notifyListeners();
    try {
      await repo.write([_putTx(tx)]);
    } finally {
      _set(await repo.load());
      notifyListeners();
    }
  }

  /// Exclui um lançamento. Para ocorrência virtual de recorrência, grava uma
  /// ocorrência cancelada (para que a regra não volte a gerá-la).
  Future<void> deleteTransaction(FinTransaction t) async {
    if (t.isVirtual) {
      await _commit([
        _putTx(
          t.copyWith(
            id: newId('tx_'),
            isVirtual: false,
            status: TransactionStatus.cancelled,
          ),
        ),
      ]);
      return;
    }
    final ops = <WriteOp>[WriteOp.delete(Coll.transactions, t.id)];
    // Remove o vínculo com transação externa conciliada, se houver.
    for (final e in externalTransactions) {
      if (e.matchedTransactionId == t.id) {
        final u = e.copyWith(
          status: ExternalTxStatus.pending,
          matchedTransactionId: null,
        );
        ops.add(WriteOp.put(Coll.externalTransactions, u.id, u.toJson()));
      }
    }
    await _commit(ops);
    externalTransactions = await repo.loadExternalTransactions();
  }

  // ---------------------------------------------------------------------------
  // Importação de planilha

  /// Grava, em um único lote, as despesas selecionadas de uma importação
  /// (categorias novas, compras parceladas e lançamentos).
  Future<ExpenseImportBatch> importExpenses(ExpenseImportPlan plan) async {
    final batch = plan.build(today: engine.today);
    if (batch.rowCount == 0) {
      throw ArgumentError('Nenhuma despesa selecionada para importar');
    }
    for (final t in batch.transactions) {
      final err = validateTransaction(t);
      if (err != null) throw ArgumentError(err);
    }
    await _commit([
      for (final c in batch.categories)
        WriteOp.put(Coll.categories, c.id, c.toJson()),
      for (final g in batch.groups)
        WriteOp.put(Coll.installmentGroups, g.id, g.toJson()),
      ...batch.transactions.map(_putTx),
    ]);
    return batch;
  }

  // ---------------------------------------------------------------------------
  // Parcelamentos

  Future<InstallmentGroup> createInstallmentPurchase(
    InstallmentGroup g, {
    TransactionStatus firstStatus = TransactionStatus.completed,
  }) async {
    if (g.count < 2) throw ArgumentError('Informe ao menos 2 parcelas');
    if (g.totalAmount.cents < g.count) {
      throw ArgumentError('Valor insuficiente para o número de parcelas');
    }
    if ((g.accountId == null) == (g.cardId == null)) {
      throw ArgumentError('Selecione uma conta ou um cartão');
    }
    final parts = Installments.build(g, firstStatus: firstStatus);
    await _commit([
      WriteOp.put(Coll.installmentGroups, g.id, g.toJson()),
      ...parts.map(_putTx),
    ]);
    return g;
  }

  List<FinTransaction> installmentsOf(String groupId) =>
      data.transactions.where((t) => t.installmentGroupId == groupId).toList()
        ..sort(
          (a, b) =>
              (a.installmentNumber ?? 0).compareTo(b.installmentNumber ?? 0),
        );

  /// Parcela "futura" = ainda não faturada (cartão) ou não vencida/paga
  /// (conta). Parcelas passadas nunca são alteradas.
  bool isFutureInstallment(FinTransaction t) {
    if (t.status == TransactionStatus.cancelled ||
        t.status == TransactionStatus.completed && t.cardId == null) {
      return false;
    }
    final card = data.cardById[t.cardId];
    if (card != null) {
      return BillingCycle.invoiceForTransaction(card, t) >
          BillingCycle.currentInvoice(card, engine.today);
    }
    return t.date.isAfter(engine.today) ||
        t.status != TransactionStatus.completed;
  }

  /// Cancela as parcelas futuras (ex.: quitação antecipada ou devolução),
  /// preservando o histórico.
  Future<int> cancelFutureInstallments(String groupId) async {
    final ops = <WriteOp>[];
    for (final t in installmentsOf(groupId)) {
      if (isFutureInstallment(t)) {
        ops.add(_putTx(t.copyWith(status: TransactionStatus.cancelled)));
      }
    }
    await _commit(ops);
    return ops.length;
  }

  /// Altera o valor das parcelas futuras (ex.: renegociação).
  Future<int> updateFutureInstallmentAmount(
    String groupId,
    Money newAmount,
  ) async {
    final ops = <WriteOp>[];
    for (final t in installmentsOf(groupId)) {
      if (isFutureInstallment(t)) {
        ops.add(_putTx(t.copyWith(amount: newAmount)));
      }
    }
    await _commit(ops);
    return ops.length;
  }

  /// Transforma um lançamento à vista já salvo em compra parcelada: o
  /// lançamento é substituído pelas parcelas do grupo [g] (no cartão, cada
  /// parcela cai na fatura correspondente). A 1ª parcela herda o status do
  /// lançamento original.
  Future<InstallmentGroup> convertToInstallments(
    FinTransaction t,
    InstallmentGroup g,
  ) async {
    if (t.isVirtual || t.isInstallment || t.isTransfer) {
      throw ArgumentError('Este lançamento não pode ser parcelado');
    }
    _checkGroup(g);
    final parts = Installments.build(
      g,
      firstStatus: t.status,
      today: engine.today,
    );
    await _commit([
      WriteOp.delete(Coll.transactions, t.id),
      WriteOp.put(Coll.installmentGroups, g.id, g.toJson()),
      ...parts.map(_putTx),
      ..._relinkExternal(t.id, parts.first.id),
    ]);
    externalTransactions = await repo.loadExternalTransactions();
    if (g.cardId != null) await _syncCardInvoices(g.cardId!, parts);
    return g;
  }

  /// Altera uma compra parcelada inteira: valor total, número de parcelas,
  /// data, descrição, categoria... As parcelas são recalculadas mantendo o
  /// ID e o status das que já existiam (mesmo número); as que sobram são
  /// excluídas. Com [InstallmentGroup.count] = 1 a compra volta a ser um
  /// lançamento à vista.
  Future<void> updateInstallmentGroup(InstallmentGroup updated) async {
    final old = data.groupById[updated.id];
    if (old == null) throw ArgumentError('Parcelamento não encontrado');
    final current = installmentsOf(old.id);
    final byNumber = {for (final t in current) t.installmentNumber: t};
    final ops = <WriteOp>[];
    final List<FinTransaction> next;
    if (updated.count == 1) {
      if ((updated.accountId == null) == (updated.cardId == null)) {
        throw ArgumentError('Selecione uma conta ou um cartão');
      }
      final first = byNumber[1];
      final single = FinTransaction(
        id: first?.id ?? newId('tx_'),
        type: TransactionType.expense,
        amount: updated.totalAmount,
        description: updated.description,
        categoryId: updated.categoryId,
        date: updated.purchaseDate,
        accountId: updated.accountId,
        cardId: updated.cardId,
        projectId: updated.projectId,
        notes: updated.notes,
        status: first?.status ?? TransactionStatus.pending,
        externalId: first?.externalId,
        createdAt: first?.createdAt,
      );
      next = [single];
      ops.add(WriteOp.delete(Coll.installmentGroups, old.id));
    } else {
      _checkGroup(updated);
      final built = Installments.build(
        updated,
        firstStatus: byNumber[1]?.status ?? TransactionStatus.pending,
        today: engine.today,
      );
      next = [
        for (final p in built)
          if (byNumber[p.installmentNumber] case final prev?)
            p.copyWith(
              id: prev.id,
              status: prev.status,
              externalId: prev.externalId,
            )
          else
            p,
      ];
      ops.add(
        WriteOp.put(Coll.installmentGroups, updated.id, updated.toJson()),
      );
    }
    final keep = {for (final t in next) t.id};
    for (final t in current) {
      if (!keep.contains(t.id)) {
        ops.add(WriteOp.delete(Coll.transactions, t.id));
      }
    }
    ops.addAll(next.map(_putTx));
    await _commit(ops);
    for (final cardId in {old.cardId, updated.cardId}) {
      if (cardId != null) {
        await _syncCardInvoices(cardId, [...current, ...next]);
      }
    }
  }

  void _checkGroup(InstallmentGroup g) {
    if (g.count < 2) throw ArgumentError('Informe ao menos 2 parcelas');
    if (g.totalAmount.cents < g.count) {
      throw ArgumentError('Valor insuficiente para o número de parcelas');
    }
    if (g.description.trim().isEmpty) {
      throw ArgumentError('Informe uma descrição');
    }
    if ((g.accountId == null) == (g.cardId == null)) {
      throw ArgumentError('Selecione uma conta ou um cartão');
    }
  }

  /// Transações externas conciliadas com [fromId] passam a apontar [toId].
  List<WriteOp> _relinkExternal(String fromId, String toId) => [
    for (final e in externalTransactions)
      if (e.matchedTransactionId == fromId)
        () {
          final u = e.copyWith(matchedTransactionId: toId);
          return WriteOp.put(Coll.externalTransactions, u.id, u.toJson());
        }(),
  ];

  /// Reaplica o status das faturas tocadas por [txs] (o status das compras
  /// acompanha a fatura).
  Future<void> _syncCardInvoices(
    String cardId,
    Iterable<FinTransaction> txs,
  ) async {
    final card = data.cardById[cardId];
    if (card == null) return;
    final months = {
      for (final t in txs)
        if (t.cardId == cardId) BillingCycle.invoiceForTransaction(card, t),
    };
    for (final m in months) {
      await _syncInvoiceItems(cardId, m);
    }
  }

  /// Exclui a compra parcelada inteira (todas as parcelas).
  Future<void> deleteInstallmentGroup(String groupId) => _commit([
    WriteOp.delete(Coll.installmentGroups, groupId),
    for (final t in installmentsOf(groupId))
      WriteOp.delete(Coll.transactions, t.id),
  ]);

  // ---------------------------------------------------------------------------
  // Recorrências

  Future<void> createRule(RecurringRule r) =>
      _commit([WriteOp.put(Coll.recurringTransactions, r.id, r.toJson())]);

  /// Torna recorrente um lançamento já salvo (ex.: assinatura lançada na
  /// fatura): cria a regra a partir da data dele e vincula o lançamento como
  /// a 1ª ocorrência, para que ela não seja gerada em duplicidade.
  Future<void> convertToRecurring(FinTransaction t, RecurringRule rule) async {
    if (t.isVirtual || t.isRecurring || t.isInstallment || t.isTransfer) {
      throw ArgumentError('Este lançamento não pode virar recorrência');
    }
    final err = validateTransaction(t);
    if (err != null) throw ArgumentError(err);
    final r = rule.copyWith(startDate: t.date);
    await _commit([
      WriteOp.put(Coll.recurringTransactions, r.id, r.toJson()),
      _putTx(t.copyWith(recurringId: r.id, occurrenceDate: t.date)),
    ]);
  }

  /// Atualiza uma regra respeitando o histórico:
  /// * Se a regra ainda não começou, é alterada diretamente.
  /// * Caso contrário, a regra atual é encerrada ontem e uma nova regra
  ///   (versão) passa a valer a partir de hoje, de modo que ocorrências
  ///   passadas continuem com os valores antigos.
  /// * Com [RuleEditScope.futureAndPlanned], ocorrências já registradas e
  ///   ainda não concluídas também recebem os novos dados.
  Future<void> updateRule(
    RecurringRule old,
    RecurringRule updated,
    RuleEditScope scope,
  ) async {
    final today = engine.today;
    final ops = <WriteOp>[];
    RecurringRule target;
    if (!old.startDate.isBefore(today)) {
      target = updated;
      ops.add(
        WriteOp.put(Coll.recurringTransactions, target.id, target.toJson()),
      );
    } else {
      final ended = old.copyWith(
        endDate: today.subtract(const Duration(days: 1)),
      );
      target = updated.copyWith(
        id: newId('rec_'),
        startDate: updated.startDate.isBefore(today)
            ? today
            : updated.startDate,
        previousRuleId: old.id,
      );
      ops
        ..add(WriteOp.put(Coll.recurringTransactions, ended.id, ended.toJson()))
        ..add(
          WriteOp.put(Coll.recurringTransactions, target.id, target.toJson()),
        );
      // Ocorrências futuras já materializadas passam para a nova versão.
      for (final t in data.transactions) {
        if (t.recurringId != old.id || t.occurrenceDate == null) continue;
        if (t.occurrenceDate!.isBefore(today)) continue;
        ops.add(_putTx(t.copyWith(recurringId: target.id)));
      }
    }
    if (scope == RuleEditScope.futureAndPlanned) {
      for (final t in data.transactions) {
        if (t.recurringId != old.id) continue;
        if (t.status != TransactionStatus.planned &&
            t.status != TransactionStatus.pending) {
          continue;
        }
        final isFuture =
            t.occurrenceDate != null && !t.occurrenceDate!.isBefore(today);
        ops.add(
          _putTx(
            t.copyWith(
              amount: target.amount,
              description: target.description,
              categoryId: target.categoryId,
              accountId: target.accountId,
              cardId: target.cardId,
              projectId: target.projectId,
              recurringId: isFuture ? target.id : old.id,
            ),
          ),
        );
      }
    }
    // Mantém a última escrita por ID (evita gravar duas versões).
    final dedup = <String, WriteOp>{};
    for (final op in ops) {
      dedup['${op.coll.name}/${op.id}'] = op;
    }
    await _commit(dedup.values.toList());
  }

  Future<void> pauseRule(RecurringRule r) {
    if (r.isPaused) return Future.value();
    final p = r.copyWith(pauses: [...r.pauses, PausePeriod(engine.today)]);
    return _commit([WriteOp.put(Coll.recurringTransactions, p.id, p.toJson())]);
  }

  Future<void> resumeRule(RecurringRule r) {
    final pauses = [
      for (final p in r.pauses)
        p.to == null ? PausePeriod(p.from, engine.today) : p,
    ];
    final u = r.copyWith(pauses: pauses);
    return _commit([WriteOp.put(Coll.recurringTransactions, u.id, u.toJson())]);
  }

  /// Exclui a regra. Lançamentos **concluídos** são preservados (histórico);
  /// ocorrências planejadas/pendentes registradas são removidas.
  Future<void> deleteRule(RecurringRule r) => _commit([
    WriteOp.delete(Coll.recurringTransactions, r.id),
    for (final t in data.transactions)
      if (t.recurringId == r.id && t.status != TransactionStatus.completed)
        WriteOp.delete(Coll.transactions, t.id),
  ]);

  // ---------------------------------------------------------------------------
  // Faturas

  Future<void> payInvoice(
    Invoice inv,
    Money amount, {
    required DateTime date,
    required String accountId,
  }) async {
    if (amount.cents <= 0) throw ArgumentError('Valor inválido');
    final p = InvoicePayment(
      id: newId('pay_'),
      cardId: inv.card.id,
      invoiceKey: inv.key,
      amount: amount,
      date: date,
      accountId: accountId,
    );
    await _commit([WriteOp.put(Coll.invoicePayments, p.id, p.toJson())]);
    await _syncInvoiceItems(inv.card.id, inv.month);
  }

  Future<void> deleteInvoicePayment(InvoicePayment p) async {
    await _commit([WriteOp.delete(Coll.invoicePayments, p.id)]);
    await _syncInvoiceItems(p.cardId, YearMonth.parse(p.invoiceKey));
  }

  /// O status das compras acompanha a fatura: quitada, todas ficam
  /// concluídas; reaberta (pagamento desfeito), as concluídas voltam a
  /// pendente. As compras não são pagas uma a uma.
  Future<void> _syncInvoiceItems(String cardId, YearMonth month) async {
    final card = data.cardById[cardId];
    if (card == null) return;
    final inv = engine.invoice(card, month);
    final settled = inv.total.isPositive && inv.paid >= inv.total;
    final ops = <WriteOp>[];
    for (final t in inv.transactions) {
      if (settled && t.status != TransactionStatus.completed) {
        ops.add(
          _putTx(
            t.isVirtual
                ? t.copyWith(
                    id: newId('tx_'),
                    isVirtual: false,
                    status: TransactionStatus.completed,
                  )
                : t.copyWith(status: TransactionStatus.completed),
          ),
        );
      } else if (!settled &&
          !t.isVirtual &&
          t.status == TransactionStatus.completed) {
        ops.add(_putTx(t.copyWith(status: TransactionStatus.pending)));
      }
    }
    if (ops.isNotEmpty) await _commit(ops);
  }

  // ---------------------------------------------------------------------------
  // Cadastros

  Future<void> saveAccount(Account a) =>
      _commit([WriteOp.put(Coll.accounts, a.id, a.toJson())]);

  bool accountInUse(String id) =>
      data.transactions.any(
        (t) => t.accountId == id || t.destinationAccountId == id,
      ) ||
      data.recurringRules.any((r) => r.accountId == id) ||
      data.invoicePayments.any((p) => p.accountId == id);

  /// Contas com histórico não podem ser excluídas (apenas desativadas), para
  /// preservar a integridade dos saldos.
  Future<void> deleteAccount(Account a) {
    if (accountInUse(a.id)) {
      throw StateError(
        'A conta possui lançamentos. Desative-a em vez de excluir.',
      );
    }
    return _commit([WriteOp.delete(Coll.accounts, a.id)]);
  }

  Future<void> saveCard(CreditCard c) {
    if (c.closingDay < 1 ||
        c.closingDay > 31 ||
        c.dueDay < 1 ||
        c.dueDay > 31) {
      throw ArgumentError(
        'Dias de fechamento/vencimento devem estar entre 1 e 31',
      );
    }
    return _commit([WriteOp.put(Coll.cards, c.id, c.toJson())]);
  }

  bool cardInUse(String id) =>
      data.transactions.any((t) => t.cardId == id) ||
      data.recurringRules.any((r) => r.cardId == id);

  Future<void> deleteCard(CreditCard c) {
    if (cardInUse(c.id)) {
      throw StateError(
        'O cartão possui lançamentos. Desative-o em vez de excluir.',
      );
    }
    return _commit([WriteOp.delete(Coll.cards, c.id)]);
  }

  Future<void> saveCategory(FinCategory c) =>
      _commit([WriteOp.put(Coll.categories, c.id, c.toJson())]);

  /// Exclui a categoria; subcategorias e lançamentos passam para a categoria
  /// pai (ou ficam sem categoria).
  Future<void> deleteCategory(FinCategory c) => _commit([
    WriteOp.delete(Coll.categories, c.id),
    for (final sub in data.categories.where((x) => x.parentId == c.id))
      WriteOp.put(
        Coll.categories,
        sub.id,
        sub.copyWith(parentId: c.parentId).toJson(),
      ),
    for (final t in data.transactions.where((t) => t.categoryId == c.id))
      _putTx(t.copyWith(categoryId: c.parentId)),
    for (final r in data.recurringRules.where((r) => r.categoryId == c.id))
      WriteOp.put(
        Coll.recurringTransactions,
        r.id,
        r.copyWith(categoryId: c.parentId).toJson(),
      ),
  ]);

  Future<void> saveProject(Project p) =>
      _commit([WriteOp.put(Coll.projects, p.id, p.toJson())]);

  /// Exclui o projeto e desvincula os lançamentos (que são preservados).
  Future<void> deleteProject(Project p) => _commit([
    WriteOp.delete(Coll.projects, p.id),
    for (final t in data.transactions.where((t) => t.projectId == p.id))
      _putTx(t.copyWith(projectId: null)),
    for (final r in data.recurringRules.where((r) => r.projectId == p.id))
      WriteOp.put(
        Coll.recurringTransactions,
        r.id,
        r.copyWith(projectId: null).toJson(),
      ),
  ]);

  Future<void> saveSettings(AppSettings s) async {
    await repo.saveSettings(s);
    _set(await repo.load());
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Painéis personalizados

  void _sortDashboards() => dashboards.sort((a, b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  });

  Dashboard? dashboardById(String? id) =>
      dashboards.where((d) => d.id == id).firstOrNull;

  /// Painel padrão (exibido na tela inicial).
  Dashboard? get defaultDashboard =>
      dashboards.where((d) => d.isDefault).firstOrNull ??
      dashboards.firstOrNull;

  /// Aplica a mudança na memória (UI responde na hora) e grava em seguida.
  Future<void> _writeDashboards(
    List<Dashboard> changed, {
    String? deleted,
  }) async {
    final byId = {for (final d in dashboards) d.id: d};
    for (final d in changed) {
      byId[d.id] = d;
    }
    if (deleted != null) byId.remove(deleted);
    dashboards = byId.values.toList();
    _sortDashboards();
    notifyListeners();
    await repo.write([
      for (final d in changed) WriteOp.put(Coll.dashboards, d.id, d.toJson()),
      if (deleted != null) WriteOp.delete(Coll.dashboards, deleted),
    ]);
  }

  Future<void> saveDashboard(Dashboard d) {
    if (d.name.trim().isEmpty) throw ArgumentError('Informe um nome');
    return _writeDashboards([d]);
  }

  Future<Dashboard> createDashboard(String name) async {
    final d = seed.emptyDashboard(
      name.trim().isEmpty ? 'Novo painel' : name.trim(),
      order: dashboards.length,
    );
    await _writeDashboards([d]);
    return d;
  }

  Future<Dashboard> duplicateDashboard(Dashboard d) async {
    final copy = Dashboard(
      id: newId('dash_'),
      name: '${d.name} (cópia)',
      order: dashboards.length,
      filter: d.filter,
      charts: [for (final c in d.charts) c.copyWith(id: newId('ch_'))],
    );
    await _writeDashboards([copy]);
    return copy;
  }

  Future<void> renameDashboard(Dashboard d, String name) =>
      saveDashboard(d.copyWith(name: name.trim()));

  Future<void> setDefaultDashboard(Dashboard d) => _writeDashboards([
    for (final x in dashboards)
      if (x.id == d.id && !x.isDefault)
        x.copyWith(isDefault: true)
      else if (x.id != d.id && x.isDefault)
        x.copyWith(isDefault: false),
  ]);

  /// Exclui o painel. O último painel não pode ser excluído; se o padrão for
  /// excluído, o primeiro restante passa a ser o padrão.
  Future<void> deleteDashboard(Dashboard d) async {
    if (dashboards.length <= 1) {
      throw StateError('Mantenha ao menos um painel.');
    }
    final rest = dashboards.where((x) => x.id != d.id).toList();
    final promote = d.isDefault && !rest.any((x) => x.isDefault)
        ? [rest.first.copyWith(isDefault: true)]
        : <Dashboard>[];
    await _writeDashboards(promote, deleted: d.id);
  }

  // ---------------------------------------------------------------------------
  // Open Finance

  Future<void> connectInstitution(OFInstitution inst) async {
    final consent = await openFinance.requestConsent(inst);
    final c = OpenFinanceConnection(
      id: newId('ofc_'),
      providerId: openFinance.id,
      institutionName: inst.name,
      consentStatus: consent.status,
      consentExpiresAt: consent.expiresAt,
    );
    await repo.write([
      WriteOp.put(Coll.openFinanceConnections, c.id, c.toJson()),
    ]);
    connections = await repo.loadConnections();
    notifyListeners();
  }

  Future<void> linkConnection(
    OpenFinanceConnection c, {
    String? accountId,
    String? cardId,
  }) async {
    final u = c.copyWith(linkedAccountId: accountId, linkedCardId: cardId);
    await repo.write([
      WriteOp.put(Coll.openFinanceConnections, u.id, u.toJson()),
    ]);
    connections = await repo.loadConnections();
    notifyListeners();
  }

  /// Sincroniza transações da conexão. Itens já recebidos (mesmo
  /// `externalId`) são ignorados; os novos passam pela detecção de
  /// duplicidade contra lançamentos manuais.
  Future<({int added, int matched})> syncConnection(
    OpenFinanceConnection c,
  ) async {
    if (c.consentStatus != ConsentStatus.active) {
      throw StateError('Consentimento não está ativo');
    }
    try {
      final fetched = await openFinance.fetchTransactions(c);
      final known = externalTransactions
          .where((e) => e.connectionId == c.id)
          .map((e) => e.externalId)
          .toSet();
      final usedMatches = externalTransactions
          .map((e) => e.matchedTransactionId)
          .whereType<String>()
          .toSet();
      final ops = <WriteOp>[];
      var added = 0, matched = 0;
      for (final e in fetched) {
        if (known.contains(e.externalId)) continue;
        final scope = data.transactions.where(
          (t) =>
              (c.linkedAccountId == null || t.accountId == c.linkedAccountId) &&
              (c.linkedCardId == null || t.cardId == c.linkedCardId),
        );
        final match = DuplicateDetector.findMatch(
          e,
          scope,
          alreadyMatched: usedMatches,
        );
        var ext = e;
        if (match != null) {
          usedMatches.add(match.id);
          ext = e.copyWith(
            status: ExternalTxStatus.matched,
            matchedTransactionId: match.id,
          );
          ops.add(_putTx(match.copyWith(externalId: e.externalId)));
          matched++;
        }
        added++;
        ops.add(WriteOp.put(Coll.externalTransactions, ext.id, ext.toJson()));
      }
      final updated = c.copyWith(lastSyncAt: DateTime.now(), lastError: null);
      ops.add(
        WriteOp.put(Coll.openFinanceConnections, updated.id, updated.toJson()),
      );
      await _commit(ops);
      connections = await repo.loadConnections();
      externalTransactions = await repo.loadExternalTransactions();
      notifyListeners();
      return (added: added, matched: matched);
    } catch (e) {
      final failed = c.copyWith(lastError: e.toString());
      await repo.write([
        WriteOp.put(Coll.openFinanceConnections, failed.id, failed.toJson()),
      ]);
      connections = await repo.loadConnections();
      notifyListeners();
      rethrow;
    }
  }

  /// Importa uma transação externa como lançamento manual.
  Future<void> importExternal(
    ExternalTransaction e,
    OpenFinanceConnection c, {
    String? categoryId,
  }) async {
    final isIncome = e.signedAmount.isPositive;
    String? accountId = c.linkedAccountId;
    final cardId = c.linkedCardId;
    if (accountId == null && cardId == null) {
      accountId = data.accounts.where((a) => a.active).firstOrNull?.id;
    }
    if (accountId == null && cardId == null) {
      throw StateError('Cadastre ou vincule uma conta antes de importar');
    }
    final tx = FinTransaction(
      id: newId('tx_'),
      type: isIncome ? TransactionType.income : TransactionType.expense,
      amount: e.signedAmount.abs(),
      description: e.description,
      categoryId:
          categoryId ?? (isIncome ? 'cat_other_income' : 'cat_other_expense'),
      date: e.date,
      accountId: cardId == null ? accountId : null,
      cardId: cardId,
      status: TransactionStatus.completed,
      externalId: e.externalId,
      notes: 'Importado via Open Finance (${c.institutionName})',
    );
    final u = e.copyWith(
      status: ExternalTxStatus.imported,
      matchedTransactionId: tx.id,
    );
    await _commit([
      _putTx(tx),
      WriteOp.put(Coll.externalTransactions, u.id, u.toJson()),
    ]);
    externalTransactions = await repo.loadExternalTransactions();
    notifyListeners();
  }

  /// Concilia manualmente com um lançamento existente.
  Future<void> reconcileExternal(
    ExternalTransaction e,
    FinTransaction target,
  ) async {
    final u = e.copyWith(
      status: ExternalTxStatus.matched,
      matchedTransactionId: target.id,
    );
    await _commit([
      _putTx(target.copyWith(externalId: e.externalId)),
      WriteOp.put(Coll.externalTransactions, u.id, u.toJson()),
    ]);
    externalTransactions = await repo.loadExternalTransactions();
    notifyListeners();
  }

  Future<void> ignoreExternal(ExternalTransaction e) async {
    final u = e.copyWith(status: ExternalTxStatus.ignored);
    await repo.write([
      WriteOp.put(Coll.externalTransactions, u.id, u.toJson()),
    ]);
    externalTransactions = await repo.loadExternalTransactions();
    notifyListeners();
  }

  Future<void> revokeConnection(OpenFinanceConnection c) async {
    await openFinance.revokeConsent(c);
    final u = c.copyWith(consentStatus: ConsentStatus.revoked);
    await repo.write([
      WriteOp.put(Coll.openFinanceConnections, u.id, u.toJson()),
    ]);
    connections = await repo.loadConnections();
    notifyListeners();
  }

  Future<void> deleteConnection(OpenFinanceConnection c) async {
    await repo.write([
      WriteOp.delete(Coll.openFinanceConnections, c.id),
      for (final e in externalTransactions.where((e) => e.connectionId == c.id))
        WriteOp.delete(Coll.externalTransactions, e.id),
    ]);
    connections = await repo.loadConnections();
    externalTransactions = await repo.loadExternalTransactions();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Utilidades para formulários

  DateTime get today => engine.today;

  List<Account> get activeAccounts =>
      data.accounts.where((a) => a.active).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  List<CreditCard> get activeCards =>
      data.cards.where((c) => c.active).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  List<Project> get activeProjects =>
      data.projects.where((p) => !p.archived).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Fatura em que uma compra no cartão cairá (para exibir no formulário).
  String? invoiceHint(String? cardId, DateTime date) {
    final card = data.cardById[cardId];
    if (card == null) return null;
    final inv = BillingCycle.invoiceFor(card, date);
    return 'Fatura ${inv.shortLabel} · vence ${Dates.format(BillingCycle.dueDate(card, inv))}';
  }
}
