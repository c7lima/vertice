-- gold.projeto_situacao_atual (A FOTOGRAFIA) e gold.utilizacao_pessoa_semana (AS PESSOAS).


-- ── projeto_situacao_atual: cada projeto em 2026-10-16 ────────────────────
-- Perguntas 1 e 2 do dono: quem atrasa, de qual cliente, quanto custa.
-- O % de hoje vem das ferramentas (silver.tarefas): é mais preciso que o status.
-- Tabela larga de propósito: já traz o cadastro, sem dim_projeto.
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual
COMMENT 'A fotografia de hoje (2026-10-16): uma linha por projeto (60), com o cadastro (cliente, segmento, gerente, contrato, prazo) e os KPIs calculados sobre as tarefas das 3 ferramentas: PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem e atraso projetados, situação (concluído, crítico, atenção, ok), farol do gerente × farol calculado e melancia.'
AS
WITH horas AS (
  -- EV e PV em horas, tarefa a tarefa: o que está feito e o que já deveria estar
  SELECT
    projeto_id,
    SUM(horas)                                   AS horas_totais,
    SUM(horas * pct_concluido / 100)             AS horas_agregadas,
    SUM(horas * CASE
      WHEN fim_baseline <= inicio_baseline THEN CASE WHEN DATE'2026-10-16' >= fim_baseline THEN 1 ELSE 0 END
      ELSE greatest(0, least(1, datediff(DATE'2026-10-16', inicio_baseline) / datediff(fim_baseline, inicio_baseline)))
    END)                                         AS horas_planejadas
  FROM tarefas
  GROUP BY projeto_id
),

custo_real AS (
  SELECT projeto_id, SUM(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),

farol_de_hoje AS (
  SELECT projeto_id, farol AS farol_do_gerente
  FROM status_semanal
  WHERE data_status = DATE'2026-10-16'
),

kpis AS (
  SELECT
    p.projeto_id,
    p.nome_projeto,
    p.cliente,
    p.segmento,
    p.tipo_projeto,
    p.ferramenta,
    p.gerente_projeto,
    p.valor_contrato,
    p.orcamento,
    p.data_inicio,
    p.data_fim_baseline,
    datediff(p.data_fim_baseline, p.data_inicio)                              AS duracao_baseline_dias,
    p.status,
    CAST(p.orcamento * h.horas_planejadas / h.horas_totais AS DECIMAL(18,2))  AS pv,
    CAST(p.orcamento * h.horas_agregadas  / h.horas_totais AS DECIMAL(18,2))  AS ev,
    coalesce(c.ac, 0)                                                         AS ac,
    f.farol_do_gerente
  FROM projetos p
  JOIN horas h            ON h.projeto_id = p.projeto_id
  LEFT JOIN custo_real c  ON c.projeto_id = p.projeto_id
  LEFT JOIN farol_de_hoje f ON f.projeto_id = p.projeto_id
),

indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi
  FROM kpis
),

projecao AS (
  SELECT
    *,
    CAST(try_divide(orcamento, cpi) AS DECIMAL(18,2)) AS eac
  FROM indices
)

SELECT
  projeto_id AS projeto,
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  greatest(eac - orcamento, 0)                                   AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4)     AS margem_projetada,
  CAST(round(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias) AS INT) AS atraso_projetado_dias,
  date_add(data_inicio, CAST(round(try_divide(duracao_baseline_dias, spi)) AS INT))  AS termino_projetado,
  CASE
    WHEN status <> 'em_andamento'     THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8       THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9       THEN 'atenção'
    ELSE 'ok'
  END                                                            AS situacao,
  farol_do_gerente,
  -- a regra do manual da Vértice: o farol que o número dá
  CASE
    WHEN spi >= 0.95 THEN 'verde'
    WHEN spi >= 0.90 THEN 'amarelo'
    ELSE 'vermelho'
  END                                                            AS farol_calculado,
  -- verde por fora, vermelho por dentro
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM projecao;


-- ── utilizacao_pessoa_semana: pergunta 3, tenho gente parada? ─────────────
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Uma linha por pessoa, projeto e semana (sexta-feira): horas disponíveis, apontadas e ociosas, utilização, custo das horas paradas (horas ociosas × custo/hora) e o SPI do projeto naquela semana. Responde a pergunta 3: tenho gente parada enquanto outro projeto pede gente?'
AS
SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  a.horas_disponiveis - a.horas_apontadas                                AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)           AS utilizacao,
  CAST((a.horas_disponiveis - a.horas_apontadas) * c.custo_hora AS DECIMAL(18,2)) AS custo_ocioso,
  f.spi                                                                  AS spi_do_projeto
FROM apontamentos a
JOIN colaboradores c
  ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id AND f.semana = a.semana
