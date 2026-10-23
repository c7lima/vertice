import { describe, expect, test } from 'vitest';
import { DecisaoSchema } from './routes/decisoes';

// a decisão do exemplo da aula: a SRE parada no PRJ-007 vai para o PRJ-011
const valida = {
  projeto_origem: 'PRJ-007',
  projeto_destino: 'PRJ-011',
  recurso_id: 'COL0017',
  tipo: 'pessoa',
  decisao: 'aprovada',
  justificativa: 'PRJ-011 pede SRE há 12 semanas e a COL0017 está a 6% no PRJ-007.',
  horas_recuperadas_mes: '150.8',
  economia_mes: '30123.18',
  dias_recuperados: '19',
};

describe('DecisaoSchema: a porta que escreve no Lakebase', () => {
  test('aceita uma decisão válida (e converte os números que chegam como texto)', () => {
    const r = DecisaoSchema.safeParse(valida);
    expect(r.success).toBe(true);
    expect(r.data?.economia_mes).toBe(30123.18);
  });

  test('recusa justificativa curta', () => {
    expect(DecisaoSchema.safeParse({ ...valida, justificativa: 'ok' }).success).toBe(false);
  });

  test('recusa projeto fora do padrão PRJ-000', () => {
    const r = DecisaoSchema.safeParse({ ...valida, projeto_origem: 'P007' });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.message).toContain('must match pattern');
  });

  test('recusa pessoa fora do padrão COL0000', () => {
    expect(DecisaoSchema.safeParse({ ...valida, recurso_id: 'C17' }).success).toBe(false);
  });

  test('recusa decisão que não é aprovada nem recusada', () => {
    expect(DecisaoSchema.safeParse({ ...valida, decisao: 'talvez' }).success).toBe(false);
  });
});
