// A chance de estouro em 30 dias de cada projeto (o modelo do prompt 1, gold.score_estouro_30d).
//
// Exceção consciente à regra "leitura é sempre config/queries/*.sql": uma query em
// config/queries com tabela que ainda não existe quebra o typegen e, com ele, o build do
// app inteiro. Aqui, se a tabela faltar, a rota responde { disponivel: false } e a tela
// mostra "—" no lugar da probabilidade.

import { getExecutionContext, getWarehouseId } from '@databricks/appkit';

const SQL = `
  SELECT projeto_id, prob_estouro_30d, ranking, faixa_risco
  FROM lakehouse_vertice.gold.score_estouro_30d
  WHERE data_referencia = (SELECT MAX(data_referencia) FROM lakehouse_vertice.gold.score_estouro_30d)`;

export interface RespostaScore {
  disponivel: boolean;
  motivo?: string;
  linhas: Record<string, string | null>[];
}

export async function buscarScore(): Promise<RespostaScore> {
  try {
    const { client } = getExecutionContext();
    const resposta = await client.statementExecution.executeStatement({
      warehouse_id: await getWarehouseId(),
      statement: SQL,
      wait_timeout: '30s',
    });
    if (resposta.status?.state !== 'SUCCEEDED') {
      return { disponivel: false, motivo: resposta.status?.error?.message ?? resposta.status?.state, linhas: [] };
    }
    const colunas = (resposta.manifest?.schema?.columns ?? []).map((c) => c.name ?? '');
    const linhas = (resposta.result?.data_array ?? []).map((linha) =>
      Object.fromEntries(colunas.map((coluna, i) => [coluna, linha[i] ?? null])),
    );
    return { disponivel: linhas.length > 0, linhas };
  } catch (erro) {
    return { disponivel: false, motivo: erro instanceof Error ? erro.message : String(erro), linhas: [] };
  }
}
