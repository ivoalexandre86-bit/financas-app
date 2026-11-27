import 'dart:math' as math;

import '../../core/dates.dart';
import '../../core/money.dart';

// FGTS acompanhado à mão. Não há fonte oficial ou autorizada que entregue o
// saldo a um app de finanças pessoais (ver docs/fgts.md): o FGTS não faz
// parte do Open Finance, e a consulta autorizada da Caixa (nov/2026) vale só
// para instituições financeiras habilitadas e não mostra o saldo total.

/// Finalidade de um saque do FGTS (modalidades da Lei 8.036/1990, art. 20).
enum FgtsPurpose {
  birthday('Saque-aniversário'),
  dismissal('Demissão sem justa causa'),
  homePurchase('Compra da casa própria'),
  housingLoan('Amortizar ou quitar financiamento habitacional'),
  retirement('Aposentadoria'),
  illness('Doença grave'),
  disaster('Calamidade ou desastre natural'),
  other('Outro motivo');

  final String label;
  const FgtsPurpose(this.label);

  /// O dinheiro vai direto ao vendedor ou ao banco do financiamento.
  bool get paidToThirdParty => this == homePurchase || this == housingLoan;

  static FgtsPurpose parse(String? s) =>
      values.where((p) => p.name == s).firstOrNull ?? other;
}

/// Dados próprios do FGTS guardados no bem (Asset com kind fgts).
class FgtsDetails {
  /// Depósito mensal esperado (8% do salário bruto, em regra).
  final Money monthlyDeposit;

  /// Rendimento ao ano usado na estimativa (3% a.a. por lei, sem a TR e
  /// sem a distribuição de lucros, que variam).
  final double annualRatePct;

  /// O saldo foi conferido no extrato (app FGTS) ou é uma estimativa.
  final bool balanceConfirmed;

  /// Data do saldo informado.
  final DateTime balanceDate;

  /// Empregador ou vínculo (livre).
  final String employer;

  FgtsDetails({
    this.monthlyDeposit = Money.zero,
    this.annualRatePct = 3.0,
    this.balanceConfirmed = false,
    DateTime? balanceDate,
    this.employer = '',
  }) : balanceDate = Dates.dateOnly(balanceDate ?? DateTime.now());

  /// 8% do salário bruto, arredondado ao centavo.
  static Money depositFromSalary(Money salary) =>
      Money((salary.cents * 8 / 100).round());

  /// Taxa mensal equivalente a [annualRatePct].
  double get monthlyRate => math.pow(1 + annualRatePct / 100, 1 / 12) - 1;

  FgtsDetails copyWith({
    Money? monthlyDeposit,
    double? annualRatePct,
    bool? balanceConfirmed,
    DateTime? balanceDate,
    String? employer,
  }) => FgtsDetails(
    monthlyDeposit: monthlyDeposit ?? this.monthlyDeposit,
    annualRatePct: annualRatePct ?? this.annualRatePct,
    balanceConfirmed: balanceConfirmed ?? this.balanceConfirmed,
    balanceDate: balanceDate ?? this.balanceDate,
    employer: employer ?? this.employer,
  );

  Map<String, Object?> toJson() => {
    'monthlyDeposit': monthlyDeposit.cents,
    'annualRatePct': annualRatePct,
    'balanceConfirmed': balanceConfirmed,
    'balanceDate': Dates.toIso(balanceDate),
    if (employer.isNotEmpty) 'employer': employer,
  };

  factory FgtsDetails.fromJson(Map<String, Object?> j) => FgtsDetails(
    monthlyDeposit: Money((j['monthlyDeposit'] as num?)?.toInt() ?? 0),
    annualRatePct: (j['annualRatePct'] as num?)?.toDouble() ?? 3.0,
    balanceConfirmed: (j['balanceConfirmed'] as bool?) ?? false,
    balanceDate: j['balanceDate'] == null
        ? null
        : Dates.fromIso(j['balanceDate'] as String),
    employer: (j['employer'] as String?) ?? '',
  );
}
