-- silver.colaboradores e silver.apontamentos.


-- ── colaboradores: as 520 pessoas ─────────────────────────────────────────
-- COL0102, COL0257 e COL0433 aparecem duas vezes no RH (a cópia vem com nome e
-- papel em CAIXA ALTA). Fica o cadastro com o papel em minúsculas.
CREATE OR REFRESH MATERIALIZED VIEW colaboradores (
  CONSTRAINT custo_hora_positivo EXPECT (custo_hora > 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro de pessoas do RH sem duplicidade: uma linha por colaborador (520). Papel, senioridade, custo/hora, admissão e desligamento.'
AS
WITH numerado AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY colaborador_id
      ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END   -- o cadastro em minúsculas primeiro
    ) AS linha
  FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  CAST(custo_hora AS DECIMAL(10,2))  AS custo_hora,
  to_date(data_admissao)             AS data_admissao,
  to_date(nullif(trim(data_desligamento), '')) AS data_desligamento
FROM numerado
WHERE linha = 1;


-- ── apontamentos: o timesheet semanal ─────────────────────────────────────
-- Horas disponíveis × horas apontadas por pessoa, projeto e semana.
-- A semana é a sexta (semana_inicio + 4), a mesma do status semanal.
CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e apontadas por pessoa, projeto e semana (sexta-feira). Uma linha por pessoa, projeto e semana (30.883).'
AS
SELECT
  colaborador_id,
  projeto_id,
  to_date(semana_inicio)                AS semana_inicio,
  date_add(to_date(semana_inicio), 4)   AS semana,
  CAST(horas_disponiveis AS DOUBLE)     AS horas_disponiveis,
  CAST(horas_apontadas   AS DOUBLE)     AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos
