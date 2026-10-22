-- silver.tarefas: AS TRÊS FERRAMENTAS VIRAM UMA.
--
-- A integração é um contrato de colunas: cada ferramenta vira uma visão temporária
-- com as MESMAS 13 colunas, e a tabela é o UNION ALL das três. Uma ferramenta nova
-- amanhã é só mais uma visão.
--
--   projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
--   inicio_baseline, fim_baseline, inicio_real, fim_real,
--   pct_como_veio, horas, status_na_ferramenta


-- ── Excel: 20 planilhas, tudo texto ───────────────────────────────────────
-- Data: com '/' é dd/MM/yyyy; sem '/' é o número de série do Excel (dias desde 1899-12-30).
-- %: '45%' ou '10,5%' (tira o % e troca a vírgula) ou 0.45 (fração: × 100).
-- Horas: '40h' (tira o h). A linha de TOTAL no fim da planilha SAI.
CREATE TEMPORARY VIEW tarefas_excel AS
SELECT
  -- o de-para casa pelo nome do arquivo; se não casar (código vazio ou o arquivo
  -- chegou sem acento), o PRJ-xxx está no próprio nome do arquivo
  coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
  'excel'                                                                AS ferramenta,
  e.id                                                                   AS id_na_ferramenta,
  e.fase,
  e.tarefa,
  e.responsavel,
  CASE WHEN contains(e.inicio_previsto, '/') THEN to_date(e.inicio_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(nullif(trim(e.inicio_previsto), '') AS DOUBLE) AS INT))
  END                                                                    AS inicio_baseline,
  CASE WHEN contains(e.termino_previsto, '/') THEN to_date(e.termino_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(nullif(trim(e.termino_previsto), '') AS DOUBLE) AS INT))
  END                                                                    AS fim_baseline,
  CASE WHEN contains(e.inicio_real, '/') THEN to_date(e.inicio_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(nullif(trim(e.inicio_real), '') AS DOUBLE) AS INT))
  END                                                                    AS inicio_real,
  CASE WHEN contains(e.termino_real, '/') THEN to_date(e.termino_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(nullif(trim(e.termino_real), '') AS DOUBLE) AS INT))
  END                                                                    AS fim_real,
  CASE WHEN contains(e.pct_concluido, '%')
       THEN CAST(replace(replace(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(nullif(trim(e.pct_concluido), '') AS DOUBLE) * 100
  END                                                                    AS pct_como_veio,
  CAST(replace(e.horas_previstas, 'h', '') AS DOUBLE)                    AS horas,
  CAST(NULL AS STRING)                                                   AS status_na_ferramenta   -- a planilha não tem status
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN projetos p
  ON p.ferramenta = 'excel' AND p.codigo_ferramenta = e.arquivo
WHERE e.tarefa <> 'TOTAL';


-- ── ClickUp: 25 listas exportadas em JSON ─────────────────────────────────
-- Datas em milissegundos. O % e o baseline estão dentro de custom_fields (uma lista).
-- Horas em time_estimate (milissegundos). Status escrito de 12 jeitos.
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  -- o de-para casa pelo list_id; se o código faltar no cadastro, casa pelo nome da lista
  coalesce(p.projeto_id, pn.projeto_id)                                                AS projeto_id,
  'clickup'                                                                            AS ferramenta,
  c.id                                                                                 AS id_na_ferramenta,
  filter(c.custom_fields, f -> f.name = 'Fase')[0].value                               AS fase,
  c.name                                                                               AS tarefa,
  c.assignees[0].username                                                              AS responsavel,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))) AS inicio_baseline,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT)))    AS fim_baseline,
  to_date(timestamp_millis(CAST(c.start_date AS BIGINT)))                              AS inicio_real,
  to_date(timestamp_millis(CAST(c.date_done  AS BIGINT)))                              AS fim_real,
  CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE)      AS pct_como_veio,
  c.time_estimate / 3600000                                                            AS horas,
  CASE
    WHEN lower(c.status.status) IN ('done', 'closed', 'concluído')                     THEN 'concluida'
    WHEN lower(c.status.status) IN ('to do', 'a fazer', 'backlog')                     THEN 'a_fazer'
    WHEN lower(c.status.status) IN ('in progress', 'doing', 'em andamento', 'review')  THEN 'em_andamento'
  END                                                                                  AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos p
  ON p.ferramenta = 'clickup' AND p.codigo_ferramenta = c.list_id
LEFT JOIN projetos pn
  ON pn.ferramenta = 'clickup' AND pn.codigo_ferramenta IS NULL AND startswith(c.list_name, pn.nome_projeto);


-- ── MS Project: 15 cronogramas em XML ─────────────────────────────────────
-- As tarefas-resumo (Summary = 1) somam as horas das de baixo: SAEM.
-- A fase não está na tarefa: é a última tarefa-resumo de nível 1 antes dela.
-- Horas em 'PT40H0M0S'.
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH com_fase AS (
  SELECT
    m.*,
    last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
      OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT
  p.projeto_id,
  'msproject'                                                    AS ferramenta,
  CAST(f.UID AS STRING)                                          AS id_na_ferramenta,
  f.fase,
  f.Name                                                         AS tarefa,
  CAST(NULL AS STRING)                                           AS responsavel,           -- o XML não traz o recurso
  to_date(f.Baseline.Start)                                      AS inicio_baseline,
  to_date(f.Baseline.Finish)                                     AS fim_baseline,
  to_date(f.ActualStart)                                         AS inicio_real,
  to_date(f.ActualFinish)                                        AS fim_real,
  CAST(f.PercentComplete AS DOUBLE)                              AS pct_como_veio,
  CAST(regexp_extract(f.Work, 'PT([0-9]+)H', 1) AS DOUBLE)       AS horas,
  CAST(NULL AS STRING)                                           AS status_na_ferramenta   -- o Project não tem status
FROM com_fase f
LEFT JOIN projetos p
  ON p.ferramenta = 'msproject' AND p.codigo_ferramenta = f.arquivo
WHERE f.Summary = 0;


-- ── a tabela: as três empilhadas ──────────────────────────────────────────
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto   EXPECT (projeto_id IS NOT NULL)            ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas   EXPECT (horas > 0)                         ON VIOLATION FAIL UPDATE
)
COMMENT 'As tarefas das 3 ferramentas (Excel, ClickUp e MS Project) num modelo só: uma linha por tarefa (4.917). Sem a linha de TOTAL do Excel e sem as tarefas-resumo do Project. pct_concluido cortado em 100, com a flag pct_veio_acima_de_100.'
AS
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  *,
  least(pct_como_veio, 100)                                AS pct_concluido,
  pct_como_veio > 100                                      AS pct_veio_acima_de_100
FROM (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
