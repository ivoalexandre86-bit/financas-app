import 'dart:convert';
import 'dart:typed_data';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/models/enums.dart';
import 'api_client.dart';

/// Lançamento lido de um cupom, nota ou comprovante pela IA.
class AiReceipt {
  final TransactionType type;
  final Money amount;
  final String description;
  final DateTime date;
  final String? categoryId;
  final String? accountId;
  final String? cardId;
  final int installments;
  final String notes;
  const AiReceipt({
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
    this.categoryId,
    this.accountId,
    this.cardId,
    this.installments = 1,
    this.notes = '',
  });

  factory AiReceipt.fromJson(Map<String, Object?> j) => AiReceipt(
    type: j['type'] == 'income'
        ? TransactionType.income
        : TransactionType.expense,
    amount: Money((j['amount'] as num).toInt()),
    description: (j['description'] as String?) ?? '',
    date: _date(j['date']),
    categoryId: j['categoryId'] as String?,
    accountId: j['accountId'] as String?,
    cardId: j['cardId'] as String?,
    installments: (j['installments'] as num?)?.toInt() ?? 1,
    notes: (j['notes'] as String?) ?? '',
  );
}

DateTime _date(Object? v) {
  try {
    return Dates.fromIso(v as String);
  } catch (_) {
    return Dates.dateOnly(DateTime.now());
  }
}

/// Uma fala da conversa com o assistente.
class AiTurn {
  final bool fromUser;
  final String text;
  const AiTurn(this.fromUser, this.text);
  Map<String, Object?> toJson() => {
    'role': fromUser ? 'user' : 'assistant',
    'text': text,
  };
}

/// IA do servidor: leitura de comprovantes e assistente financeiro.
abstract class AiService {
  Future<AiReceipt> readReceipt({
    Uint8List? bytes,
    String? mimeType,
    String? text,
  });
  Future<String> ask(String question, String snapshot, List<AiTurn> history);
}

class HttpAiService implements AiService {
  final ApiClient api;
  HttpAiService(this.api);

  static const _slow = Duration(seconds: 90);

  @override
  Future<AiReceipt> readReceipt({
    Uint8List? bytes,
    String? mimeType,
    String? text,
  }) async {
    final r = await api.post('ai/receipt', {
      if (bytes != null) 'media': base64Encode(bytes),
      if (bytes != null) 'mimeType': mimeType,
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
    }, _slow);
    return AiReceipt.fromJson(Map<String, Object?>.from(r['draft'] as Map));
  }

  @override
  Future<String> ask(
    String question,
    String snapshot,
    List<AiTurn> history,
  ) async {
    final r = await api.post('ai/ask', {
      'question': question,
      'snapshot': snapshot,
      'history': [for (final t in history) t.toJson()],
    }, _slow);
    return (r['answer'] as String?) ?? '';
  }
}
