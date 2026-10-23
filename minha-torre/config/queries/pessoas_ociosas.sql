-- Gente parada: utilização abaixo de 20% nas últimas 12 semanas, com as horas paradas
-- e o custo ocioso MÉDIOS por semana (o simulador multiplica por 4 para dar o mês).
WITH uso AS (
  SELECT
    colaborador_id, nome, papel, senioridade, projeto_id,
    SUM(horas_apontadas) / SUM(horas_disponiveis) AS utilizacao,
    SUM(horas_ociosas)  / COUNT(DISTINCT semana)  AS horas_paradas_semana,
    SUM(custo_ocioso)   / COUNT(DISTINCT semana)  AS custo_ocioso_semana
  FROM lakehouse_vertice.gold.utilizacao_pessoa_semana
  WHERE semana > DATE'2026-07-24'
  GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
  HAVING SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2
)
SELECT u.*, c.custo_hora
FROM uso u
JOIN lakehouse_vertice.silver.colaboradores c USING (colaborador_id)
ORDER BY u.custo_ocioso_semana DESC
