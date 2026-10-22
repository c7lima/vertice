-- silver.status_semanal e silver.custos.


-- ── status_semanal: o status que o gerente publica toda sexta ─────────────
-- Farol escrito de 3 jeitos ('Verde', 'VERDE', 'verde'). Status vazio
-- ('', 'N/A', 'ver ata da reunião') NÃO é descartado: ganha a flag status_vazio.
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal de cada projeto (toda sexta): % concluído, farol do gerente padronizado e o texto livre com os bloqueios. Uma linha por projeto e sexta (3.911). status_vazio marca os 51 textos sem conteúdo.'
AS
SELECT
  projeto_id,
  to_date(data_status)               AS data_status,
  gerente,
  lower(trim(farol))                 AS farol,
  CAST(pct_concluido AS INT)         AS pct_concluido,
  texto_status,
  coalesce(trim(texto_status), '') IN ('', 'N/A', 'ver ata da reunião') AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;


-- ── custos: cada lançamento de custo real ─────────────────────────────────
-- 671 valores com vírgula decimal ('12345,67'): replace ANTES do CAST.
-- try_cast devolveria nulo e jogaria R$ 5,4 mi fora em silêncio.
-- Estorno (valor negativo) FICA: o custo é líquido. Só ganha a flag estorno.
CREATE OR REFRESH MATERIALIZED VIEW custos (
  CONSTRAINT valor_preenchido EXPECT (valor IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Lançamentos de custo real por projeto (23.640): pessoal, consultoria, cloud, licenças e despesas. Vírgula decimal recuperada (valor_veio_com_virgula) e estornos mantidos (estorno). O total é o mesmo da bronze: R$ 193,35 mi.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(data)                                  AS data,
  date_add(date_trunc('WEEK', to_date(data)), 4) AS semana,         -- a sexta da semana
  categoria,
  descricao,
  CAST(replace(valor, ',', '.') AS DECIMAL(18,2)) AS valor,
  contains(valor, ',')                           AS valor_veio_com_virgula,
  CAST(replace(valor, ',', '.') AS DECIMAL(18,2)) < 0 AS estorno,
  centro_custo
FROM lakehouse_vertice.bronze.custos
