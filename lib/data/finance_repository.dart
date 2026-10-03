import 'package:sembast/sembast.dart';

import '../domain/engine/financial_engine.dart';
import '../domain/models/dashboard.dart';
import '../domain/models/entities.dart';
import 'db_factory.dart';

/// Coleções persistidas. Os nomes espelham as tabelas do PostgreSQL
/// (ver `backend/db/migrations`).
enum Coll {
  accounts,
  cards,
  categories,
  projects,
  transactions,
  recurringTransactions,
  installmentGroups,
  invoicePayments,
  openFinanceConnections,
  externalTransactions,
  dashboards,
}

/// Uma operação de escrita (upsert ou delete) para gravação em lote.
class WriteOp {
  final Coll coll;
  final String id;
  final Map<String, Object?>? json; // null = excluir
  const WriteOp.put(this.coll, this.id, Map<String, Object?> this.json);
  const WriteOp.delete(this.coll, this.id) : json = null;
}

/// Contrato de persistência dos dados financeiros de **um** usuário.
///
/// A implementação local ([LocalFinanceRepository]) usa um banco por
/// usuário, garantindo isolamento físico dos dados. Uma implementação REST
/// (fase 3) pode substituí-la sem alterar o restante do app.
abstract class FinanceRepository {
  Future<FinanceData> load();
  Future<List<OpenFinanceConnection>> loadConnections();
  Future<List<ExternalTransaction>> loadExternalTransactions();
  Future<List<Dashboard>> loadDashboards();
  Future<void> write(List<WriteOp> ops);
  Future<void> saveSettings(AppSettings settings);
  Future<void> close();
  Future<void> destroy();
}

class LocalFinanceRepository implements FinanceRepository {
  final String userId;
  Database? _db;
  LocalFinanceRepository(this.userId);

  String get _dbName => 'financas_user_$userId.db';
  final _settings = StoreRef<String, Map<String, Object?>>('settings');

  StoreRef<String, Map<String, Object?>> _store(Coll c) =>
      StoreRef<String, Map<String, Object?>>(c.name);

  Future<Database> get db async => _db ??= await openAppDatabase(_dbName);

  Future<List<T>> _all<T>(Coll c, T Function(Map<String, Object?>) f) async {
    final recs = await _store(c).find(await db);
    return recs.map((r) => f(Map<String, Object?>.from(r.value))).toList();
  }

  @override
  Future<FinanceData> load() async {
    final s = await _settings.record('app').get(await db);
    return FinanceData(
      accounts: await _all(Coll.accounts, Account.fromJson),
      cards: await _all(Coll.cards, CreditCard.fromJson),
      categories: await _all(Coll.categories, FinCategory.fromJson),
      projects: await _all(Coll.projects, Project.fromJson),
      transactions: await _all(Coll.transactions, FinTransaction.fromJson),
      recurringRules: await _all(
        Coll.recurringTransactions,
        RecurringRule.fromJson,
      ),
      installmentGroups: await _all(
        Coll.installmentGroups,
        InstallmentGroup.fromJson,
      ),
      invoicePayments: await _all(
        Coll.invoicePayments,
        InvoicePayment.fromJson,
      ),
      settings: s == null
          ? const AppSettings()
          : AppSettings.fromJson(Map<String, Object?>.from(s)),
    );
  }

  @override
  Future<List<OpenFinanceConnection>> loadConnections() =>
      _all(Coll.openFinanceConnections, OpenFinanceConnection.fromJson);

  @override
  Future<List<ExternalTransaction>> loadExternalTransactions() =>
      _all(Coll.externalTransactions, ExternalTransaction.fromJson);

  @override
  Future<List<Dashboard>> loadDashboards() =>
      _all(Coll.dashboards, Dashboard.fromJson);

  /// Grava todas as operações atomicamente (tudo ou nada).
  @override
  Future<void> write(List<WriteOp> ops) async {
    if (ops.isEmpty) return;
    await (await db).transaction((txn) async {
      for (final op in ops) {
        final rec = _store(op.coll).record(op.id);
        if (op.json == null) {
          await rec.delete(txn);
        } else {
          await rec.put(txn, op.json!);
        }
      }
    });
  }

  @override
  Future<void> saveSettings(AppSettings settings) async =>
      _settings.record('app').put(await db, settings.toJson());

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<void> destroy() async {
    await close();
    await deleteAppDatabase(_dbName);
  }
}
