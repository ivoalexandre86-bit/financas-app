# Finanças — gestão financeira pessoal

Aplicativo Flutter (Android primeiro, pronto para iOS) para controlar contas,
cartões, recorrências e parcelamentos e **projetar o saldo mês a mês**.
Moeda BRL, locale pt-BR, datas DD/MM/AAAA.

## Estado atual

| Fase | Situação |
|---|---|
| 1 — MVP funcional | ✅ Navegação, dashboard, lançamentos, contas, categorias, persistência local, matriz de projeção, filtros, projetos |
| 2 — Motor financeiro | ✅ Recorrências, parcelas, ciclo de faturamento, faturas e pagamentos, saldos projetados, drill-down |
| 3 — Backend e segurança | 🟡 Esquema PostgreSQL com migrations, RLS e isolamento por usuário (`backend/db`). Autenticação local com PBKDF2. **Falta:** API REST e sincronização |
| 4 — Open Finance | 🟡 Interface de provedor, provedor *sandbox*, consentimento, importação, deduplicação e conciliação. **Falta:** provedor real via backend |
| 5 — Produção | ⏳ 31 testes automatizados do motor e das regras; falta monitoramento de erros, build de release assinado e ficha da Play Store |

## Plataformas: web, Android e iOS

O mesmo código roda nas três. A persistência escolhe a implementação por
plataforma (`lib/data/db_factory.dart`): arquivo local no Android/iOS e
IndexedDB no navegador.

| Plataforma | Situação | Como gerar |
|---|---|---|
| Web | ✅ Compilado e testado no Chromium | `flutter build web --release --no-web-resources-cdn` → pasta `build/web`, publicável em qualquer hospedagem estática (Firebase Hosting, Netlify, Vercel, S3) |
| Android | ✅ Configurado (nome “Finanças”, ícone adaptativo, permissão de internet, `br.com.financas.financas_app`) | `flutter build apk --release` ou `flutter build appbundle` (Play Store). Requer Android SDK |
| iOS | ✅ Configurado (nome “Finanças”, idioma pt-BR, ícones, iOS 15+) | Em um Mac com Xcode: `flutter build ipa` ou abrir `ios/Runner.xcworkspace`. Requer conta Apple Developer para assinar |

Antes de publicar nas lojas, troque o identificador `br.com.financas.financas_app`
pelo seu (Android: `android/app/build.gradle.kts`; iOS: *Bundle Identifier*
no Xcode) e configure a assinatura de release.

## Como rodar

```bash
flutter pub get
flutter test                 # motor financeiro + regras de negócio
flutter run                  # Android ou iOS (emulador/dispositivo)
flutter run -d chrome        # web, útil para revisão rápida
```

Na tela de login, **“Explorar com dados de exemplo”** abre uma conta de
demonstração com seis meses de histórico fictício (faixa laranja “Dados de
exemplo” no topo). Contas reais começam vazias, só com as categorias padrão.

Banco PostgreSQL:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/db/migrations/001_initial_schema.sql
```

## Estrutura

```
lib/
  core/            Money (centavos inteiros), datas, YearMonth, IDs
  domain/
    models/        Entidades e enums (JSON ↔ objetos)
    engine/        Motor de cálculo puro (sem Flutter):
                   billing_cycle, recurrence, installments,
                   projection_filter, financial_engine
  data/            Persistência local (sembast, um banco por usuário),
                   autenticação, dados de exemplo, Open Finance
  state/           FinanceController / AuthController (ChangeNotifier)
  ui/              Tema, componentes e as 23 telas
backend/db/migrations/  Esquema PostgreSQL
test/              Testes do motor e do controlador
```

O motor (`FinancialEngine`) é a única fonte de números: dashboard, lista,
matriz, drill-down, faturas e projetos chamam as mesmas funções, então os
valores sempre batem entre telas. Toda alteração grava no repositório,
recarrega a foto dos dados e recria o motor, recalculando tudo.

## Regras de negócio implementadas

**Dinheiro.** Todos os valores são `Money` em centavos inteiros; nada de
`double` em valores persistidos. Parcelas dividem o total sem perder centavos
(R$ 1.000,00 em 3× = 333,34 + 333,33 + 333,33).

**Transferências** nunca contam como receita ou despesa. Só aparecem na
projeção quando você filtra por conta (linha “Transferências”).

**Cartão de crédito.**
- Fatura identificada pelo mês de fechamento. Compras *antes* do dia de
  fechamento entram na fatura do mês; no dia do fechamento ou depois, na
  seguinte (fecha dia 10: compra em 09/08 → agosto; 11/08 → setembro).
- Dias 29–31 se ajustam ao fim do mês. Vencimento no mesmo mês se o dia de
  vencimento for maior que o de fechamento, senão no mês seguinte.
- A compra é a despesa, reconhecida no mês de vencimento da fatura (visão de
  caixa, padrão) ou no mês da compra (configurável). **O pagamento da fatura
  liquida o passivo e não é uma segunda despesa.**
- Status da fatura: futura, aberta, fechada, paga parcialmente, paga,
  vencida. Pagamentos parciais acumulam; dá para desfazer.
- Limite disponível = limite − saldo devedor, incluindo parcelas futuras.
- Mudar o dia de fechamento recalcula a alocação de todas as compras.

**Parcelamentos.** A parcela N cai N − 1 faturas depois da compra (ou
N − 1 meses, se for em conta). Mostra progresso “3/12”. Dá para alterar o
valor ou cancelar só as parcelas futuras, sem tocar nas já faturadas.

**Recorrências.** As ocorrências futuras são geradas pelo motor (não
gravadas) e deduplicadas contra as já confirmadas pela chave
regra + data da ocorrência. Datas calculadas pela âncora, sem deriva
(31/01 → 28/02 → 31/03). Frequências semanal, mensal, trimestral, anual e
personalizada (a cada N dias/semanas/meses), data final e pausa/retomada.
Ao editar, você escolhe entre “somente futuras” (a regra vira uma nova
versão a partir de hoje) ou “futuras e planejadas existentes”. Excluir a
regra preserva os lançamentos concluídos.

**Projeção mensal.** Resultado = Receitas − Despesas; Acumulado = anterior
+ resultado. Saldo inicial = saldos iniciais das contas + tudo o que foi
reconhecido antes do primeiro mês, ou um valor informado para simular.
Com filtros de categoria/projeto/tipo/origem/status o acumulado começa em
zero (é o acumulado do recorte). Períodos de 3, 6, 12, 24 meses ou
personalizado; primeira coluna fixa; negativos destacados.

**Status rápido.** Na lista de transações, cada receita/despesa tem uma
caixa de seleção que alterna Concluída ⇄ Pendente com um toque (sem abrir
os detalhes). A mudança é aplicada na hora e gravada em seguida; saldos,
indicadores e painéis recalculam juntos. Lançamentos pendentes aparecem com
valor esmaecido e marcados como atrasados quando a data já passou. Filtros
rápidos: Tudo / Receitas / Despesas e Todas / Pendentes (planejadas +
pendentes) / Concluídas, sempre dentro do mês selecionado. Concluir uma
ocorrência prevista de recorrência a materializa (mantendo o vínculo com a
regra).

**Painéis personalizados.** A tela inicial mostra o painel padrão; o botão
**Personalizar painel** abre o modo de edição. Cada painel tem filtros
aplicados a todos os gráficos (período, status e categorias) e um mês de
referência. Cada gráfico define título, fonte (receitas, despesas, ambos,
resultado ou saldo projetado), categorias, status, período próprio ou do
painel (mês, vários meses, ano, intervalo de datas, janela relativa),
comparação (período anterior ou ano anterior), eixo X, valor do eixo Y
(soma, quantidade, média), séries, totais/percentuais/variações, cores e
tamanho. Tipos: barras, barras empilhadas, linhas, área, tendência
(mínimos quadrados), cascata, Pareto 80/20, pizza, rosca, comparativo,
evolução mensal e acumulado; dá para trocar o tipo sem recriar o gráfico.
Painéis podem ser criados, renomeados, duplicados, excluídos e definidos
como padrão; gráficos podem ser adicionados, removidos, duplicados,
redimensionados e reorganizados (arrastar). Os painéis guardam só
configuração: os números vêm do mesmo `FinancialEngine`
(`lib/domain/engine/dashboard_engine.dart`), então qualquer alteração em
transações aparece em todos eles.

**Saldo atual × projetado.** “Saldo atual” usa apenas lançamentos concluídos
e pagamentos de fatura. “Projetado” assume que tudo o que está planejado
acontece e que as faturas são pagas integralmente no vencimento.
“Disponível” = saldo atual − despesas e faturas em aberto até o fim do mês.

**Importação de despesas por planilha** (Mais › Importar despesas, ou o
menu ⋮ em Transações). O app gera um modelo `.xlsx` com listas suspensas dos
cadastros do usuário (categorias, contas, cartões, projetos, status), aba de
instruções e exemplos; aceita `.xlsx` ou `.csv`. Antes de gravar há uma
prévia linha a linha: erros (data/valor inválidos, conta ou cartão
inexistente) bloqueiam a linha, e lançamentos já existentes com mesma data,
valor e descrição vêm desmarcados como possíveis duplicadas. Parcelas > 1
criam uma compra parcelada (o valor informado é o total). Tudo é gravado em
um único lote. Leitura/validação em `lib/domain/import/expense_import.dart`
e `lib/data/spreadsheet_io.dart` (leitor `.xlsx` próprio, em Dart puro).

## Segurança e privacidade

- Senhas com PBKDF2-HMAC-SHA256 + salt aleatório, comparação em tempo
  constante; sessão por token aleatório com expiração.
- Banco local separado por usuário; no PostgreSQL, chaves estrangeiras
  compostas `(id, user_id)` e Row Level Security impedem acesso cruzado
  (testado: um usuário não enxerga nem referencia contas de outro).
- O app nunca pede senha bancária; Open Finance usa consentimento do
  provedor e pode ser revogado.
- Política de privacidade (texto provisório) e exclusão de conta e dados em
  Configurações.

## Próximos passos

1. API REST (Dart `shelf` ou outra stack) sobre o esquema PostgreSQL, com
   JWT de acesso + refresh token e `SET LOCAL app.current_user_id` por
   requisição; trocar `LocalFinanceRepository`/`LocalAuthService` por versões
   remotas (as interfaces já existem).
2. Guardar tokens em `flutter_secure_storage` no Android/iOS.
3. Provedor Open Finance real (Pluggy, Belvo ou similar) chamado pelo
   backend, implementando `OpenFinanceProvider`.
4. Crashlytics/Sentry, ícone e splash, assinatura de release e ficha da
   Play Store; revisão jurídica da política de privacidade.
