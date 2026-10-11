// Cálculo da divisão de uma despesa compartilhada. Percentuais em
// pontos-base (10000 = 100%); valores em centavos.

const FULL = 10000;

/// Divide `total` conforme `shares` ([{userId, bp}]) sem perder centavos:
/// cada um recebe o piso da sua parte e os centavos que sobram vão para as
/// maiores frações (empate: ordem da lista).
function allocate(total, shares) {
  const rows = shares
    .filter((s) => s.bp > 0)
    .map((s, i) => {
      const exact = total * s.bp;
      return {
        userId: s.userId,
        bp: s.bp,
        amount: Math.floor(exact / FULL),
        rest: exact % FULL,
        i,
      };
    });
  let left = total - rows.reduce((a, r) => a + r.amount, 0);
  const order = [...rows].sort((a, b) => b.rest - a.rest || a.i - b.i);
  for (const r of order) {
    if (left <= 0) break;
    r.amount++;
    left--;
  }
  return rows.map(({ userId, bp, amount }) => ({ userId, bp, amount }));
}

/// Confere uma configuração de percentuais ({userId: bp}). Devolve a lista
/// normalizada ou uma mensagem de erro.
function checkPercentages(percentages, activeIds) {
  if (!percentages || typeof percentages !== 'object' || Array.isArray(percentages)) {
    return { error: 'Informe os percentuais dos participantes' };
  }
  const list = [];
  for (const [userId, raw] of Object.entries(percentages)) {
    const bp = Number(raw);
    if (!Number.isInteger(bp) || bp < 0 || bp > FULL) {
      return { error: 'Percentual inválido' };
    }
    if (bp === 0) continue;
    if (!activeIds.includes(userId)) {
      return { error: 'Só participantes ativos do grupo podem ter percentual' };
    }
    list.push({ userId, bp });
  }
  const sum = list.reduce((a, s) => a + s.bp, 0);
  if (sum !== FULL) {
    return {
      error: `A soma dos percentuais deve ser 100% (está em ${(sum / 100).toLocaleString('pt-BR')}%)`,
    };
  }
  // Ordem estável: a do grupo (activeIds).
  list.sort((a, b) => activeIds.indexOf(a.userId) - activeIds.indexOf(b.userId));
  return { list };
}

const toObject = (list) => Object.fromEntries(list.map((s) => [s.userId, s.bp]));

module.exports = { FULL, allocate, checkPercentages, toObject };
