import '../../core/dates.dart';
import '../../domain/models/shared.dart';
import 'api_client.dart';

/// Acesso às despesas compartilhadas no servidor.
abstract class SharedApi {
  Future<SharedState> state();
  Future<List<ShareAuditEntry>> history(String groupId);

  Future<String> createGroup(String name, GroupKind kind);
  Future<void> updateGroup(
    String id, {
    String? name,
    GroupKind? kind,
    bool? archived,
  });

  Future<void> invite(String groupId, String email, ShareRole role);
  Future<void> respondInvite(String groupId, bool accept);
  Future<void> setRole(String groupId, String userId, ShareRole role);
  Future<void> removeMember(String groupId, String userId);

  Future<String> createCategory(
    String groupId,
    String name,
    Map<String, int> p,
  );
  Future<void> updateCategory(
    String id, {
    String? name,
    Map<String, int>? percentages,
    bool? archived,
  });
  Future<int> recalculate(String groupId, {String? categoryId});

  Future<String> upsertExpense(Map<String, Object?> body);
  Future<void> updateExpense(String id, Map<String, Object?> body);
  Future<void> deleteExpense(String id);

  Future<void> addPayment(
    String expenseId, {
    required String userId,
    required int amount,
    required DateTime date,
    String note = '',
  });
  Future<void> deletePayment(String id);
  Future<void> settle(
    String groupId, {
    required String fromUserId,
    required String toUserId,
    required int amount,
    required DateTime date,
    String note = '',
  });
  Future<void> deleteSettlement(String id);

  Future<String> createRecurrence(Map<String, Object?> body);
  Future<void> updateRecurrence(String id, Map<String, Object?> body);
  Future<void> cancelRecurrence(String id, DateTime today);
}

class HttpSharedApi implements SharedApi {
  final ApiClient api;
  HttpSharedApi(this.api);

  @override
  Future<SharedState> state() async =>
      SharedState.fromJson(await api.get('shared/state'));

  @override
  Future<List<ShareAuditEntry>> history(String groupId) async => [
    for (final h
        in (await api.get('shared/groups/$groupId/history'))['history'] as List)
      ShareAuditEntry.fromJson((h as Map).cast()),
  ];

  @override
  Future<String> createGroup(String name, GroupKind kind) async =>
      (await api.post('shared/groups', {'name': name, 'kind': kind.name}))['id']
          as String;

  @override
  Future<void> updateGroup(
    String id, {
    String? name,
    GroupKind? kind,
    bool? archived,
  }) => api.patch('shared/groups/$id', {
    'name': ?name,
    'kind': ?kind?.name,
    'archived': ?archived,
  });

  @override
  Future<void> invite(String groupId, String email, ShareRole role) => api.post(
    'shared/groups/$groupId/members',
    {'email': email, 'role': role.name},
  );

  @override
  Future<void> respondInvite(String groupId, bool accept) =>
      api.post('shared/groups/$groupId/${accept ? 'accept' : 'reject'}');

  @override
  Future<void> setRole(String groupId, String userId, ShareRole role) =>
      api.patch('shared/groups/$groupId/members/$userId', {'role': role.name});

  @override
  Future<void> removeMember(String groupId, String userId) =>
      api.delete('shared/groups/$groupId/members/$userId');

  @override
  Future<String> createCategory(
    String groupId,
    String name,
    Map<String, int> p,
  ) async =>
      (await api.post('shared/groups/$groupId/categories', {
            'name': name,
            'percentages': p,
          }))['id']
          as String;

  @override
  Future<void> updateCategory(
    String id, {
    String? name,
    Map<String, int>? percentages,
    bool? archived,
  }) => api.patch('shared/categories/$id', {
    'name': ?name,
    'percentages': ?percentages,
    'archived': ?archived,
  });

  @override
  Future<int> recalculate(String groupId, {String? categoryId}) async =>
      ((await api.post('shared/groups/$groupId/recalculate', {
                'categoryId': ?categoryId,
              }))['updated']
              as num)
          .toInt();

  @override
  Future<String> upsertExpense(Map<String, Object?> body) async =>
      (await api.post('shared/expenses', body))['id'] as String;

  @override
  Future<void> updateExpense(String id, Map<String, Object?> body) =>
      api.patch('shared/expenses/$id', body);

  @override
  Future<void> deleteExpense(String id) => api.delete('shared/expenses/$id');

  @override
  Future<void> addPayment(
    String expenseId, {
    required String userId,
    required int amount,
    required DateTime date,
    String note = '',
  }) => api.post('shared/expenses/$expenseId/payments', {
    'userId': userId,
    'amount': amount,
    'date': Dates.toIso(date),
    'note': note,
  });

  @override
  Future<void> deletePayment(String id) => api.delete('shared/payments/$id');

  @override
  Future<void> settle(
    String groupId, {
    required String fromUserId,
    required String toUserId,
    required int amount,
    required DateTime date,
    String note = '',
  }) => api.post('shared/groups/$groupId/settlements', {
    'fromUserId': fromUserId,
    'toUserId': toUserId,
    'amount': amount,
    'date': Dates.toIso(date),
    'note': note,
  });

  @override
  Future<void> deleteSettlement(String id) =>
      api.delete('shared/settlements/$id');

  @override
  Future<String> createRecurrence(Map<String, Object?> body) async =>
      (await api.post('shared/recurrences', body))['id'] as String;

  @override
  Future<void> updateRecurrence(String id, Map<String, Object?> body) =>
      api.patch('shared/recurrences/$id', body);

  @override
  Future<void> cancelRecurrence(String id, DateTime today) =>
      api.delete('shared/recurrences/$id?today=${Dates.toIso(today)}');
}
