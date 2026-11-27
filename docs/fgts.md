# FGTS: avaliação de acesso automático (nov/2026)

Conclusão: **não há fonte oficial ou autorizada que entregue o saldo do FGTS a
um app de finanças pessoais**. O app faz o acompanhamento manual.

| Fonte | Situação |
| --- | --- |
| Open Finance Brasil | O FGTS não faz parte do escopo (contas, cartões, crédito, investimentos, seguros, câmbio). A Caixa participa como banco, mas não compartilha a conta vinculada do FGTS. |
| Pluggy (agregador já usado no app) | Usa os dados do Open Finance; não traz o FGTS. |
| Consulta autorizada do extrato FGTS (Caixa, desde 10/11/2026) | O trabalhador autoriza pelo app FGTS ou na agência, por 90 dias. Só instituições financeiras **habilitadas pela Caixa** podem consultar, e só os **depósitos dos últimos 12 meses**, não o saldo total. Feita para comprovar renda/vínculo em operações financeiras. Não serve a este app. |
| App FGTS / gov.br | Só o titular vê o saldo. Não há API pública. Raspar a sessão do usuário violaria os termos e exigiria a senha gov.br. |

Fonte: Agência Brasil, reproduzida em O Tempo, 11/11/2026
(https://www.otempo.com.br/economia/2026/11/11/trabalhador-podera-autorizar-bancos-a-consultar-fgts-servico-pode-ser-usado-para-comprovar-renda).

## O que o app faz

- Saldo do FGTS como bem à parte (`Asset` com `AssetKind.fgts` e `FgtsDetails`):
  data do saldo, confirmado (extrato) ou estimado, depósito mensal e
  rendimento para estimar o saldo futuro (`FgtsEngine.projectedBalance`).
- Patrimônio: linha própria "FGTS" (`NetWorth.fgts`), fora do caixa.
- Saques simulados como `ScenarioFlow` (source `fgts`, refId = id do FGTS) em
  um `PlanScenario` (coleção `scenarios`). Valor e data têm marcas de
  confirmado/estimado.
- Projeção: o seletor "Cenário" sobrepõe os fluxos pendentes
  (`ScenarioEngine.apply`); o orçamento base e os meses fechados não mudam.
- "Registrar recebimento" lança a receita real, baixa o saldo do FGTS e marca
  o fluxo como realizado (não conta duas vezes).

Se a Caixa abrir a consulta do saldo a agregadores autorizados, basta um
sincronizador que grave `Asset.withValue` com `balanceConfirmed = true`.
