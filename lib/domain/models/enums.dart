/// Enumerações do domínio financeiro, com rótulos em pt-BR.
library;

enum TransactionType {
  income('Receita'),
  expense('Despesa'),
  transfer('Transferência');

  final String label;
  const TransactionType(this.label);
}

enum TransactionStatus {
  planned('Planejada'),
  pending('Pendente'),
  completed('Concluída'),
  cancelled('Cancelada');

  final String label;
  const TransactionStatus(this.label);

  /// Status que entram nos cálculos de projeção por padrão.
  bool get countsInProjection => this != TransactionStatus.cancelled;
}

enum AccountType {
  checking('Conta corrente'),
  savings('Poupança'),
  digital('Conta digital'),
  cash('Dinheiro'),
  investment('Investimentos');

  final String label;
  const AccountType(this.label);
}

enum CategoryKind {
  income('Receita'),
  expense('Despesa');

  final String label;
  const CategoryKind(this.label);
}

enum RecurrenceFrequency {
  weekly('Semanal'),
  monthly('Mensal'),
  quarterly('Trimestral'),
  yearly('Anual'),
  custom('Personalizada');

  final String label;
  const RecurrenceFrequency(this.label);
}

enum RecurrenceUnit {
  days('dia(s)'),
  weeks('semana(s)'),
  months('mês(es)');

  final String label;
  const RecurrenceUnit(this.label);
}

/// Como as compras no cartão eram reconhecidas como despesa nos relatórios.
///
/// Obsoleto: o app usa uma única visão, por mês de pagamento da fatura.
/// Mantido apenas para ler configurações gravadas por versões anteriores.
enum CardExpenseBasis {
  /// No mês de vencimento da fatura (visão de caixa — padrão).
  invoiceDue('Mês de vencimento da fatura'),

  /// No mês da compra (visão de competência).
  purchaseDate('Mês da compra');

  final String label;
  const CardExpenseBasis(this.label);
}

enum InvoiceStatus {
  future('Planejada'),
  open('Aberta'),
  closed('Fechada'),
  partial('Paga parcialmente'),
  paid('Paga'),
  overdue('Vencida');

  final String label;
  const InvoiceStatus(this.label);
}

enum ConsentStatus {
  pending('Aguardando autorização'),
  active('Ativo'),
  expired('Expirado'),
  revoked('Revogado');

  final String label;
  const ConsentStatus(this.label);
}

enum ExternalTxStatus {
  pending('Novo'),
  imported('Importado'),
  matched('Conciliado'),
  ignored('Ignorado');

  final String label;
  const ExternalTxStatus(this.label);
}

T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
