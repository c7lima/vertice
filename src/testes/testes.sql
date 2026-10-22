-- Os 10 testes de qualidade: melhor o job falhar do que o diretor ver número errado.
--
-- Rodam depois do medalhão, como tarefa do job. Cada teste é uma linha; se falhar,
-- raise_error() para o job e diz qual teste quebrou. O EXPECT do pipeline olha UMA
-- linha de cada vez; o teste olha a tabela INTEIRA ("a soma bate", "são 60").

WITH testes AS (

  -- ── integração ──────────────────────────────────────────────────────
  SELECT 1 AS n, 'os 60 projetos têm cronograma na silver.tarefas' AS teste,
         (SELECT COUNT(DISTINCT projeto_id) FROM lakehouse_vertice.silver.tarefas) = 60 AS passou

  UNION ALL
  SELECT 2, 'cada projeto veio de UMA ferramenta, a do cadastro do PMO',
         (SELECT COUNT(*) FROM (
            SELECT t.projeto_id
            FROM lakehouse_vertice.silver.tarefas t
            JOIN lakehouse_vertice.silver.projetos p ON p.projeto_id = t.projeto_id
            GROUP BY t.projeto_id
            HAVING COUNT(DISTINCT t.ferramenta) <> 1 OR MAX(t.ferramenta) <> MAX(p.ferramenta)
         )) = 0

  -- ── conservação ─────────────────────────────────────────────────────
  UNION ALL
  SELECT 3, 'as horas do Excel na silver = a soma das linhas de TOTAL das planilhas',
         abs(
           (SELECT SUM(horas) FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel')
           - (SELECT SUM(CAST(replace(horas_previstas, 'h', '') AS DOUBLE))
              FROM lakehouse_vertice.bronze.excel_tarefas WHERE tarefa = 'TOTAL')
         ) < 0.01

  -- ── unicidade ───────────────────────────────────────────────────────
  UNION ALL
  SELECT 4, 'uma linha por pessoa na silver',
         (SELECT COUNT(*) = COUNT(DISTINCT colaborador_id) FROM lakehouse_vertice.silver.colaboradores)

  UNION ALL
  SELECT 5, 'a CodeForge virou um fornecedor só',
         (SELECT COUNT(DISTINCT fornecedor) FROM lakehouse_vertice.silver.entregas_fornecedor
          WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%') = 1

  -- ── conservação ─────────────────────────────────────────────────────
  UNION ALL
  SELECT 6, 'a limpeza não mudou o custo total (bronze com replace = silver)',
         (SELECT SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) FROM lakehouse_vertice.bronze.custos)
         = (SELECT SUM(valor) FROM lakehouse_vertice.silver.custos)

  -- ── completude ──────────────────────────────────────────────────────
  UNION ALL
  SELECT 7, 'os 60 projetos têm fotografia de hoje',
         (SELECT COUNT(*) FROM lakehouse_vertice.gold.projeto_situacao_atual) = 60

  UNION ALL
  SELECT 8, 'todo projeto em andamento tem SPI e CPI',
         (SELECT COUNT(*) FROM lakehouse_vertice.gold.projeto_situacao_atual
          WHERE status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL)) = 0

  -- ── coerência: a fotografia e o filme contam a mesma história hoje ──
  UNION ALL
  SELECT 9, 'o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)',
         abs(
           (SELECT SUM(ev) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
           / (SELECT SUM(ev) FROM lakehouse_vertice.gold.projeto_situacao_atual) - 1
         ) < 0.01

  UNION ALL
  SELECT 10, 'AC de hoje no fato = soma dos lançamentos até hoje',
         (SELECT SUM(ac) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
         = (SELECT SUM(valor) FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16')
)

SELECT
  n,
  teste,
  CASE WHEN passou THEN 'ok'
       ELSE raise_error(concat('Teste ', n, ' falhou: ', teste))
  END AS resultado
FROM testes
ORDER BY n
