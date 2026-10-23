// As decisões de realocação: o dado vira decisão, e a decisão vira dado.
//
// Até hoje, mover uma SRE de um projeto para outro era decidido por WhatsApp, e ninguém sabia
// quem aprovou, quando e por quê. Aqui cada clique em Aprovar ou Recusar vira uma linha no
// Lakebase (Postgres): uma linha por clique, com chave, transação e leitura imediata.
//
// O app roda como service principal, que NÃO enxerga o schema public: ele cria o próprio
// schema (torre) na subida e vira dono dele. O usuário gravado é quem clicou (o e-mail que o
// Databricks Apps manda no header depois do login), não o service principal.

import type { Request } from 'express';
import { z } from 'zod';

// a função de consulta do plugin lakebase (appkit.lakebase.query)
export type Consulta = (sql: string, params?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;

const CRIAR = [
  `CREATE SCHEMA IF NOT EXISTS torre`,
  `CREATE TABLE IF NOT EXISTS torre.decisoes (
     id                    SERIAL PRIMARY KEY,
     projeto_origem        TEXT NOT NULL,
     projeto_destino       TEXT NOT NULL,
     recurso_id            TEXT NOT NULL,
     tipo                  TEXT NOT NULL CHECK (tipo IN ('pessoa')),
     decisao               TEXT NOT NULL CHECK (decisao IN ('aprovada', 'recusada')),
     justificativa         TEXT NOT NULL,
     horas_recuperadas_mes NUMERIC(12,1),
     economia_mes          NUMERIC(14,2),
     dias_recuperados      NUMERIC(8,1),
     usuario               TEXT NOT NULL,
     criado_em             TIMESTAMPTZ NOT NULL DEFAULT NOW()
   )`,
];

// A porta que escreve é a mais vigiada: nada entra no banco sem passar por aqui.
export const DecisaoSchema = z.object({
  projeto_origem: z.string().regex(/^PRJ-\d{3}$/),
  projeto_destino: z.string().regex(/^PRJ-\d{3}$/),
  recurso_id: z.string().regex(/^COL\d{4}$/),
  tipo: z.enum(['pessoa']),
  decisao: z.enum(['aprovada', 'recusada']),
  justificativa: z.string().trim().min(10, 'Escreva uma justificativa de pelo menos 10 caracteres').max(1000),
  horas_recuperadas_mes: z.coerce.number().nonnegative().optional(),
  economia_mes: z.coerce.number().nonnegative().optional(),
  dias_recuperados: z.coerce.number().nonnegative().optional(),
});

export type Decisao = z.infer<typeof DecisaoSchema>;

// quem clicou: o e-mail do login (fora do Databricks Apps, um marcador de desenvolvimento)
export const usuarioDaRequisicao = (req: Request) =>
  req.header('x-forwarded-email') ?? req.header('x-forwarded-user') ?? 'local@desenvolvimento';

export async function criarTabela(consulta: Consulta) {
  for (const sql of CRIAR) await consulta(sql);
}

export async function listarDecisoes(consulta: Consulta) {
  const { rows } = await consulta(
    `SELECT id, projeto_origem, projeto_destino, recurso_id, tipo, decisao, justificativa,
            horas_recuperadas_mes, economia_mes, dias_recuperados, usuario, criado_em
     FROM torre.decisoes
     ORDER BY criado_em DESC
     LIMIT 200`,
  );
  return rows;
}

export async function gravarDecisao(consulta: Consulta, d: Decisao, usuario: string) {
  const { rows } = await consulta(
    `INSERT INTO torre.decisoes
       (projeto_origem, projeto_destino, recurso_id, tipo, decisao, justificativa,
        horas_recuperadas_mes, economia_mes, dias_recuperados, usuario)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     RETURNING id, decisao, usuario, criado_em`,
    [
      d.projeto_origem, d.projeto_destino, d.recurso_id, d.tipo, d.decisao, d.justificativa,
      d.horas_recuperadas_mes ?? null, d.economia_mes ?? null, d.dias_recuperados ?? null, usuario,
    ],
  );
  return rows[0];
}
