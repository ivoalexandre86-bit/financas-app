import '../../core/dates.dart';
import '../../core/money.dart';
import '../engine/calculators.dart' show AmortizationSystem;

export '../engine/calculators.dart' show AmortizationSystem;

// Dívidas e contratos (empréstimos e financiamentos) cadastrados à mão.
//
// Valores em centavos ([Money]); taxas como fração ao mês (1% = 0.01).
// Nada aqui inicia pagamentos ou altera o contrato no credor: o app só
// planeja. As parcelas que entram na Projeção vêm do compromisso vinculado
// (lançamento recorrente, parcelamento) ou das parcelas geradas a partir do
// contrato, nunca dos dois ao mesmo tempo.

DateTime? _pd(Object? s) => s == null ? null : Dates.fromIso(s as String);
String? _d(DateTime? d) => d == null ? null : Dates.toIso(d);
DateTime _ts(Object? s) =>
    s == null ? DateTime.now() : DateTime.parse(s as String);
Money? _m(Object? v) => v == null ? null : Money((v as num).toInt());
double? _dbl(Object? v) => v == null ? null : (v as num).toDouble();
T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;

/// Sentinela para `copyWith` limpar campos opcionais.
const Object _unset = Object();

enum DebtKind {
  personalLoan('Empréstimo pessoal'),
  payroll('Consignado'),
  vehicle('Financiamento de veículo'),
  realEstate('Financiamento imobiliário'),
  student('Financiamento estudantil'),
  other('Outra dívida');

  final String label;
  const DebtKind(this.label);
}

/// Indexador que corrige o saldo devedor (financiamentos imobiliários, por
/// exemplo). A taxa mensal usada é sempre uma estimativa informada.
enum DebtIndex {
  none('Sem correção'),
  tr('TR'),
  ipca('IPCA'),
  igpm('IGP-M'),
  incc('INCC'),
  cdi('CDI'),
  other('Outro');

  final String label;
  const DebtIndex(this.label);
}

/// O contrato permite a opção? `unknown` = não informado (o app calcula,
/// mas pede para conferir no contrato).
enum OptionSupport {
  unknown('Não sei'),
  allowed('Permite'),
  notAllowed('Não permite');

  final String label;
  const OptionSupport(this.label);
}

/// Opções de antecipação e quitação.
enum PrepayOption {
  lastInstallments('Antecipar as últimas parcelas'),
  reduceTerm('Amortizar e reduzir o prazo'),
  reducePayment('Amortizar e reduzir a parcela'),
  payoff('Quitar o contrato');

  final String label;
  const PrepayOption(this.label);
}

/// De onde vêm as parcelas na Projeção.
enum DebtInstallments {
  none('Não lançar parcelas'),
  linked('Vinculadas a um lançamento existente'),
  generated('Geradas a partir do contrato');

  final String label;
  const DebtInstallments(this.label);
}

/// Encargo mensal cobrado junto com a parcela (seguro MIP/DFI, taxa de
/// administração).
class DebtFee {
  final String name;
  final Money monthly;
  const DebtFee(this.name, this.monthly);

  Map<String, Object?> toJson() => {'name': name, 'monthly': monthly.cents};
  factory DebtFee.fromJson(Map<String, Object?> j) => DebtFee(
    (j['name'] as String?) ?? 'Encargo',
    Money((j['monthly'] as num?)?.toInt() ?? 0),
  );
}

enum QuoteKind {
  payoff('Quitação'),
  prepayment('Amortização'),
  lastInstallments('Últimas parcelas'),
  renegotiation('Renegociação');

  final String label;
  const QuoteKind(this.label);
}

/// Valor informado pelo credor (boleto de quitação, proposta de
/// renegociação). Prevalece sobre a estimativa do app quando existe.
class LenderQuote {
  final String id;
  final QuoteKind kind;
  final DateTime date;
  final Money amount;
  final DateTime? validUntil;

  /// Parcelas cobertas (antecipação das últimas parcelas).
  final int? installments;

  /// Nova parcela e novo prazo (amortização ou renegociação).
  final Money? newPayment;
  final int? newMonths;
  final String note;

  const LenderQuote({
    required this.id,
    required this.kind,
    required this.date,
    required this.amount,
    this.validUntil,
    this.installments,
    this.newPayment,
    this.newMonths,
    this.note = '',
  });

  bool isValidOn(DateTime day) =>
      validUntil == null || !Dates.dateOnly(day).isAfter(validUntil!);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'date': _d(date),
    'amount': amount.cents,
    'validUntil': _d(validUntil),
    'installments': installments,
    'newPayment': newPayment?.cents,
    'newMonths': newMonths,
    'note': note,
  };

  factory LenderQuote.fromJson(Map<String, Object?> j) => LenderQuote(
    id: j['id'] as String,
    kind: _enum(QuoteKind.values, j['kind'], QuoteKind.payoff),
    date: _pd(j['date']) ?? Dates.today(),
    amount: Money((j['amount'] as num?)?.toInt() ?? 0),
    validUntil: _pd(j['validUntil']),
    installments: (j['installments'] as num?)?.toInt(),
    newPayment: _m(j['newPayment']),
    newMonths: (j['newMonths'] as num?)?.toInt(),
    note: (j['note'] as String?) ?? '',
  );
}

/// Arquivo do contrato ou extrato anexado. O conteúdo fica em base64 no
/// próprio registro (limite de [maxBytes]).
class DebtAttachment {
  static const maxBytes = 2 * 1024 * 1024;

  final String id;
  final String name;
  final String mime;
  final int size;
  final String? data; // base64
  final DateTime addedAt;

  DebtAttachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    this.data,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mime': mime,
    'size': size,
    'data': data,
    'addedAt': addedAt.toIso8601String(),
  };

  factory DebtAttachment.fromJson(Map<String, Object?> j) => DebtAttachment(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'arquivo',
    mime: (j['mime'] as String?) ?? 'application/octet-stream',
    size: (j['size'] as num?)?.toInt() ?? 0,
    data: j['data'] as String?,
    addedAt: _ts(j['addedAt']),
  );
}

/// Campos do contrato usados nos cálculos (para apontar o que falta).
enum DebtField {
  outstanding('Saldo devedor atual'),
  rate('Taxa de juros'),
  remainingMonths('Parcelas restantes'),
  system('Sistema de amortização (Price ou SAC)'),
  payment('Valor da parcela atual'),
  nextDueDate('Vencimento da próxima parcela');

  final String label;
  const DebtField(this.label);
}

/// Empréstimo ou financiamento.
class DebtContract {
  final String id;
  final String name;
  final String lender;
  final DebtKind kind;

  /// `null` = não informado.
  final AmortizationSystem? system;

  /// Taxa de juros efetiva ao mês (fração). `null` = não informada.
  final double? monthlyRate;

  /// Dados originais (informativos).
  final Money? originalPrincipal;
  final DateTime? contractDate;
  final int? termMonths;

  /// Situação atual: saldo devedor na [balanceDate], parcelas que faltam e
  /// próxima parcela.
  final Money? outstanding;
  final DateTime? balanceDate;
  final int? remainingMonths;
  final DateTime? nextDueDate;

  /// Parcela atual sem os encargos mensais.
  final Money? currentPayment;

  final List<DebtFee> fees;
  final DebtIndex index;

  /// Correção estimada do indexador ao mês (fração).
  final double indexMonthlyRate;

  /// Opções que o contrato permite.
  final OptionSupport lastInstallments;
  final OptionSupport reduceTerm;
  final OptionSupport reducePayment;
  final OptionSupport payoff;

  /// Tarifa sobre o valor antecipado (fração). Zero na maioria dos
  /// contratos de pessoa física.
  final double prepaymentFeeRate;

  /// Conta que paga as parcelas e categoria das parcelas geradas.
  final String? accountId;
  final String? categoryId;

  final DebtInstallments installments;

  /// Compromisso já lançado que representa as parcelas
  /// ([DebtInstallments.linked]).
  final String? linkedRuleId;
  final String? linkedGroupId;

  /// Pagamentos já registrados que pertencem ao contrato.
  final List<String> linkedTxIds;

  final List<LenderQuote> quotes;
  final List<DebtAttachment> attachments;

  /// Campos preenchidos a partir do anexo (revisados pelo usuário).
  final List<String> extractedFields;
  final String notes;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  DebtContract({
    required this.id,
    required this.name,
    this.lender = '',
    this.kind = DebtKind.personalLoan,
    this.system,
    this.monthlyRate,
    this.originalPrincipal,
    this.contractDate,
    this.termMonths,
    this.outstanding,
    this.balanceDate,
    this.remainingMonths,
    this.nextDueDate,
    this.currentPayment,
    this.fees = const [],
    this.index = DebtIndex.none,
    this.indexMonthlyRate = 0,
    this.lastInstallments = OptionSupport.unknown,
    this.reduceTerm = OptionSupport.unknown,
    this.reducePayment = OptionSupport.unknown,
    this.payoff = OptionSupport.unknown,
    this.prepaymentFeeRate = 0,
    this.accountId,
    this.categoryId,
    this.installments = DebtInstallments.none,
    this.linkedRuleId,
    this.linkedGroupId,
    this.linkedTxIds = const [],
    this.quotes = const [],
    this.attachments = const [],
    this.extractedFields = const [],
    this.notes = '',
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Encargos mensais somados.
  Money get monthlyFees => fees.fold(Money.zero, (a, f) => a + f.monthly);

  /// Parcela total (parcela + encargos), quando informada.
  Money? get currentTotalPayment =>
      currentPayment == null ? null : currentPayment! + monthlyFees;

  OptionSupport supportOf(PrepayOption o) => switch (o) {
    PrepayOption.lastInstallments => lastInstallments,
    PrepayOption.reduceTerm => reduceTerm,
    PrepayOption.reducePayment => reducePayment,
    PrepayOption.payoff => payoff,
  };

  /// Cotação do credor mais recente para a opção, válida em [day].
  LenderQuote? quoteFor(PrepayOption o, DateTime day) {
    final kind = switch (o) {
      PrepayOption.payoff => QuoteKind.payoff,
      PrepayOption.lastInstallments => QuoteKind.lastInstallments,
      _ => QuoteKind.prepayment,
    };
    final list =
        quotes.where((q) => q.kind == kind && q.isValidOn(day)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return list.firstOrNull;
  }

  DebtContract copyWith({
    String? name,
    String? lender,
    DebtKind? kind,
    Object? system = _unset,
    Object? monthlyRate = _unset,
    Object? originalPrincipal = _unset,
    Object? contractDate = _unset,
    Object? termMonths = _unset,
    Object? outstanding = _unset,
    Object? balanceDate = _unset,
    Object? remainingMonths = _unset,
    Object? nextDueDate = _unset,
    Object? currentPayment = _unset,
    List<DebtFee>? fees,
    DebtIndex? index,
    double? indexMonthlyRate,
    OptionSupport? lastInstallments,
    OptionSupport? reduceTerm,
    OptionSupport? reducePayment,
    OptionSupport? payoff,
    double? prepaymentFeeRate,
    Object? accountId = _unset,
    Object? categoryId = _unset,
    DebtInstallments? installments,
    Object? linkedRuleId = _unset,
    Object? linkedGroupId = _unset,
    List<String>? linkedTxIds,
    List<LenderQuote>? quotes,
    List<DebtAttachment>? attachments,
    List<String>? extractedFields,
    String? notes,
    bool? archived,
  }) => DebtContract(
    id: id,
    name: name ?? this.name,
    lender: lender ?? this.lender,
    kind: kind ?? this.kind,
    system: system == _unset ? this.system : system as AmortizationSystem?,
    monthlyRate: monthlyRate == _unset
        ? this.monthlyRate
        : monthlyRate as double?,
    originalPrincipal: originalPrincipal == _unset
        ? this.originalPrincipal
        : originalPrincipal as Money?,
    contractDate: contractDate == _unset
        ? this.contractDate
        : contractDate as DateTime?,
    termMonths: termMonths == _unset ? this.termMonths : termMonths as int?,
    outstanding: outstanding == _unset
        ? this.outstanding
        : outstanding as Money?,
    balanceDate: balanceDate == _unset
        ? this.balanceDate
        : balanceDate as DateTime?,
    remainingMonths: remainingMonths == _unset
        ? this.remainingMonths
        : remainingMonths as int?,
    nextDueDate: nextDueDate == _unset
        ? this.nextDueDate
        : nextDueDate as DateTime?,
    currentPayment: currentPayment == _unset
        ? this.currentPayment
        : currentPayment as Money?,
    fees: fees ?? this.fees,
    index: index ?? this.index,
    indexMonthlyRate: indexMonthlyRate ?? this.indexMonthlyRate,
    lastInstallments: lastInstallments ?? this.lastInstallments,
    reduceTerm: reduceTerm ?? this.reduceTerm,
    reducePayment: reducePayment ?? this.reducePayment,
    payoff: payoff ?? this.payoff,
    prepaymentFeeRate: prepaymentFeeRate ?? this.prepaymentFeeRate,
    accountId: accountId == _unset ? this.accountId : accountId as String?,
    categoryId: categoryId == _unset ? this.categoryId : categoryId as String?,
    installments: installments ?? this.installments,
    linkedRuleId: linkedRuleId == _unset
        ? this.linkedRuleId
        : linkedRuleId as String?,
    linkedGroupId: linkedGroupId == _unset
        ? this.linkedGroupId
        : linkedGroupId as String?,
    linkedTxIds: linkedTxIds ?? this.linkedTxIds,
    quotes: quotes ?? this.quotes,
    attachments: attachments ?? this.attachments,
    extractedFields: extractedFields ?? this.extractedFields,
    notes: notes ?? this.notes,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'lender': lender,
    'kind': kind.name,
    'system': system?.name,
    'monthlyRate': monthlyRate,
    'originalPrincipal': originalPrincipal?.cents,
    'contractDate': _d(contractDate),
    'termMonths': termMonths,
    'outstanding': outstanding?.cents,
    'balanceDate': _d(balanceDate),
    'remainingMonths': remainingMonths,
    'nextDueDate': _d(nextDueDate),
    'currentPayment': currentPayment?.cents,
    'fees': [for (final f in fees) f.toJson()],
    'index': index.name,
    'indexMonthlyRate': indexMonthlyRate,
    'lastInstallments': lastInstallments.name,
    'reduceTerm': reduceTerm.name,
    'reducePayment': reducePayment.name,
    'payoff': payoff.name,
    'prepaymentFeeRate': prepaymentFeeRate,
    'accountId': accountId,
    'categoryId': categoryId,
    'installments': installments.name,
    'linkedRuleId': linkedRuleId,
    'linkedGroupId': linkedGroupId,
    'linkedTxIds': linkedTxIds,
    'quotes': [for (final q in quotes) q.toJson()],
    'attachments': [for (final a in attachments) a.toJson()],
    'extractedFields': extractedFields,
    'notes': notes,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory DebtContract.fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> list(String k) => [
      for (final x in (j[k] as List?) ?? const [])
        Map<String, Object?>.from(x as Map),
    ];
    OptionSupport opt(String k) =>
        _enum(OptionSupport.values, j[k], OptionSupport.unknown);
    return DebtContract(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Contrato',
      lender: (j['lender'] as String?) ?? '',
      kind: _enum(DebtKind.values, j['kind'], DebtKind.other),
      system: AmortizationSystem.values
          .where((s) => s.name == j['system'])
          .firstOrNull,
      monthlyRate: _dbl(j['monthlyRate']),
      originalPrincipal: _m(j['originalPrincipal']),
      contractDate: _pd(j['contractDate']),
      termMonths: (j['termMonths'] as num?)?.toInt(),
      outstanding: _m(j['outstanding']),
      balanceDate: _pd(j['balanceDate']),
      remainingMonths: (j['remainingMonths'] as num?)?.toInt(),
      nextDueDate: _pd(j['nextDueDate']),
      currentPayment: _m(j['currentPayment']),
      fees: [for (final f in list('fees')) DebtFee.fromJson(f)],
      index: _enum(DebtIndex.values, j['index'], DebtIndex.none),
      indexMonthlyRate: _dbl(j['indexMonthlyRate']) ?? 0,
      lastInstallments: opt('lastInstallments'),
      reduceTerm: opt('reduceTerm'),
      reducePayment: opt('reducePayment'),
      payoff: opt('payoff'),
      prepaymentFeeRate: _dbl(j['prepaymentFeeRate']) ?? 0,
      accountId: j['accountId'] as String?,
      categoryId: j['categoryId'] as String?,
      installments: _enum(
        DebtInstallments.values,
        j['installments'],
        DebtInstallments.none,
      ),
      linkedRuleId: j['linkedRuleId'] as String?,
      linkedGroupId: j['linkedGroupId'] as String?,
      linkedTxIds: [
        for (final x in (j['linkedTxIds'] as List?) ?? const []) x as String,
      ],
      quotes: [for (final q in list('quotes')) LenderQuote.fromJson(q)],
      attachments: [
        for (final a in list('attachments')) DebtAttachment.fromJson(a),
      ],
      extractedFields: [
        for (final x in (j['extractedFields'] as List?) ?? const [])
          x as String,
      ],
      notes: (j['notes'] as String?) ?? '',
      archived: (j['archived'] as bool?) ?? false,
      createdAt: _ts(j['createdAt']),
      updatedAt: _ts(j['updatedAt']),
    );
  }
}

enum ScenarioKind {
  newFinancing('Novo financiamento'),
  prepayment('Antecipação ou quitação'),
  comparison('Comparação entre dívidas');

  final String label;
  const ScenarioKind(this.label);
}

/// Simulação salva. Guarda os dados de entrada e um resumo do resultado
/// (congelado na data do cálculo) para comparar depois. [appliedAt] marca
/// quando o usuário confirmou levar a opção para o planejamento.
class DebtScenario {
  final String id;
  final String name;
  final ScenarioKind kind;
  final DateTime calculatedAt;

  /// Entradas (ex.: {debtId, option, amount} ou {principal, rate, months}).
  final Map<String, Object?> inputs;

  /// Linhas de resumo, já com os valores em centavos
  /// (ex.: [{label, outflow, totalSaved, monthlyRelief, ...}]).
  final List<Map<String, Object?>> summary;
  final String notes;
  final DateTime? appliedAt;
  final DateTime createdAt;

  DebtScenario({
    required this.id,
    required this.name,
    required this.kind,
    required this.calculatedAt,
    this.inputs = const {},
    this.summary = const [],
    this.notes = '',
    this.appliedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  DebtScenario copyWith({String? name, String? notes, DateTime? appliedAt}) =>
      DebtScenario(
        id: id,
        name: name ?? this.name,
        kind: kind,
        calculatedAt: calculatedAt,
        inputs: inputs,
        summary: summary,
        notes: notes ?? this.notes,
        appliedAt: appliedAt ?? this.appliedAt,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'calculatedAt': calculatedAt.toIso8601String(),
    'inputs': inputs,
    'summary': summary,
    'notes': notes,
    'appliedAt': appliedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory DebtScenario.fromJson(Map<String, Object?> j) => DebtScenario(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Simulação',
    kind: _enum(ScenarioKind.values, j['kind'], ScenarioKind.prepayment),
    calculatedAt: _ts(j['calculatedAt']),
    inputs: j['inputs'] is Map
        ? Map<String, Object?>.from(j['inputs'] as Map)
        : const {},
    summary: [
      for (final x in (j['summary'] as List?) ?? const [])
        Map<String, Object?>.from(x as Map),
    ],
    notes: (j['notes'] as String?) ?? '',
    appliedAt: j['appliedAt'] == null
        ? null
        : DateTime.parse(j['appliedAt'] as String),
    createdAt: _ts(j['createdAt']),
  );
}
