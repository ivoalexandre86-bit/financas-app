/// Instituições financeiras brasileiras identificadas pelo código COMPE
/// (3 dígitos, atribuído pelo Banco Central) — o mesmo código usado em
/// TED, boletos e no Pix.
class Bank {
  final String code;
  final String name;

  /// Outras formas comuns de escrever o nome (usadas para reconhecer
  /// instituições digitadas livremente).
  final List<String> aliases;

  const Bank(this.code, this.name, [this.aliases = const []]);

  /// Ex.: "341 · Itaú Unibanco".
  String get label => '$code · $name';
}

const List<Bank> brazilianBanks = [
  Bank('001', 'Banco do Brasil', ['bb', 'banco do brasil s.a.']),
  Bank('003', 'Banco da Amazônia', ['basa']),
  Bank('004', 'Banco do Nordeste', ['bnb']),
  Bank('021', 'Banestes'),
  Bank('025', 'Banco Alfa', ['alfa']),
  Bank('033', 'Santander', ['banco santander']),
  Bank('037', 'Banpará', ['banco do para']),
  Bank('041', 'Banrisul', ['banco do estado do rio grande do sul']),
  Bank('047', 'Banese', ['banco do estado de sergipe']),
  Bank('069', 'Crefisa', ['banco crefisa']),
  Bank('070', 'BRB - Banco de Brasília', ['brb', 'banco de brasilia']),
  Bank('077', 'Banco Inter', ['inter', 'banco intermedium']),
  Bank('085', 'Ailos', ['cooperativa central ailos', 'viacredi']),
  Bank('102', 'XP Investimentos', ['xp', 'xp investimentos cctvm']),
  Bank('104', 'Caixa Econômica Federal', ['caixa', 'cef', 'caixa economica']),
  Bank('121', 'Agibank', ['agiplan', 'banco agibank']),
  Bank('125', 'Banco Genial', ['genial', 'genial investimentos']),
  Bank('133', 'Cresol'),
  Bank('136', 'Unicred'),
  Bank('197', 'Stone', ['stone pagamentos']),
  Bank('208', 'BTG Pactual', ['btg', 'banco btg pactual']),
  Bank('212', 'Banco Original', ['original']),
  Bank('218', 'Banco BS2', ['bs2']),
  Bank('237', 'Bradesco', ['banco bradesco', 'next']),
  Bank('246', 'Banco ABC Brasil', ['abc brasil']),
  Bank('260', 'Nubank', ['nu pagamentos', 'nu bank', 'nu']),
  Bank('280', 'Will Bank', ['will', 'avista']),
  Bank('290', 'PagBank', ['pagseguro', 'pag seguro', 'pagbank pagseguro']),
  Bank('318', 'Banco BMG', ['bmg']),
  Bank('323', 'Mercado Pago', ['mercadopago']),
  Bank('329', 'QI Tech', ['qi scd', 'qi sociedade de credito direto']),
  Bank('336', 'C6 Bank', ['c6', 'banco c6']),
  Bank('341', 'Itaú Unibanco', [
    'itau',
    'banco itau',
    'itau personnalite',
    'personnalite',
    'iti',
  ]),
  Bank('348', 'Banco XP', ['xp banco']),
  Bank('364', 'Efí', ['gerencianet', 'efi bank']),
  Bank('376', 'J.P. Morgan', ['jp morgan', 'jpmorgan']),
  Bank('380', 'PicPay', ['picpay bank']),
  Bank('389', 'Banco Mercantil do Brasil', [
    'mercantil',
    'mercantil do brasil',
  ]),
  Bank('403', 'Cora', ['cora scd']),
  Bank('422', 'Banco Safra', ['safra']),
  Bank('461', 'Asaas', ['asaas ip']),
  Bank('536', 'Neon', ['neon pagamentos', 'banco neon']),
  Bank('612', 'Banco Guanabara', ['guanabara']),
  Bank('623', 'Banco Pan', ['pan', 'banco panamericano']),
  Bank('633', 'Banco Rendimento', ['rendimento']),
  Bank('634', 'Banco Triângulo', ['tribanco', 'triangulo']),
  Bank('637', 'Banco Sofisa', ['sofisa', 'sofisa direto']),
  Bank('643', 'Banco Pine', ['pine']),
  Bank('655', 'Banco BV', ['bv', 'banco votorantim', 'votorantim']),
  Bank('707', 'Banco Daycoval', ['daycoval']),
  Bank('745', 'Citibank', ['citi', 'banco citibank']),
  Bank('748', 'Sicredi', ['banco cooperativo sicredi']),
  Bank('756', 'Sicoob', ['bancoob', 'banco cooperativo do brasil']),
];

final Map<String, Bank> _byCode = {for (final b in brazilianBanks) b.code: b};

Bank? bankByCode(String? code) =>
    code == null || code.isEmpty ? null : _byCode[code.padLeft(3, '0')];

/// Minúsculas, sem acentos e só com letras/dígitos separados por espaço.
String normalizeBankText(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Reconhece uma instituição digitada livremente ("Itaú", "341",
/// "Nu Pagamentos", "260 - Nubank"...). Retorna `null` quando não há
/// correspondência segura.
Bank? matchBank(String text) {
  final t = normalizeBankText(text);
  if (t.isEmpty) return null;

  // Código no início: "341", "341 itau", "0341".
  final code = RegExp(r'^0*(\d{1,3})\b').firstMatch(t);
  if (code != null) {
    final b = bankByCode(code.group(1));
    if (b != null) return b;
  }

  // Nome ou apelido exato.
  for (final b in brazilianBanks) {
    if (normalizeBankText(b.name) == t) return b;
    for (final a in b.aliases) {
      if (normalizeBankText(a) == t) return b;
    }
  }

  // Nome/apelido contido no texto como palavra inteira ("Conta Itaú",
  // "Itaú Unibanco S.A."). Apelidos curtos (≤ 3 letras) só valem exatos.
  Bank? best;
  var bestLen = 0;
  for (final b in brazilianBanks) {
    for (final n in [b.name, ...b.aliases]) {
      final k = normalizeBankText(n);
      if (k.length <= 3) continue;
      if (' $t '.contains(' $k ') && k.length > bestLen) {
        best = b;
        bestLen = k.length;
      }
    }
  }
  return best;
}

/// Busca para o seletor: por código ou por nome/apelido.
List<Bank> searchBanks(String query) {
  final q = normalizeBankText(query);
  if (q.isEmpty) return brazilianBanks;
  return [
    for (final b in brazilianBanks)
      if (b.code.contains(q) ||
          normalizeBankText(b.name).contains(q) ||
          b.aliases.any((a) => normalizeBankText(a).contains(q)))
        b,
  ];
}

/// Texto exibido para uma instituição: "341 · Itaú Unibanco" quando há
/// código, senão o nome livre.
String institutionLabel(String code, String name) {
  final b = bankByCode(code);
  if (b != null) return b.label;
  if (code.isNotEmpty && name.isNotEmpty) return '$code · $name';
  return name;
}
