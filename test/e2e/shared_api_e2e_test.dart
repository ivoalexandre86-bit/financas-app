// Contra uma API real: SHARED_E2E_URL=http://localhost:3999 flutter test test/e2e
import 'dart:io';

import 'package:financas_app/data/cloud/api_client.dart';
import 'package:financas_app/data/cloud/shared_api.dart';
import 'package:financas_app/domain/models/shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['SHARED_E2E_URL'];
  test('fluxo completo pela API', () async {
    final a = ApiClient(url!);
    final reg = await a.post('auth/register', {
      'name': 'Ana',
      'email': 'ana@e2e.com',
      'password': 'Senha1234',
    });
    a.token = reg['token'] as String;
    await a.post('users', {
      'name': 'Bia',
      'email': 'bia@e2e.com',
      'password': 'Senha1234',
    });
    final b = ApiClient(url);
    b.token =
        (await b.post('auth/login', {
              'email': 'bia@e2e.com',
              'password': 'Senha1234',
            }))['token']
            as String;
    final sa = HttpSharedApi(a), sb = HttpSharedApi(b);
    final gid = await sa.createGroup('Casa', GroupKind.couple);
    await sa.invite(gid, 'bia@e2e.com', ShareRole.member);
    expect((await sb.state()).invites.single.groupName, 'Casa');
    await sb.respondInvite(gid, true);
    var s = await sa.state();
    final g = s.groups.single;
    final luz = g.categories.firstWhere((c) => c.name == 'Luz e água');
    final bia = g.members.firstWhere((m) => m.name == 'Bia').userId;
    await sa.updateCategory(luz.id, percentages: {s.userId: 6000, bia: 4000});
    await sa.upsertExpense({
      'groupId': gid,
      'categoryId': luz.id,
      'description': 'Luz',
      'total': 30000,
      'date': '2026-10-10',
      'dueDate': '2026-10-15',
      'source': 'card',
      'sourceKey': 'tx1',
    });
    final rid = await sa.createRecurrence({
      'groupId': gid,
      'categoryId': luz.id,
      'sourceRuleId': 'rule',
      'description': 'Água',
    });
    await sa.upsertExpense({
      'groupId': gid,
      'recurrenceId': rid,
      'description': 'Água',
      'total': 10000,
      'date': '2026-11-05',
      'source': 'recurring',
      'sourceKey': 'r:rule:2026-11-05',
      'occurrenceDate': '2026-11-05',
    });
    final sbState = await sb.state();
    final e = sbState.groups.single.expenses.first;
    expect(e.shareOf(bia)!.owed, 12000);
    expect(e.sourceKey, isNull);
    expect(e.cashDate, DateTime(2026, 10, 15));
    await sb.addPayment(
      e.id,
      userId: bia,
      amount: 5000,
      date: DateTime(2026, 10, 20),
    );
    await sb.settle(
      gid,
      fromUserId: bia,
      toUserId: s.userId,
      amount: 7000,
      date: DateTime(2026, 10, 25),
    );
    s = await sa.state();
    expect(s.groups.single.expenses.first.status, PayStatus.paid);
    expect(s.groups.single.recurrences.single.createdAt, isNotNull);
    final h = await sa.history(gid);
    expect(h.length, greaterThan(6));
  }, skip: url == null ? 'SHARED_E2E_URL não definido' : false);
}
