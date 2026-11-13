import 'package:financas_app/data/cloud/account_api.dart';
import 'package:financas_app/ui/screens/account/account_members_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Servidor falso: Ivo é o dono; convites e remoções mudam a lista.
class FakeAccountApi implements AccountApi {
  bool owner;
  final members = <AccountMember>[];
  final invites = <AccountInvite>[];
  final calls = <String>[];
  FakeAccountApi({this.owner = true});

  AccountState get _s => AccountState(
    accountId: 'ivo',
    ownerName: 'Ivo',
    ownerEmail: 'ivo@x.com',
    isOwner: owner,
    members: [
      const AccountMember(
        id: null,
        userId: 'ivo',
        name: 'Ivo',
        email: 'ivo@x.com',
        status: 'owner',
      ),
      ...members,
    ],
    invites: invites,
  );

  @override
  Future<AccountState> state() async => _s;

  @override
  Future<AccountState> invite(String email) async {
    calls.add('invite $email');
    members.add(
      AccountMember(
        id: 'm${members.length}',
        userId: null,
        name: null,
        email: email,
        status: 'invited',
      ),
    );
    return _s;
  }

  @override
  Future<AccountState> remove(String memberId) async {
    calls.add('remove $memberId');
    members.removeWhere((m) => m.id == memberId);
    return _s;
  }

  @override
  Future<AccountState> leave() async => _s;
  @override
  Future<AccountState> accept(String inviteId) async => _s;
  @override
  Future<AccountState> reject(String inviteId) async {
    calls.add('reject $inviteId');
    invites.removeWhere((i) => i.id == inviteId);
    return _s;
  }
}

Future<void> _open(WidgetTester tester, AccountApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AccountMembersScreen(api: api),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dono convida pelo e-mail e cancela o convite', (tester) async {
    final api = FakeAccountApi();
    await _open(tester, api);
    expect(find.text('Sua conta'), findsOneWidget);
    expect(find.textContaining('Dono da conta'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('invite-email')), 'x');
    await tester.tap(find.byKey(const ValueKey('send-invite')));
    await tester.pumpAndSettle();
    expect(find.text('Informe um e-mail válido'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('invite-email')),
      'ana@x.com',
    );
    await tester.tap(find.byKey(const ValueKey('send-invite')));
    await tester.pumpAndSettle();
    expect(api.calls, ['invite ana@x.com']);
    expect(find.text('Convite pendente · ana@x.com'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remove-ana@x.com')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar convite').last);
    await tester.pumpAndSettle();
    expect(api.calls.last, 'remove m0');
    expect(find.text('Convite pendente · ana@x.com'), findsNothing);
  });

  testWidgets('quem entrou na conta vê o dono e pode sair', (tester) async {
    final api = FakeAccountApi(owner: false)
      ..members.add(
        const AccountMember(
          id: 'm1',
          userId: 'ana',
          name: 'Ana',
          email: 'ana@x.com',
          status: 'active',
        ),
      );
    await _open(tester, api);
    expect(find.text('Você está usando a conta de Ivo'), findsOneWidget);
    expect(find.byKey(const ValueKey('leave-account')), findsOneWidget);
    // Só o dono convida e remove.
    expect(find.byKey(const ValueKey('invite-email')), findsNothing);
    expect(find.byKey(const ValueKey('remove-ana@x.com')), findsNothing);
  });

  testWidgets('convite recebido: aceitar ou recusar', (tester) async {
    final api = FakeAccountApi()
      ..invites.add(const AccountInvite('i1', 'Bia', 'bia@x.com'));
    await _open(tester, api);
    expect(find.text('Convite de Bia'), findsOneWidget);
    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    expect(api.calls, ['reject i1']);
    expect(find.text('Convite de Bia'), findsNothing);
  });

  test('AccountState.fromJson', () {
    final s = AccountState.fromJson({
      'account': {
        'id': 'a',
        'ownerName': 'Ivo',
        'ownerEmail': 'ivo@x.com',
        'isOwner': false,
      },
      'members': [
        {
          'id': null,
          'userId': 'a',
          'name': 'Ivo',
          'email': 'ivo@x.com',
          'status': 'owner',
        },
        {
          'id': 'm',
          'userId': null,
          'name': null,
          'email': 'ana@x.com',
          'status': 'invited',
        },
      ],
      'invites': [
        {'id': 'i', 'ownerName': 'Bia', 'ownerEmail': 'bia@x.com'},
      ],
      'maxMembers': 5,
    });
    expect(s.isOwner, isFalse);
    expect(s.guestCount, 1);
    expect(s.members.last.label, 'ana@x.com');
    expect(s.invites.single.ownerName, 'Bia');
  });
}
