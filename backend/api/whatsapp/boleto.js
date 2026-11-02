// Códigos de pagamento de contas: linha digitável de boleto (bancário, 47
// dígitos, ou de arrecadação/concessionária, 48 dígitos) e Pix copia e cola
// (BR Code). Confere os dígitos verificadores para não lembrar o usuário de
// pagar com um código lido errado.

const pad = (n) => String(n).padStart(2, '0');

function mod10(digits) {
  let sum = 0;
  let weight = 2;
  for (let i = digits.length - 1; i >= 0; i--) {
    let p = Number(digits[i]) * weight;
    if (p > 9) p = Math.floor(p / 10) + (p % 10);
    sum += p;
    weight = weight === 2 ? 1 : 2;
  }
  return (10 - (sum % 10)) % 10;
}

function mod11Sum(digits) {
  let sum = 0;
  let weight = 2;
  for (let i = digits.length - 1; i >= 0; i--) {
    sum += Number(digits[i]) * weight;
    weight = weight === 9 ? 2 : weight + 1;
  }
  return sum;
}

/// DV geral do código de barras de boleto bancário (0, 10 e 11 viram 1).
function mod11Bank(digits) {
  const dv = 11 - (mod11Sum(digits) % 11);
  return dv === 0 || dv >= 10 ? 1 : dv;
}

/// DV módulo 11 da arrecadação (10 e 11 viram 0).
function mod11Collection(digits) {
  const dv = 11 - (mod11Sum(digits) % 11);
  return dv >= 10 ? 0 : dv;
}

function isoOf(t) {
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

/**
 * Vencimento a partir do fator (dias). O fator voltou a 1000 em 22/02/2025;
 * entre os dois ciclos vale a data mais próxima de hoje.
 */
function dueFromFactor(factor, today) {
  if (!factor) return null;
  const day = 864e5;
  const old = new Date(Date.UTC(1997, 9, 7) + factor * day);
  const cur = new Date(Date.UTC(2025, 1, 22) + (factor - 1000) * day);
  const ref = new Date(`${today}T00:00:00Z`).getTime();
  const best = Math.abs(cur - ref) <= Math.abs(old - ref) ? cur : old;
  return isoOf(best);
}

/**
 * Lê uma linha digitável. Aceita pontos, espaços e traços.
 * @returns {{kind: 'bank'|'collection', code: string, amount: number|null,
 *   dueDate: string|null} | null} null quando inválida
 */
function parseBoleto(raw, today = isoOf(new Date())) {
  const code = String(raw ?? '').replace(/\D/g, '');
  if (code.length === 47) {
    const f1 = code.slice(0, 10);
    const f2 = code.slice(10, 21);
    const f3 = code.slice(21, 32);
    for (const f of [f1, f2, f3]) {
      if (mod10(f.slice(0, -1)) !== Number(f.at(-1))) return null;
    }
    const bar =
      code.slice(0, 4) + code[32] + code.slice(33, 47) +
      f1.slice(4, 9) + f2.slice(0, 10) + f3.slice(0, 10);
    if (mod11Bank(bar.slice(0, 4) + bar.slice(5)) !== Number(bar[4])) return null;
    const factor = Number(code.slice(33, 37));
    const cents = Number(code.slice(37, 47));
    return {
      kind: 'bank',
      code,
      amount: cents > 0 ? cents : null,
      dueDate: dueFromFactor(factor, today),
    };
  }
  if (code.length === 48 && code[0] === '8') {
    const blocks = [0, 12, 24, 36].map((i) => code.slice(i, i + 12));
    const ref = code[2];
    if (!'6789'.includes(ref)) return null;
    const dv = ref === '6' || ref === '7' ? mod10 : mod11Collection;
    for (const b of blocks) {
      if (dv(b.slice(0, 11)) !== Number(b[11])) return null;
    }
    const bar = blocks.map((b) => b.slice(0, 11)).join('');
    if (dv(bar.slice(0, 3) + bar.slice(4)) !== Number(bar[3])) return null;
    // Identificador 6 ou 8: valor efetivo em reais nas posições 5 a 15.
    const cents = ref === '6' || ref === '8' ? Number(bar.slice(4, 15)) : 0;
    return { kind: 'collection', code, amount: cents > 0 ? cents : null, dueDate: null };
  }
  return null;
}

/// Linha digitável com a pontuação de costume (para exibir).
function formatBoleto(code) {
  if (code.length === 47) {
    return `${code.slice(0, 5)}.${code.slice(5, 10)} ${code.slice(10, 15)}.${code.slice(15, 21)} ` +
      `${code.slice(21, 26)}.${code.slice(26, 32)} ${code[32]} ${code.slice(33)}`;
  }
  return code.match(/.{1,12}/g).join(' ');
}

function crc16(s) {
  let crc = 0xffff;
  for (const ch of Buffer.from(s, 'utf8')) {
    crc ^= ch << 8;
    for (let i = 0; i < 8; i++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/**
 * Confere um Pix copia e cola (BR Code com CRC16 no fim).
 * @returns {{code: string, amount: number|null} | null}
 */
function parsePix(raw) {
  const code = String(raw ?? '').trim().replace(/\s+/g, '');
  if (!code.startsWith('000201') || code.length < 30 || code.length > 600) return null;
  const crcAt = code.length - 4;
  if (code.slice(crcAt - 4, crcAt) !== '6304') return null;
  if (crc16(code.slice(0, crcAt)).toUpperCase() !== code.slice(crcAt).toUpperCase()) return null;
  // Campo 54 (valor) no nível de cima do EMV.
  let amount = null;
  for (let i = 0; i + 4 <= crcAt; ) {
    const id = code.slice(i, i + 2);
    const len = Number(code.slice(i + 2, i + 4));
    if (!Number.isFinite(len)) break;
    if (id === '54') {
      const v = Math.round(Number(code.slice(i + 4, i + 4 + len)) * 100);
      if (v > 0) amount = v;
    }
    i += 4 + len;
  }
  return { code, amount };
}

module.exports = { parseBoleto, formatBoleto, parsePix, mod10, crc16, dueFromFactor };
