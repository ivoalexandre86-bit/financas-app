import '../../core/dates.dart';
import '../../core/money.dart';

/// Fechamento (ou ajuste manual) do resultado de um mês.
///
/// Enquanto existir, o mês passa a usar [income] e [expenses] no lugar dos
/// valores calculados a partir dos lançamentos: Início, Projeção, gráficos e
/// relatórios mostram esses números, e o saldo acumulado dos meses seguintes
/// parte deles. Lançar, editar ou excluir algo no mês não muda mais o
/// resultado. Excluir o registro (reabrir o mês) reverte tudo para o
/// cálculo automático. Saldos reais das contas não são afetados.
///
/// Ao **fechar** o mês, [income]/[expenses] são uma foto dos valores
/// calculados naquele momento. Ao **ajustar**, são os valores informados
/// pelo usuário. [computedIncome]/[computedExpenses] guardam o que o app
/// calculava quando o registro foi salvo, para mostrar a diferença.
class MonthClosing {
  final YearMonth month;
  final Money income;
  final Money expenses; // positivo
  final Money computedIncome;
  final Money computedExpenses;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  MonthClosing({
    required this.month,
    required this.income,
    required this.expenses,
    required this.computedIncome,
    required this.computedExpenses,
    this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Um registro por mês: o id é a chave do mês ("2026-10").
  String get id => month.key;

  Money get net => income - expenses;
  Money get computedNet => computedIncome - computedExpenses;

  /// Valores diferentes do que o app calculava ao salvar.
  bool get isAdjusted =>
      income != computedIncome || expenses != computedExpenses;

  /// Diferença do resultado em relação ao cálculo automático.
  Money get adjustment => net - computedNet;

  Map<String, Object?> toJson() => {
    'id': id,
    'month': month.key,
    'income': income.cents,
    'expenses': expenses.cents,
    'computedIncome': computedIncome.cents,
    'computedExpenses': computedExpenses.cents,
    if (note != null && note!.isNotEmpty) 'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MonthClosing.fromJson(Map<String, Object?> j) {
    Money m(String k) => Money((j[k] as num?)?.toInt() ?? 0);
    DateTime ts(String k) =>
        j[k] == null ? DateTime.now() : DateTime.parse(j[k] as String);
    final income = m('income');
    final expenses = m('expenses');
    return MonthClosing(
      month: YearMonth.parse((j['month'] ?? j['id']) as String),
      income: income,
      expenses: expenses,
      computedIncome: j.containsKey('computedIncome')
          ? m('computedIncome')
          : income,
      computedExpenses: j.containsKey('computedExpenses')
          ? m('computedExpenses')
          : expenses,
      note: j['note'] as String?,
      createdAt: ts('createdAt'),
      updatedAt: ts('updatedAt'),
    );
  }
}
