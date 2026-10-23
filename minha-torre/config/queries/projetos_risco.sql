-- Os projetos em andamento, do pior para o melhor, com a causa que o gerente escreveu
-- no status dos últimos 90 dias (a IA da noite 3 classificou) e os dias de impacto.
WITH causas AS (
  SELECT projeto_id, causa_bloqueio, COUNT(*) AS semanas, SUM(coalesce(dias_impacto, 0)) AS dias_impacto
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= DATE'2026-07-18'
    AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
  GROUP BY projeto_id, causa_bloqueio
),
por_projeto AS (
  SELECT
    projeto_id,
    max_by(causa_bloqueio, semanas)                                              AS causa_principal,
    SUM(CASE WHEN causa_bloqueio = 'falta_sre'    THEN dias_impacto ELSE 0 END)  AS dias_falta_sre,
    SUM(CASE WHEN causa_bloqueio = 'rotatividade' THEN dias_impacto ELSE 0 END)  AS dias_rotatividade
  FROM causas
  GROUP BY projeto_id
)
SELECT
  p.projeto_id, p.nome_projeto, p.cliente, p.situacao,
  p.spi, p.cpi, p.estouro_previsto, p.atraso_projetado_dias,
  p.farol_do_gerente, p.farol_calculado, p.melancia,
  c.causa_principal,
  coalesce(c.dias_falta_sre, 0)    AS dias_falta_sre,
  coalesce(c.dias_rotatividade, 0) AS dias_rotatividade
FROM lakehouse_vertice.gold.projeto_situacao_atual p
LEFT JOIN por_projeto c USING (projeto_id)
WHERE p.status = 'em_andamento'
ORDER BY least(p.spi, p.cpi), p.projeto_id
