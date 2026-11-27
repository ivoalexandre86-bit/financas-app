import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../domain/engine/debt_engine.dart';
import '../../../domain/models/debt.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// "1,5" → 0.015 (porcentagem digitada no padrão brasileiro).
double? parsePercent(String s) {
  final t = s.replaceAll('%', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0 || v > 1000) return null;
  return v / 100;
}

/// 0.015 → "1,5" (para preencher campos).
String percentText(double? f, {int digits = 4}) {
  if (f == null) return '';
  var s = (f * 100).toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

/// Taxa mensal/anual escolhida no formulário.
enum RateBasis {
  monthly('% ao mês'),
  annual('% ao ano');

  final String label;
  const RateBasis(this.label);
}

IconData debtIcon(DebtKind k) => switch (k) {
  DebtKind.personalLoan => Icons.request_quote_outlined,
  DebtKind.payroll => Icons.badge_outlined,
  DebtKind.vehicle => Icons.directions_car_outlined,
  DebtKind.realEstate => Icons.home_outlined,
  DebtKind.student => Icons.school_outlined,
  DebtKind.other => Icons.money_off_outlined,
};

/// Etiqueta "Cotação do credor" / "Estimativa do app".
class SourcePill extends StatelessWidget {
  final EstimateSource source;
  const SourcePill(this.source, {super.key});
  @override
  Widget build(BuildContext context) => Pill(
    source.label,
    color: source == EstimateSource.lender
        ? context.fin.positive
        : context.colors.primary,
    icon: source == EstimateSource.lender
        ? Icons.verified_outlined
        : Icons.calculate_outlined,
  );
}

/// Cronograma mês a mês (rolagem horizontal no celular).
class ScheduleTable extends StatelessWidget {
  final DebtSchedule schedule;
  final double height;
  const ScheduleTable(this.schedule, {super.key, this.height = 360});

  static const _w = [44.0, 92.0, 104.0, 100.0, 108.0, 92.0, 116.0];

  @override
  Widget build(BuildContext context) {
    if (schedule.isEmpty) {
      return const Text('Sem parcelas restantes.');
    }
    final fees = schedule.totalFees.isPositive;
    final corr = schedule.totalCorrection.isPositive;
    final known = schedule.interestKnown;
    final heads = [
      'Nº',
      'Vencimento',
      'Parcela',
      if (known) 'Juros',
      if (known) 'Amortização',
      if (corr) 'Correção',
      if (fees) 'Encargos',
      if (fees) 'Total',
      if (known) 'Saldo devedor',
    ];
    double w(String h) => switch (h) {
      'Nº' => _w[0],
      'Vencimento' => _w[1],
      'Amortização' || 'Saldo devedor' => _w[4] + 8,
      _ => _w[2],
    };
    final width = heads.fold(0.0, (a, h) => a + w(h)) + 16;
    final small = context.text.bodySmall;
    Widget cell(String h, String v, {bool bold = false}) => SizedBox(
      width: w(h),
      child: Text(
        v,
        textAlign: h == 'Nº' || h == 'Vencimento'
            ? TextAlign.left
            : TextAlign.right,
        style: (bold ? small?.copyWith(fontWeight: FontWeight.w600) : small)
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
    List<String> values(DebtRow r) => [
      '${r.number}',
      Dates.format(r.dueDate),
      r.payment.formatPlain(),
      if (known) r.interest.formatPlain(),
      if (known) r.amortization.formatPlain(),
      if (corr) r.correction.formatPlain(),
      if (fees) r.fees.formatPlain(),
      if (fees) r.total.formatPlain(),
      if (known) r.balance.formatPlain(),
    ];
    final totals = [
      'Total',
      '',
      schedule.totalPayments.formatPlain(),
      if (known) schedule.totalInterest.formatPlain(),
      if (known) schedule.totalAmortization.formatPlain(),
      if (corr) schedule.totalCorrection.formatPlain(),
      if (fees) schedule.totalFees.formatPlain(),
      if (fees) schedule.totalPaid.formatPlain(),
      if (known) '',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [for (final h in heads) cell(h, h, bold: true)],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: schedule.rows.length,
                itemExtent: 28,
                itemBuilder: (_, i) {
                  final v = values(schedule.rows[i]);
                  return Container(
                    color: i.isOdd
                        ? context.colors.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          )
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        for (var k = 0; k < heads.length; k++)
                          cell(heads[k], v[k]),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (var k = 0; k < heads.length; k++)
                    cell(heads[k], totals[k], bold: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista de premissas e avisos do cálculo.
class AssumptionsList extends StatelessWidget {
  final DateTime calculatedAt;
  final List<String> assumptions;
  final List<String> warnings;
  const AssumptionsList({
    super.key,
    required this.calculatedAt,
    this.assumptions = const [],
    this.warnings = const [],
  });

  @override
  Widget build(BuildContext context) {
    final small = context.text.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, size: 16, color: context.fin.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(w, style: small)),
              ],
            ),
          ),
        Text(
          'Calculado em ${Dates.format(calculatedAt)}. Premissas:',
          style: small?.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final a in assumptions)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '• $a',
              style: small?.copyWith(color: context.fin.subtle),
            ),
          ),
      ],
    );
  }
}

/// Resultado de uma opção de antecipação/quitação.
class PrepayResultView extends StatelessWidget {
  final PrepayResult r;
  final Money? reserve;
  final CashImpact? impact;
  const PrepayResultView(this.r, {super.key, this.reserve, this.impact});

  @override
  Widget build(BuildContext context) {
    String months(int n) => n == 0 ? 'quitado' : '$n parcelas';
    final saved = r.totalSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            SourcePill(r.source),
            if (r.installmentsCovered > 0)
              Pill(
                '${r.installmentsCovered} parcelas antecipadas',
                color: context.colors.secondary,
              ),
          ],
        ),
        const SizedBox(height: 8),
        InfoRow('Sai do caixa agora', MoneyText(r.outflow)),
        if (r.fee.isPositive)
          InfoRow('  inclui tarifa de antecipação', MoneyText(r.fee)),
        InfoRow(
          saved.isNegative ? 'Custo a mais estimado' : 'Economia estimada',
          MoneyText(
            saved.abs(),
            color: saved.isNegative
                ? context.fin.negative
                : context.fin.positive,
          ),
        ),
        if (r.interestSaved case final i?)
          InfoRow('Juros a menos', MoneyText(i)),
        InfoRow(
          'Próxima parcela',
          Text(
            '${r.paymentBefore.format()} → ${r.paymentAfter.format()}',
            textAlign: TextAlign.right,
          ),
        ),
        InfoRow(
          'Redução da parcela',
          MoneyText(r.monthlyRelief, color: context.fin.positive),
        ),
        InfoRow(
          'Prazo',
          Text(
            '${months(r.monthsBefore)} → ${months(r.monthsAfter)}',
            textAlign: TextAlign.right,
          ),
        ),
        if (r.endBefore != null)
          InfoRow(
            'Última parcela',
            Text(
              '${Dates.format(r.endBefore!)} → '
              '${r.endAfter == null ? 'agora' : Dates.format(r.endAfter!)}',
              textAlign: TextAlign.right,
            ),
          ),
        if (impact != null) ...[
          const SizedBox(height: 8),
          CashImpactView(impact!),
        ],
        const SizedBox(height: 8),
        AssumptionsList(
          calculatedAt: r.calculatedAt,
          assumptions: r.assumptions,
          warnings: r.warnings,
        ),
      ],
    );
  }
}

/// Caixa projetado antes/depois, mês a mês, contra a reserva mínima.
class CashImpactView extends StatelessWidget {
  final CashImpact impact;
  final int months;
  const CashImpactView(this.impact, {super.key, this.months = 12});

  @override
  Widget build(BuildContext context) {
    if (impact.points.isEmpty) return const SizedBox.shrink();
    final small = context.text.bodySmall;
    final below = impact.firstBelowReserve;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Caixa projetado (saldo acumulado)',
          style: context.text.titleSmall,
        ),
        const SizedBox(height: 4),
        if (impact.reserve.isPositive)
          Text(
            below == null
                ? 'Fica acima da reserva mínima de '
                      '${impact.reserve.format()} em todos os meses.'
                : 'Fica abaixo da reserva mínima de '
                      '${impact.reserve.format()} a partir de '
                      '${below.shortLabel} (menor saldo '
                      '${impact.minAfter.format()}).',
            style: small?.copyWith(
              color: below == null
                  ? context.fin.positive
                  : context.fin.negative,
            ),
          ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columnSpacing: 16,
            horizontalMargin: 4,
            columns: const [
              DataColumn(label: Text('Mês')),
              DataColumn(label: Text('Antes'), numeric: true),
              DataColumn(label: Text('Depois'), numeric: true),
              DataColumn(label: Text('Diferença'), numeric: true),
            ],
            rows: [
              for (final p in impact.points.take(months))
                DataRow(
                  cells: [
                    DataCell(Text(p.month.shortLabel, style: small)),
                    DataCell(Text(p.before.format(), style: small)),
                    DataCell(
                      Text(
                        p.after.format(),
                        style: small?.copyWith(
                          color: p.after < impact.reserve
                              ? context.fin.negative
                              : null,
                        ),
                      ),
                    ),
                    DataCell(MoneyText(p.delta, style: small, colorize: true)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Campos que faltam para calcular, com atalhos.
class MissingFieldsCard extends StatelessWidget {
  final List<DebtField> missing;
  final String? blocked;
  final VoidCallback? onEdit;
  final VoidCallback? onQuote;
  const MissingFieldsCard({
    super.key,
    this.missing = const [],
    this.blocked,
    this.onEdit,
    this.onQuote,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (blocked != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block, size: 16, color: context.fin.warning),
            const SizedBox(width: 6),
            Expanded(child: Text(blocked!)),
          ],
        ),
      if (missing.isNotEmpty) ...[
        Text(
          'Sem estimativa: faltam dados do contrato.',
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final f in missing) Text('• ${f.label}'),
        const SizedBox(height: 4),
        Text(
          'Complete o contrato ou informe a cotação do credor (boleto de '
          'quitação ou proposta de amortização).',
          style: context.text.bodySmall?.copyWith(color: context.fin.subtle),
        ),
      ],
      if (missing.isNotEmpty && (onEdit != null || onQuote != null))
        Wrap(
          spacing: 8,
          children: [
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Completar dados'),
              ),
            if (onQuote != null)
              TextButton.icon(
                onPressed: onQuote,
                icon: const Icon(Icons.request_quote_outlined),
                label: const Text('Informar cotação'),
              ),
          ],
        ),
    ],
  );
}
