/**
 * Utilidades das telas da Torre.
 *
 * O warehouse devolve TODO número como string no JSON, mesmo quando o tipo gerado pelo
 * typegen diz `number`. Sem Number(), `toLocaleString` devolve a string intacta e `+`
 * concatena. Tudo passa por num() antes de qualquer conta ou formato.
 */
export const num = (v: unknown) => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
};

// o booleano também pode chegar como texto ("true")
export const sim = (v: unknown) => v === true || v === 'true';

export const milhoes = (v: unknown) =>
  `R$ ${(num(v) / 1e6).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} mi`;

export const mil = (v: unknown) =>
  `R$ ${(num(v) / 1e3).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} mil`;

export const reais = (v: unknown) =>
  num(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

export const indice = (v: unknown) =>
  num(v).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const pct = (v: unknown, casas = 0) =>
  `${(num(v) * 100).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;

export const decimal = (v: unknown, casas = 1) =>
  num(v).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });

// a causa do bloqueio, como a IA da noite 3 classificou, em português de diretoria
export const CAUSAS: Record<string, string> = {
  change_freeze: 'change freeze',
  falta_sre: 'falta de SRE',
  dependencia_fornecedor: 'fornecedor atrasado',
  rotatividade: 'rotatividade',
  mudanca_escopo: 'mudança de escopo',
  bug_retrabalho: 'bugs e retrabalho',
  aprovacao_cliente: 'aprovação do cliente',
};

// cor com significado: crítico é vermelho, atenção é âmbar (tokens do tema, nunca cor crua)
export const classeSituacao = (situacao: string) =>
  situacao === 'crítico'
    ? 'bg-destructive/15 text-destructive'
    : situacao === 'atenção'
      ? 'bg-warning/15 text-warning'
      : 'bg-muted text-muted-foreground';
