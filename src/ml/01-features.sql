-- ml.features_projeto_semana: a matéria-prima do modelo de estouro em 30 dias.
--
-- Uma linha por projeto e sexta-feira (4.235). Com 60 projetos não existe ML: com
-- 4.235 sextas-feiras de projeto, existe. Cada sexta é uma foto, e o rótulo é o que
-- veio depois.
--
-- A regra de ouro: toda FEATURE olha só para trás (lag, PRECEDING, datas até a sexta).
-- Os dois ALVOS olham para a frente (FOLLOWING) e nunca entram no modelo como feature.
-- O "hoje" é 2026-10-16. A sql_task corta o arquivo em todo ponto e vírgula, então ele
-- só aparece no fim de cada comando.


CREATE SCHEMA IF NOT EXISTS lakehouse_vertice.ml
COMMENT 'O laboratório do cientista de dados: as features, as métricas e o modelo de estouro em 30 dias. Na gold fica só o resultado (score_estouro_30d).';


CREATE OR REPLACE TABLE lakehouse_vertice.ml.features_projeto_semana
COMMENT 'Features do modelo de estouro em 30 dias: uma linha por projeto e sexta-feira. Toda feature olha só para trás. alvo_pior_indice_30d e estoura_30d olham as 4 semanas SEGUINTES e nunca entram como feature (NULL quando ainda não há 4 semanas de futuro). elegivel = 1 quando o projeto ainda está acima do corte e faz sentido prever.'
AS
WITH base AS (
  SELECT
    f.projeto_id,
    f.semana,
    p.segmento,
    p.status,
    p.data_inicio,
    p.data_fim_baseline,
    CAST(p.orcamento AS DOUBLE)          AS orcamento,
    CAST(f.pv AS DOUBLE)                 AS pv,
    CAST(f.ev AS DOUBLE)                 AS ev,
    CAST(f.ac AS DOUBLE)                 AS ac,
    CAST(f.spi AS DOUBLE)                AS spi,
    CAST(f.cpi AS DOUBLE)                AS cpi,
    CAST(least(f.spi, f.cpi) AS DOUBLE)  AS indice_min,
    f.farol_do_gerente,
    coalesce(f.horas_disponiveis, 0)     AS horas_disponiveis,
    coalesce(f.horas_ociosas, 0)         AS horas_ociosas
  FROM lakehouse_vertice.gold.fato_projeto_semana f
  JOIN lakehouse_vertice.gold.projeto_situacao_atual p USING (projeto_id)
),

-- o custo da semana por categoria (a semana do custo já é a sexta, como no fato)
custo_semana AS (
  SELECT
    projeto_id,
    semana,
    SUM(valor)                                             AS custo,
    -- sem lançamento da categoria, fica nulo (não zero): "não houve" não é "custou 0%"
    SUM(CASE WHEN categoria = 'consultoria' THEN valor END) AS custo_consultoria,
    SUM(CASE WHEN categoria = 'cloud'       THEN valor END) AS custo_cloud
  FROM lakehouse_vertice.silver.custos
  GROUP BY projeto_id, semana
),

-- quem passou pelo projeto (aparece no timesheet dele) e quando se desligou da empresa
pessoas_do_projeto AS (
  SELECT DISTINCT a.projeto_id, a.colaborador_id, c.data_desligamento
  FROM lakehouse_vertice.silver.apontamentos a
  JOIN lakehouse_vertice.silver.colaboradores c USING (colaborador_id)
  WHERE c.data_desligamento IS NOT NULL
),

-- os sinais que só existem em agregação com data: saídas e causas do status
saidas AS (
  SELECT b.projeto_id, b.semana, COUNT(DISTINCT pp.colaborador_id) AS saidas_12s
  FROM base b
  JOIN pessoas_do_projeto pp
    ON pp.projeto_id = b.projeto_id
   AND pp.data_desligamento >  date_sub(b.semana, 84)
   AND pp.data_desligamento <= b.semana
  GROUP BY b.projeto_id, b.semana
),

status_4s AS (
  SELECT
    b.projeto_id,
    b.semana,
    COUNT_IF(s.causa_bloqueio = 'change_freeze')                           AS status_freeze_4s,
    COUNT_IF(s.causa_bloqueio = 'falta_sre')                               AS status_falta_sre_4s,
    COUNT_IF(s.causa_bloqueio = 'dependencia_fornecedor')                  AS status_fornecedor_4s,
    COUNT_IF(s.causa_bloqueio = 'rotatividade')                            AS status_rotatividade_4s,
    COUNT_IF(s.causa_bloqueio = 'mudanca_escopo')                          AS status_escopo_4s,
    COUNT_IF(s.causa_bloqueio = 'bug_retrabalho')                          AS status_retrabalho_4s,
    COUNT_IF(s.causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado'))    AS status_com_bloqueio_4s
  FROM base b
  JOIN lakehouse_vertice.gold.status_estruturado s
    ON s.projeto_id = b.projeto_id
   AND s.data_status >  date_sub(b.semana, 28)
   AND s.data_status <= b.semana
  GROUP BY b.projeto_id, b.semana
),

-- primeiro as defasagens (janela num CTE: janela dentro de agregação quebra)
com_lags AS (
  SELECT
    b.*,
    coalesce(cs.custo, 0)             AS custo,
    cs.custo_consultoria,
    cs.custo_cloud,
    lag(b.spi, 4)        OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS spi_4s_atras,
    lag(b.cpi, 4)        OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS cpi_4s_atras,
    lag(b.spi, 8)        OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS spi_8s_atras,
    lag(b.cpi, 8)        OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS cpi_8s_atras,
    lag(b.indice_min, 4) OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS indice_min_4s_atras,
    lag(b.cpi, 1)        OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS cpi_semana_anterior,
    lag(b.pv, 4)         OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS pv_4s_atras,
    lag(b.ev, 4)         OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS ev_4s_atras,
    lag(b.ac, 4)         OVER (PARTITION BY b.projeto_id ORDER BY b.semana) AS ac_4s_atras
  FROM base b
  LEFT JOIN custo_semana cs
    ON cs.projeto_id = b.projeto_id AND cs.semana = b.semana
),

-- depois as janelas das últimas 4 semanas (por extenso: janela nomeada com frame dá erro)
com_janelas AS (
  SELECT
    *,
    SUM(CASE WHEN cpi < cpi_semana_anterior THEN 1 ELSE 0 END)
      OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS semanas_cpi_caindo,
    SUM(horas_ociosas)     OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS ociosas_4s,
    SUM(horas_disponiveis) OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS disponiveis_4s,
    SUM(custo)             OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS custo_4s,
    SUM(custo_consultoria) OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS consultoria_4s,
    SUM(custo_cloud)       OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS cloud_4s,
    -- os ALVOS: o futuro, só para o rótulo
    COUNT(*)        OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 1 FOLLOWING AND 4 FOLLOWING) AS semanas_de_futuro,
    MIN(indice_min) OVER (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN 1 FOLLOWING AND 4 FOLLOWING) AS pior_indice_futuro
  FROM com_lags
)

SELECT
  j.projeto_id,
  j.semana,
  j.segmento,
  j.farol_do_gerente,

  -- o índice e como ele andou
  j.spi,
  j.cpi,
  j.indice_min,
  j.spi - j.spi_4s_atras                                   AS d_spi_4s,
  j.cpi - j.cpi_4s_atras                                   AS d_cpi_4s,
  j.spi - j.spi_8s_atras                                   AS d_spi_8s,
  j.cpi - j.cpi_8s_atras                                   AS d_cpi_8s,
  j.indice_min - j.indice_min_4s_atras                     AS d_indice_min_4s,
  CAST(j.semanas_cpi_caindo AS DOUBLE)                     AS semanas_cpi_caindo,

  -- o ritmo do último mês (o acumulado anda devagar, o ritmo não)
  try_divide(j.ev - j.ev_4s_atras, j.ac - j.ac_4s_atras)   AS cpi_ultimas_4s,
  try_divide(j.ev - j.ev_4s_atras, j.pv - j.pv_4s_atras)   AS spi_ultimas_4s,

  -- o avanço físico e o do prazo
  try_divide(j.ev, j.orcamento)                            AS pct_fisico,
  try_divide(CAST(datediff(j.semana, j.data_inicio) AS DOUBLE),
             CAST(datediff(j.data_fim_baseline, j.data_inicio) AS DOUBLE)) AS pct_prazo,

  -- pessoas e custo
  try_divide(j.ociosas_4s, j.disponiveis_4s)               AS ociosidade_4s,
  try_divide(j.consultoria_4s, j.custo_4s)                 AS pct_consultoria_4s,
  try_divide(j.cloud_4s, j.custo_4s)                       AS pct_cloud_4s,
  CAST(coalesce(sa.saidas_12s, 0) AS DOUBLE)               AS saidas_12s,

  -- o que o gerente escreveu nos últimos 28 dias (a IA da noite 3 classificou)
  CAST(coalesce(st.status_freeze_4s, 0) AS DOUBLE)         AS status_freeze_4s,
  CAST(coalesce(st.status_falta_sre_4s, 0) AS DOUBLE)      AS status_falta_sre_4s,
  CAST(coalesce(st.status_fornecedor_4s, 0) AS DOUBLE)     AS status_fornecedor_4s,
  CAST(coalesce(st.status_rotatividade_4s, 0) AS DOUBLE)   AS status_rotatividade_4s,
  CAST(coalesce(st.status_escopo_4s, 0) AS DOUBLE)         AS status_escopo_4s,
  CAST(coalesce(st.status_retrabalho_4s, 0) AS DOUBLE)     AS status_retrabalho_4s,
  CAST(coalesce(st.status_com_bloqueio_4s, 0) AS DOUBLE)   AS status_com_bloqueio_4s,

  -- faz sentido prever? (ainda acima do corte, projeto maduro, sem estar no fim)
  CASE
    WHEN j.spi >= 0.9 AND j.cpi >= 0.9
     AND datediff(j.semana, j.data_inicio) >= 84
     AND j.ev < 0.98 * j.orcamento
     AND (j.status = 'em_andamento' OR j.semana < DATE'2026-10-16')
    THEN 1 ELSE 0
  END                                                      AS elegivel,

  -- os ALVOS (o futuro): NULL quando ainda não há 4 semanas pela frente
  CASE WHEN j.semanas_de_futuro = 4 THEN j.pior_indice_futuro END AS alvo_pior_indice_30d,
  CASE WHEN j.semanas_de_futuro = 4 THEN CASE WHEN j.pior_indice_futuro < 0.9 THEN 1 ELSE 0 END END AS estoura_30d
FROM com_janelas j
LEFT JOIN saidas sa    ON sa.projeto_id = j.projeto_id AND sa.semana = j.semana
LEFT JOIN status_4s st ON st.projeto_id = j.projeto_id AND st.semana = j.semana;


-- a conferência: linhas, treino, taxa base e as linhas de hoje (sem alvo)
SELECT
  COUNT(*)                                                          AS linhas,
  COUNT_IF(elegivel = 1 AND estoura_30d IS NOT NULL)                AS treino,
  ROUND(AVG(CASE WHEN elegivel = 1 THEN estoura_30d END), 3)        AS taxa_base,
  COUNT_IF(semana = DATE'2026-10-16')                               AS linhas_de_hoje,
  COUNT_IF(semana = DATE'2026-10-16' AND alvo_pior_indice_30d IS NOT NULL) AS alvo_preenchido_hoje
FROM lakehouse_vertice.ml.features_projeto_semana;
