import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ids.dart';
import '../../../core/money.dart';
import '../../../domain/models/entities.dart';
import '../../../state/finance_controller.dart';
import '../../widgets/category_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

class ProjectFormScreen extends StatefulWidget {
  final Project? project;
  const ProjectFormScreen({super.key, this.project});
  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.project?.name ?? '');
  late final desc = TextEditingController(
    text: widget.project?.description ?? '',
  );
  late final budget = TextEditingController(
    text: widget.project?.budget.formatPlain() ?? '',
  );
  late DateTime? start = widget.project?.startDate;
  late DateTime? end = widget.project?.endDate;
  late int color = widget.project?.color ?? palette.first;
  late bool archived = widget.project?.archived ?? false;

  @override
  Widget build(BuildContext context) {
    final fc = context.read<FinanceController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project == null ? 'Novo projeto' : 'Editar projeto'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: desc,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            const SizedBox(height: 12),
            MoneyField(controller: budget, label: 'Orçamento', allowZero: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DateField(
                    value: start,
                    label: 'Início',
                    clearable: true,
                    onChanged: (d) => setState(() => start = d),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DateField(
                    value: end,
                    label: 'Fim',
                    clearable: true,
                    onChanged: (d) => setState(() => end = d),
                  ),
                ),
              ],
            ),
            if (start != null && end != null && end!.isBefore(start!))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'A data final deve ser após a inicial',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            if (widget.project != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Arquivado'),
                value: archived,
                onChanged: (v) => setState(() => archived = v),
              ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                if (start != null && end != null && end!.isBefore(start!)) {
                  return;
                }
                final b = Money.tryParse(budget.text)!;
                final p =
                    (widget.project ??
                            Project(id: newId('prj_'), name: name.text.trim()))
                        .copyWith(
                          name: name.text.trim(),
                          description: desc.text.trim(),
                          budget: b,
                          startDate: start,
                          endDate: end,
                          color: color,
                          archived: archived,
                        );
                final ok = await runAction(
                  context,
                  () => fc.saveProject(p),
                  success: 'Projeto salvo',
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
