import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../state/finance_controller.dart';

/// Faz uma grade lembrar os últimos filtros usados (mês, cartões, status,
/// ordenação…): a tela reabre como o usuário deixou até ele mudar. Os
/// filtros ficam nas preferências do usuário ([AppSettings.gridFilters]),
/// que sincronizam entre aparelhos.
///
/// Uso: implemente [filterKey], [filtersToJson] e [restoreFilters], e troque
/// `setState` por [setFilters] onde um filtro muda.
mixin RememberedFilters<T extends StatefulWidget> on State<T> {
  /// Identificador único da grade nas preferências (ex.: 'invoices').
  String get filterKey;

  /// Estado atual dos filtros, em JSON.
  Map<String, Object?> filtersToJson();

  /// Aplica filtros salvos. Valores desconhecidos (um cartão excluído, por
  /// exemplo) devem ser ignorados.
  void restoreFilters(Map<String, Object?> saved, FinanceController fc);

  @override
  void initState() {
    super.initState();
    final fc = context.read<FinanceController>();
    final saved = fc.gridFilter(filterKey);
    if (saved == null) return;
    try {
      restoreFilters(saved, fc);
    } catch (_) {
      // Formato antigo ou corrompido: fica com o padrão.
    }
  }

  /// `setState` que também salva os filtros.
  void setFilters(VoidCallback fn) {
    setState(fn);
    rememberFilters();
  }

  void rememberFilters() => context.read<FinanceController>().saveGridFilter(
    filterKey,
    filtersToJson(),
  );
}

/// Conversões JSON usadas pelos filtros salvos.
abstract final class FilterJson {
  static List<String> ids(Iterable<String> v) => v.toList();

  static Set<String> idSet(Object? v, [Iterable<String>? valid]) {
    final ok = valid?.toSet();
    return {
      if (v is List)
        for (final x in v)
          if (x is String && (ok == null || ok.contains(x))) x,
    };
  }

  static List<String> enums(Iterable<Enum> v) => [for (final e in v) e.name];

  static Set<E> enumSet<E extends Enum>(List<E> values, Object? v) => {
    if (v is List)
      for (final x in v) ...values.where((e) => e.name == x),
  };

  static E? enumOrNull<E extends Enum>(List<E> values, Object? v) =>
      values.where((e) => e.name == v).firstOrNull;

  static List<String> months(Iterable<YearMonth> v) => [
    for (final m in v) m.key,
  ];

  static Set<YearMonth> monthSet(Object? v) => {
    if (v is List)
      for (final x in v)
        if (x is String) YearMonth.parse(x),
  };

  static YearMonth? month(Object? v) => v is String ? YearMonth.parse(v) : null;

  /// [v] quando é um id válido; senão nulo.
  static String? id(Object? v, Iterable<String> valid) =>
      v is String && valid.contains(v) ? v : null;
}
