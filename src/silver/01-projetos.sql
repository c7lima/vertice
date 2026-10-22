-- silver.projetos: o cadastro do PMO, limpo.
--
-- É o DE-PARA da integração: diz em qual ferramenta cada projeto vive e com qual
-- código (o arquivo do Excel ou do Project, ou o list_id do ClickUp).
-- Sujeiras resolvidas aqui: data de início em 2 formatos, ferramenta escrita de
-- 8 jeitos e código da ferramenta vazio.

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida   EXPECT (data_inicio IS NOT NULL)                        ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro do PMO limpo: uma linha por projeto (60). É o de-para da integração: ferramenta (excel, clickup, msproject) e codigo_ferramenta (arquivo do Excel/Project ou list_id do ClickUp).'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,

  -- 'Excel', 'Planilha', 'click up', 'MS Project'... viram 3 valores
  CASE
    WHEN lower(ferramenta) LIKE '%click%'                                       THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
    WHEN lower(ferramenta) LIKE '%project%'                                     THEN 'msproject'
  END                                    AS ferramenta,
  ferramenta                             AS ferramenta_como_veio,
  nullif(trim(codigo_ferramenta), '')    AS codigo_ferramenta,

  CAST(valor_contrato  AS DECIMAL(18,2)) AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(18,2)) AS orcamento,

  -- a data vem em yyyy-MM-dd ou dd/MM/yyyy: tenta os dois
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'),
           try_to_date(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
  to_date(data_fim_baseline)             AS data_fim_baseline,
  status,
  gerente_projeto
FROM lakehouse_vertice.bronze.projetos
