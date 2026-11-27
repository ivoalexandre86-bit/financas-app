import 'package:financas_app/data/cloud/account_api.dart';
import 'package:financas_app/data/cloud/invite_api.dart';
import 'package:financas_app/ui/widgets/access_scope_picker.dart';
import 'package:financas_app/ui/screens/users/invites_screen.dart';
import 'package:financas_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WhatsAppInvite _invite({
  String name = 'Ana',
  String sendStatus = 'not_sent',
  String status = 'pending',
  AccessScope? scope,
}) => WhatsAppInvite(
  id: 'i-$name',
  name: name,
  phone: '5547991892931',
  phoneLabel: '+55 (47) 99189-2931',
  joinAccount: true,
  scope: scope,
  status: status,
  sendStatus: sendStatus,
  sendError: 'O modelo da mensagem está em análise na Meta.',
  userName: null,
  link: 'https://app/?cadastro=abc',
  shareUrl: 'https://wa.me/5547991892931?text=oi',
  expiresAt: null,
);

class _FakeApi implements InviteApi {
  final invites = <WhatsAppInvite>[];
  InviteTemplate template = const InviteTemplate('PENDING');
  final created = <(String, String, bool)>[];
  AccessScope? lastScope;

  @override
  Future<InvitesState> list() async => InvitesState([...invites], template);

  @override
  Future<(WhatsAppInvite, InviteTemplate)> create({
    required String name,
    required String phone,
    required bool joinAccount,
    AccessScope? scope,
  }) async {
    created.add((name, phone, joinAccount));
    lastScope = scope;
    final i = _invite(
      name: name,
      sendStatus: template.approved ? 'sent' : 'not_sent',
      scope: scope,
    );
    invites.insert(0, i);
    return (i, template);
  }

  @override
  Future<(WhatsAppInvite, InviteTemplate)> resend(String id) async =>
      (invites.first, template);

  @override
  Future<void> cancel(String id) async =>
      invites.removeWhere((i) => i.id == id);
}

Future<List<Uri>> _pump(WidgetTester tester, _FakeApi api) async {
  final opened = <Uri>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: InvitesScreen(
        api: api,
        openUrl: (u) async => opened.add(u),
        scopeOptions: const ScopeOptions(
          cards: [('nubank', 'Nubank'), ('xp', 'XP')],
          accounts: [('itau', 'Itaú')],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('modelo em análise: convida e oferece o envio manual', (
    tester,
  ) async {
    final api = _FakeApi();
    final opened = await _pump(tester, api);
    expect(find.byKey(const ValueKey('invite-template-banner')), findsOneWidget);
    expect(find.text('Nenhum convite ainda'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new-invite')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('invite-name')), 'Ana');
    await tester.enterText(
      find.byKey(const ValueKey('invite-phone')),
      '(47) 99189-2931',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('invite-join')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-join')));
    await tester.pumpAndSettle();
    // Usar o meu orçamento: o padrão é liberar só o que for marcado.
    await tester.ensureVisible(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Marque ao menos um cartão ou conta.'), findsOneWidget);
    expect(api.created, isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('scope-nubank')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-nubank')));
    await tester.ensureVisible(find.byKey(const ValueKey('scope-itau')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-itau')));
    await tester.ensureVisible(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    expect(api.created.single, ('Ana', '(47) 99189-2931', true));
    expect(api.lastScope!.cards, ['nubank']);
    expect(api.lastScope!.accounts, ['itau']);

    expect(find.text('Envie pelo seu WhatsApp'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invite-send-manual')));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'wa.me');
    expect(find.text('Não enviado'), findsOneWidget);
    expect(find.textContaining('acesso: Cartão Nubank, Conta Itaú'), findsOneWidget);
  });

  testWidgets('modelo aprovado: o bot envia', (tester) async {
    final api = _FakeApi()..template = const InviteTemplate('APPROVED');
    await _pump(tester, api);
    expect(find.byKey(const ValueKey('invite-template-banner')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('new-invite')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('invite-name')), 'Bia');
    await tester.enterText(
      find.byKey(const ValueKey('invite-phone')),
      '11988887777',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Envie pelo seu WhatsApp'), findsNothing);
    expect(find.text('Enviado'), findsOneWidget);
  });

  testWidgets('servidor sem a rota: aviso claro', (tester) async {
    await _pump(tester, _OldServerApi());
    expect(find.text('Servidor ainda não atualizado'), findsOneWidget);
  });

  testWidgets('número curto não passa', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const ValueKey('new-invite')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('invite-name')), 'Ana');
    await tester.enterText(find.byKey(const ValueKey('invite-phone')), '9999');
    await tester.ensureVisible(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Informe DDD + número'), findsOneWidget);
    expect(api.created, isEmpty);
  });
}

class _OldServerApi extends _FakeApi {
  @override
  Future<InvitesState> list() async =>
      throw Exception('Erro 404 no servidor');
}

