-- Os KPIs da tela "Projetos em risco": a carteira em andamento hoje (16/10/2026)
-- e quantos projetos o modelo põe em alto risco nos próximos 30 dias.
SELECT
  COUNT(*)                                     AS projetos_em_andamento,
  COUNT_IF(situacao IN ('atenção', 'crítico')) AS projetos_em_risco,
  COUNT_IF(situacao = 'crítico')               AS projetos_criticos,
  COUNT_IF(melancia)                           AS projetos_melancia,
  SUM(estouro_previsto)                        AS estouro_previsto,
  SUM(valor_contrato)                          AS carteira,
  (SELECT COUNT_IF(faixa_risco = 'alto')
   FROM lakehouse_vertice.gold.score_estouro_30d
   WHERE data_referencia = (SELECT MAX(data_referencia) FROM lakehouse_vertice.gold.score_estouro_30d)
  )                                            AS alto_risco_30d
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
