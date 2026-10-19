import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/money.dart';
import '../../../domain/engine/calculators.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// Calculadoras: juros compostos, financiamento, quanto guardar por mês e
/// amortizar dívida × investir. Tudo é recalculado enquanto se digita.
class CalculatorsScreen extends StatelessWidget {
  const CalculatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calculadoras'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Juros compostos'),
              Tab(text: 'Financiamento'),
              Tab(text: 'Quanto guardar'),
              Tab(text: 'Quitar ou investir'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CompoundCalculator(),
            LoanCalculator(),
            SavingsCalculator(),
            PrepayCalculator(),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Campos compartilhados

/// Interpreta "1,5" ou "1.5" como 1.5. `null` se inválido.
double? parseDecimal(String s) {
  var t = s.replaceAll('%', '').replaceAll(' ', '').trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// Taxa em % com a escolha ao mês / ao ano. [monthly] devolve a taxa mensal
/// como fração.
class _Rate {
  final text = TextEditingController();
  bool annual = false;
  double? get monthly {
    final p = parseDecimal(text.text);
    if (p == null) return null;
    return annual ? monthlyFromAnnual(p / 100) : p / 100;
  }
}

/// Prazo em meses ou anos.
class _Term {
  final text = TextEditingController();
  bool years = false;
  int? get months {
    final n = int.tryParse(text.text.trim());
    if (n == null || n <= 0) return null;
    return years ? n * 12 : n;
  }
}

class _RateField extends StatelessWidget {
  final _Rate rate;
  final String label;
  final VoidCallback onChanged;
  final Key? fieldKey;
  const _RateField(
    this.rate, {
    required this.onChanged,
    this.label = 'Taxa de juros',
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          key: fieldKey,
          controller: rate.text,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(labelText: label, suffixText: '%'),
          onChanged: (_) => onChanged(),
        ),
      ),
      const SizedBox(width: 8),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('a.m.')),
          ButtonSegment(value: true, label: Text('a.a.')),
        ],
        selected: {rate.annual},
        onSelectionChanged: (s) {
          rate.annual = s.first;
          onChanged();
        },
      ),
    ],
  );
}

class _TermField extends StatelessWidget {
  final _Term term;
  final VoidCallback onChanged;
  final Key? fieldKey;
  const _TermField(this.term, {required this.onChanged, this.fieldKey});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          key: fieldKey,
          controller: term.text,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Prazo'),
          onChanged: (_) => onChanged(),
        ),
      ),
      const SizedBox(width: 8),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('meses')),
          ButtonSegment(value: true, label: Text('anos')),
        ],
        selected: {term.years},
        onSelectionChanged: (s) {
          term.years = s.first;
          onChanged();
        },
      ),
    ],
  );
}

Money _money(TextEditingController c) => Money.tryEval(c.text) ?? Money.zero;

class _Line extends StatelessWidget {
  final String label;
  final Money value;
  final bool strong;
  final bool colorize;
  const _Line(
    this.label,
    this.value, {
    this.strong = false,
    this.colorize = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : context.text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          MoneyText(value, style: style, colorize: colorize),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.text.bodyMedium?.copyWith(color: context.fin.subtle),
  );
}

/// Tabela simples com rolagem horizontal; a primeira coluna à esquerda.
class _Table extends StatelessWidget {
  final List<String> header;
  final List<List<String>> rows;
  const _Table({required this.header, required this.rows});

  @override
  Widget build(BuildContext context) {
    final head = context.text.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: context.fin.subtle,
    );
    Widget cell(String s, {TextStyle? style, bool left = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        s,
        style: style ?? context.text.bodySmall,
        textAlign: left ? TextAlign.left : TextAlign.right,
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(color: context.fin.gridLine),
        ),
        children: [
          TableRow(
            children: [
              for (final (i, h) in header.indexed)
                cell(h, style: head, left: i == 0),
            ],
          ),
          for (final r in rows)
            TableRow(
              children: [for (final (i, v) in r.indexed) cell(v, left: i == 0)],
            ),
        ],
      ),
    );
  }
}

abstract class _CalcState<T extends StatefulWidget> extends State<T> {
  void refresh() => setState(() {});

  Widget page(List<Widget> inputs, Widget result) => LayoutBuilder(
    builder: (context, c) {
      final form = SectionCard(
        title: 'Dados',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, w) in inputs.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              w,
            ],
          ],
        ),
      );
      if (c.maxWidth >= 900) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 380, child: form),
              const SizedBox(width: 16),
              Expanded(child: result),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [form, const SizedBox(height: 12), result],
      );
    },
  );
}

// -----------------------------------------------------------------------------
// Juros compostos

class CompoundCalculator extends StatefulWidget {
  const CompoundCalculator({super.key});
  @override
  State<CompoundCalculator> createState() => _CompoundCalculatorState();
}

class _CompoundCalculatorState extends _CalcState<CompoundCalculator> {
  final initial = TextEditingController();
  final monthly = TextEditingController();
  final rate = _Rate();
  final term = _Term()..years = true;

  @override
  Widget build(BuildContext context) {
    final i = rate.monthly, n = term.months;
    CompoundResult? r;
    if (i != null && n != null && n <= 1200) {
      r = compoundInterest(
        initial: _money(initial),
        monthly: _money(monthly),
        rate: i,
        months: n,
      );
    }
    return page(
      [
        MoneyField(
          key: const ValueKey('calc-compound-initial'),
          controller: initial,
          label: 'Aporte inicial',
          allowZero: true,
          onChanged: (_) => refresh(),
        ),
        MoneyField(
          key: const ValueKey('calc-compound-monthly'),
          controller: monthly,
          label: 'Aporte mensal',
          allowZero: true,
          onChanged: (_) => refresh(),
        ),
        _RateField(
          rate,
          onChanged: refresh,
          fieldKey: const ValueKey('calc-compound-rate'),
        ),
        _TermField(
          term,
          onChanged: refresh,
          fieldKey: const ValueKey('calc-compound-term'),
        ),
      ],
      SectionCard(
        title: 'Resultado',
        child: r == null
            ? const _Hint('Informe a taxa e o prazo para ver o resultado.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Line('Montante final', r.total, strong: true),
                  _Line('Total investido', r.invested),
                  _Line('Juros ganhos', r.interest, colorize: true),
                  const SizedBox(height: 12),
                  _Table(
                    header: const ['Ano', 'Investido', 'Juros', 'Saldo'],
                    rows: [
                      for (final y in r.years)
                        [
                          '${y.year}',
                          y.invested.format(),
                          y.interest.format(),
                          y.balance.format(),
                        ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Financiamento

class LoanCalculator extends StatefulWidget {
  const LoanCalculator({super.key});
  @override
  State<LoanCalculator> createState() => _LoanCalculatorState();
}

class _LoanCalculatorState extends _CalcState<LoanCalculator> {
  final amount = TextEditingController();
  final rate = _Rate();
  final term = _Term();
  var system = AmortizationSystem.price;

  /// Linhas exibidas da tabela de amortização.
  static const shownRows = 12;

  @override
  Widget build(BuildContext context) {
    final i = rate.monthly, n = term.months, pv = _money(amount);
    LoanResult? price, sac;
    if (i != null && n != null && n <= 1200 && pv.isPositive) {
      price = loan(principal: pv, rate: i, months: n);
      sac = loan(
        principal: pv,
        rate: i,
        months: n,
        system: AmortizationSystem.sac,
      );
    }
    final r = system == AmortizationSystem.price ? price : sac;
    return page(
      [
        MoneyField(
          key: const ValueKey('calc-loan-amount'),
          controller: amount,
          label: 'Valor financiado',
          onChanged: (_) => refresh(),
        ),
        _RateField(
          rate,
          onChanged: refresh,
          fieldKey: const ValueKey('calc-loan-rate'),
        ),
        _TermField(
          term,
          onChanged: refresh,
          fieldKey: const ValueKey('calc-loan-term'),
        ),
        SegmentedButton<AmortizationSystem>(
          segments: const [
            ButtonSegment(
              value: AmortizationSystem.price,
              label: Text('Price'),
            ),
            ButtonSegment(value: AmortizationSystem.sac, label: Text('SAC')),
          ],
          selected: {system},
          onSelectionChanged: (s) => setState(() => system = s.first),
        ),
      ],
      SectionCard(
        title: 'Resultado · ${system.label}',
        child: r == null
            ? const _Hint(
                'Informe o valor, a taxa e o prazo para ver as parcelas.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Line('Primeira parcela', r.firstPayment, strong: true),
                  _Line('Última parcela', r.lastPayment),
                  _Line('Total pago', r.totalPaid),
                  _Line('Total de juros', r.totalInterest),
                  if (price != null && sac != null) ...[
                    const SizedBox(height: 8),
                    _Hint(
                      'Juros: Price ${price.totalInterest.format()} · SAC '
                      '${sac.totalInterest.format()}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _Table(
                    header: const [
                      'Nº',
                      'Parcela',
                      'Juros',
                      'Amortização',
                      'Saldo',
                    ],
                    rows: [
                      for (final row in r.rows.take(shownRows))
                        [
                          '${row.number}',
                          row.payment.format(),
                          row.interest.format(),
                          row.amortization.format(),
                          row.balance.format(),
                        ],
                    ],
                  ),
                  if (r.rows.length > shownRows)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Hint(
                        'Mostrando as $shownRows primeiras de '
                        '${r.rows.length} parcelas.',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quanto guardar por mês

class SavingsCalculator extends StatefulWidget {
  const SavingsCalculator({super.key});
  @override
  State<SavingsCalculator> createState() => _SavingsCalculatorState();
}

class _SavingsCalculatorState extends _CalcState<SavingsCalculator> {
  final target = TextEditingController();
  final initial = TextEditingController();
  final rate = _Rate();
  final term = _Term();

  @override
  Widget build(BuildContext context) {
    final i = rate.monthly ?? 0, n = term.months, goal = _money(target);
    Money? pmt;
    CompoundResult? check;
    if (n != null && n <= 1200 && goal.isPositive) {
      pmt = monthlySavingsFor(
        target: goal,
        rate: i,
        months: n,
        initial: _money(initial),
      );
      check = compoundInterest(
        initial: _money(initial),
        monthly: pmt,
        rate: i,
        months: n,
      );
    }
    return page(
      [
        MoneyField(
          key: const ValueKey('calc-savings-target'),
          controller: target,
          label: 'Quanto quero ter',
          onChanged: (_) => refresh(),
        ),
        MoneyField(
          key: const ValueKey('calc-savings-initial'),
          controller: initial,
          label: 'Já tenho (opcional)',
          allowZero: true,
          onChanged: (_) => refresh(),
        ),
        _TermField(
          term,
          onChanged: refresh,
          fieldKey: const ValueKey('calc-savings-term'),
        ),
        _RateField(
          rate,
          label: 'Rendimento (opcional)',
          onChanged: refresh,
          fieldKey: const ValueKey('calc-savings-rate'),
        ),
      ],
      SectionCard(
        title: 'Resultado',
        child: pmt == null || check == null
            ? const _Hint('Informe a meta e o prazo.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Line('Guardar por mês', pmt, strong: true),
                  _Line('Total que você deposita', check.invested),
                  _Line('Rendimento no período', check.interest),
                  _Line('Valor ao final', check.total),
                ],
              ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quitar dívida antecipado × investir

class PrepayCalculator extends StatefulWidget {
  const PrepayCalculator({super.key});
  @override
  State<PrepayCalculator> createState() => _PrepayCalculatorState();
}

class _PrepayCalculatorState extends _CalcState<PrepayCalculator> {
  final debt = TextEditingController();
  final extra = TextEditingController();
  final debtRate = _Rate();
  final investRate = _Rate();
  final term = _Term();

  @override
  Widget build(BuildContext context) {
    final di = debtRate.monthly, ii = investRate.monthly, n = term.months;
    final d = _money(debt), x = _money(extra);
    PrepayComparison? r;
    if (di != null &&
        ii != null &&
        n != null &&
        n <= 1200 &&
        d.isPositive &&
        x.isPositive) {
      r = prepayVsInvest(
        debt: d,
        debtRate: di,
        months: n,
        extra: x,
        investRate: ii,
      );
    }
    return page(
      [
        MoneyField(
          key: const ValueKey('calc-prepay-debt'),
          controller: debt,
          label: 'Saldo da dívida',
          onChanged: (_) => refresh(),
        ),
        _RateField(
          debtRate,
          label: 'Juros da dívida',
          onChanged: refresh,
          fieldKey: const ValueKey('calc-prepay-debt-rate'),
        ),
        _TermField(
          term,
          onChanged: refresh,
          fieldKey: const ValueKey('calc-prepay-term'),
        ),
        MoneyField(
          key: const ValueKey('calc-prepay-extra'),
          controller: extra,
          label: 'Dinheiro disponível',
          onChanged: (_) => refresh(),
        ),
        _RateField(
          investRate,
          label: 'Rendimento do investimento',
          onChanged: refresh,
          fieldKey: const ValueKey('calc-prepay-invest-rate'),
        ),
      ],
      SectionCard(
        title: 'Comparação',
        child: r == null
            ? const _Hint(
                'Informe a dívida (saldo, juros e parcelas restantes), o '
                'dinheiro disponível e quanto ele renderia investido.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    r.prepayWins
                        ? 'Amortizar a dívida compensa mais'
                        : 'Investir compensa mais',
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.fin.positive,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Hint(
                    'Diferença ao final do prazo: ${r.difference.format()}',
                  ),
                  const SizedBox(height: 12),
                  _Line('Parcela atual', r.currentPayment),
                  _Line('Parcela depois de amortizar', r.newPayment),
                  _Line('Juros que deixam de ser pagos', r.interestSaved),
                  const Divider(),
                  _Line(
                    'Amortizando e investindo a economia das parcelas',
                    r.prepayValue,
                  ),
                  _Line('Investindo o dinheiro', r.investValue),
                  const SizedBox(height: 8),
                  const _Hint(
                    'Considera o mesmo prazo nos dois casos (amortização '
                    'que reduz a parcela) e não desconta impostos.',
                  ),
                ],
              ),
      ),
    );
  }
}
