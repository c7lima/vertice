-- Conferência da bronze: as 9 tabelas chegaram inteiras?
--
-- Roda depois das duas ingestões, antes do medalhão. Uma linha por tabela, com o
-- esperado (seed 42) e o obtido. Se alguma divergir, raise_error() para o job aqui:
-- melhor parar do que recalcular a silver e a gold com meio dado.
-- bronze.feriados fica de fora: ela cresce a cada execução da API.

WITH esperado AS (
  SELECT * FROM VALUES
    ('projetos',            60),
    ('status_semanal',      3911),
    ('excel_tarefas',       1663),
    ('clickup_tarefas',     2119),
    ('msproject_tarefas',   1260),
    ('colaboradores',       523),
    ('apontamentos',        30883),
    ('custos',              23640),
    ('entregas_fornecedor', 640)
  AS t(tabela, esperado)
),

obtido AS (
  SELECT 'projetos'            AS tabela, COUNT(*) AS obtido FROM lakehouse_vertice.bronze.projetos            UNION ALL
  SELECT 'status_semanal',                COUNT(*)           FROM lakehouse_vertice.bronze.status_semanal      UNION ALL
  SELECT 'excel_tarefas',                 COUNT(*)           FROM lakehouse_vertice.bronze.excel_tarefas       UNION ALL
  SELECT 'clickup_tarefas',               COUNT(*)           FROM lakehouse_vertice.bronze.clickup_tarefas     UNION ALL
  SELECT 'msproject_tarefas',             COUNT(*)           FROM lakehouse_vertice.bronze.msproject_tarefas   UNION ALL
  SELECT 'colaboradores',                 COUNT(*)           FROM lakehouse_vertice.bronze.colaboradores       UNION ALL
  SELECT 'apontamentos',                  COUNT(*)           FROM lakehouse_vertice.bronze.apontamentos        UNION ALL
  SELECT 'custos',                        COUNT(*)           FROM lakehouse_vertice.bronze.custos              UNION ALL
  SELECT 'entregas_fornecedor',           COUNT(*)           FROM lakehouse_vertice.bronze.entregas_fornecedor
)

SELECT
  e.tabela,
  e.esperado,
  o.obtido,
  CASE
    WHEN o.obtido = e.esperado THEN 'ok'
    ELSE raise_error(concat(
      'bronze.', e.tabela, ': esperado ', e.esperado, ', obtido ', o.obtido,
      '. Olhe a saída da tarefa ingestao_data_lake.'))
  END AS resultado
FROM esperado e
JOIN obtido o USING (tabela)
ORDER BY e.tabela
