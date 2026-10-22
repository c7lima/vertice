-- gold.fato_projeto_semana: O FILME. Uma linha por projeto e semana (sexta-feira),
-- da semana do início até hoje (2026-10-16).
--
-- De onde vem o histórico? Excel, ClickUp e Project só guardam o % de HOJE. O único
-- lugar com o % de cada semana é o status semanal que o gerente publica toda sexta.
-- PV, EV e AC são ACUMULADOS: nunca se soma EV de semanas diferentes do mesmo projeto.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo     EXPECT (pv >= 0)          ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_o_orcamento  EXPECT (ev <= orcamento)  ON VIOLATION FAIL UPDATE
)
COMMENT 'O filme: uma linha por projeto e semana (sexta-feira), do início do projeto até 2026-10-16. PV, EV e AC acumulados até a semana, SPI, CPI e EAC, o farol do gerente e as horas do timesheet. O % de cada semana vem do status semanal.'
AS
WITH semanas AS (
  SELECT
    p.projeto_id,
    p.orcamento,
    p.data_inicio,
    p.data_fim_baseline,
    explode(sequence(
      date_add(date_trunc('WEEK', p.data_inicio), 4),     -- a sexta da semana do início
      DATE'2026-10-16',
      INTERVAL 1 WEEK
    )) AS semana
  FROM projetos p
),

-- o status daquela sexta; projeto concluído para de publicar, então o último % e o
-- último farol valem para as semanas seguintes (a janela fica num CTE: janela dentro
-- de agregação dá erro no pipeline)
com_status AS (
  SELECT
    s.*,
    last_value(st.pct_concluido, true) OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS pct_concluido,
    last_value(st.farol, true)         OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS farol_do_gerente
  FROM semanas s
  LEFT JOIN status_semanal st
    ON st.projeto_id = s.projeto_id AND st.data_status = s.semana
),

-- custo real acumulado: tudo que foi lançado até aquela semana
custo_acumulado AS (
  SELECT
    s.projeto_id,
    s.semana,
    coalesce(SUM(c.valor), 0) AS ac
  FROM semanas s
  LEFT JOIN custos c
    ON c.projeto_id = s.projeto_id AND c.data <= s.semana
  GROUP BY s.projeto_id, s.semana
),

horas_da_semana AS (
  SELECT
    projeto_id,
    semana,
    SUM(horas_disponiveis)                   AS horas_disponiveis,
    SUM(horas_apontadas)                     AS horas_apontadas,
    SUM(horas_disponiveis - horas_apontadas) AS horas_ociosas
  FROM apontamentos
  GROUP BY projeto_id, semana
),

kpis AS (
  SELECT
    cs.projeto_id,
    cs.semana,
    cs.orcamento,
    -- PV: quanto do orçamento já deveria estar feito, pela fração do baseline decorrida
    CAST(cs.orcamento * greatest(0, least(1,
      try_divide(datediff(cs.semana, cs.data_inicio), datediff(cs.data_fim_baseline, cs.data_inicio))
    )) AS DECIMAL(18,2))                                    AS pv,
    -- EV: quanto do orçamento está feito, pelo % do status daquela sexta
    CAST(cs.orcamento * coalesce(cs.pct_concluido, 0) / 100 AS DECIMAL(18,2)) AS ev,
    ca.ac,
    cs.pct_concluido,
    cs.farol_do_gerente,
    h.horas_disponiveis,
    h.horas_apontadas,
    h.horas_ociosas
  FROM com_status cs
  JOIN custo_acumulado ca
    ON ca.projeto_id = cs.projeto_id AND ca.semana = cs.semana
  LEFT JOIN horas_da_semana h
    ON h.projeto_id = cs.projeto_id AND h.semana = cs.semana
)

SELECT
  projeto_id,
  semana,
  orcamento,
  pv,
  ev,
  ac,
  round(try_divide(ev, pv), 4)                         AS spi,
  round(try_divide(ev, ac), 4)                         AS cpi,
  CAST(try_divide(orcamento, round(try_divide(ev, ac), 4)) AS DECIMAL(18,2)) AS eac,
  pct_concluido,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  horas_ociosas
FROM kpis
