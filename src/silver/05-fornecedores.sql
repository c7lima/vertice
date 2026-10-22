-- silver.entregas_fornecedor: o que cada consultoria prometeu e quando entregou.
--
-- A mesma consultoria vem escrita de 4 jeitos ('CodeForge Consultoria Ltda',
-- 'Codeforge Consultoria', 'CODEFORGE CONSULTORIA LTDA', 'Code Forge Consultoria'):
-- vira um fornecedor só, com o original guardado em fornecedor_como_veio.
-- Data de entrega vazia é entrega em aberto (não é sujeira).

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias (640): prometido × entregue, prazos em dias e atraso. A CodeForge de 4 grafias vira 1 fornecedor. em_atraso = em aberto com a data prometida antes de 2026-10-16. Lida direto pelo dashboard e pelo Genie (não há tabela gold de fornecedor).'
AS
WITH limpo AS (
  SELECT
    entrega_id,
    projeto_id,
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor
    END                                          AS fornecedor,
    fornecedor                                   AS fornecedor_como_veio,
    item,
    CAST(valor AS DECIMAL(18,2))                 AS valor,
    to_date(data_pedido)                         AS data_pedido,
    to_date(data_prometida)                      AS data_prometida,
    to_date(nullif(trim(data_entrega), ''))      AS data_entrega,
    CAST(prazo_contratado_dias AS INT)           AS prazo_contratado_dias,
    status
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  *,
  datediff(data_prometida, data_pedido)          AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)            AS prazo_real_dias,
  datediff(data_entrega, data_prometida)         AS dias_de_atraso_na_entrega,
  data_entrega IS NULL                           AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16' AS em_atraso
FROM limpo
