import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/ai_snapshot.dart';
import '../../../data/cloud/ai_api.dart';
import '../../../state/finance_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Conversa com a IA sobre as finanças do usuário. A cada pergunta o app
/// manda um retrato atualizado (saldos, meses, categorias, orçamentos e
/// metas) calculado aqui, na visão de caixa.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final turns = <AiTurn>[];
  bool busy = false;

  static const suggestions = [
    'Como está meu mês?',
    'Onde estou gastando mais que o normal?',
    'Quanto posso guardar por mês?',
    'Vou fechar o mês no azul?',
    'Quais contas vencem esta semana?',
  ];

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _send(AiService ai, String text) async {
    final q = text.trim();
    if (q.isEmpty || busy) return;
    final fc = context.read<FinanceController>();
    final history = List<AiTurn>.of(turns);
    setState(() {
      turns.add(AiTurn(true, q));
      busy = true;
      input.clear();
    });
    _toEnd();
    try {
      final snapshot = buildAiSnapshot(
        fc.engine,
        budgets: fc.budgets,
        goals: fc.goals,
      );
      final answer = await ai.ask(q, snapshot, history);
      if (!mounted) return;
      setState(() => turns.add(AiTurn(false, answer)));
    } catch (e) {
      if (!mounted) return;
      setState(() => turns.add(AiTurn(false, 'Não consegui responder: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final ai = Provider.of<AiService?>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistente'),
        actions: [
          if (turns.isNotEmpty)
            IconButton(
              tooltip: 'Nova conversa',
              icon: const Icon(Icons.refresh),
              onPressed: busy ? null : () => setState(turns.clear),
            ),
        ],
      ),
      body: ai == null
          ? const EmptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'Assistente indisponível',
              message:
                  'O assistente com IA funciona com a conta na nuvem. Entre '
                  'com seu e-mail para usar.',
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (turns.isEmpty) ...[
                        Text(
                          'Pergunte sobre seus gastos, saldos, orçamentos e '
                          'metas. As respostas usam os dados do app (visão de '
                          'caixa).',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.fin.subtle,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in suggestions)
                              ActionChip(
                                label: Text(s),
                                onPressed: () => _send(ai, s),
                              ),
                          ],
                        ),
                      ],
                      for (final t in turns) _Bubble(t),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('assistant-input'),
                            controller: input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            decoration: const InputDecoration(
                              hintText: 'Escreva sua pergunta',
                            ),
                            onSubmitted: (v) => _send(ai, v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const ValueKey('assistant-send'),
                          tooltip: 'Enviar',
                          icon: const Icon(Icons.send),
                          onPressed: busy ? null : () => _send(ai, input.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AiTurn turn;
  const _Bubble(this.turn);

  @override
  Widget build(BuildContext context) {
    final mine = turn.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? context.colors.primaryContainer
              : context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(turn.text),
      ),
    );
  }
}
