-- gold.status_estruturado: o texto livre do status semanal vira coluna.
--
-- A IA custa por linha (~5 s por texto com as duas funções), então cada ferramenta
-- onde ela é a certa:
--   regra          a semana sem bloqueio e o status vazio (custo zero, resposta exata)
--   ia             o texto com bloqueio dos últimos 90 dias (ai_classify + ai_extract)
--   palavra_chave  o histórico antigo, onde a resposta não muda decisão
--
-- A tabela ACUMULA: o MERGE só recebe os status que ainda não estão nela. Na semana
-- que vem a IA lê só os status da semana que vem, e a conta não se paga duas vezes.
-- Atenção: a sql_task corta o arquivo em todo ponto e vírgula, então ele só aparece
-- no fim de cada comando.


-- a. a tabela (NÃO é CREATE OR REPLACE: a IA não pode ser refeita a cada execução)
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id       STRING    COMMENT 'Projeto (PRJ-xxx)',
  data_status      DATE      COMMENT 'A sexta-feira do status semanal',
  farol            STRING    COMMENT 'Farol publicado pelo gerente: verde, amarelo ou vermelho',
  causa_bloqueio   STRING    COMMENT 'Causa do bloqueio numa lista fechada: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio ou nao_reportado (status vazio)',
  bloqueio         STRING    COMMENT 'O bloqueio em poucas palavras (só nos textos lidos pela IA)',
  quem_destrava    STRING    COMMENT 'Quem pode destravar o bloqueio (só nos textos lidos pela IA)',
  dias_impacto     DOUBLE    COMMENT 'Dias de impacto declarados no texto (1 semana = 7)',
  metodo           STRING    COMMENT 'De onde veio a resposta: regra, ia ou palavra_chave',
  texto_status     STRING    COMMENT 'O texto livre original do status',
  _classificado_em TIMESTAMP COMMENT 'Quando a linha foi classificada'
)
COMMENT 'O status semanal estruturado: uma linha por projeto e sexta (3.911), com a causa do bloqueio tirada do texto livre por regra, por IA (ai_classify + ai_extract, nos últimos 90 dias com bloqueio) ou por palavra-chave. A tabela acumula: cada execução classifica só os status novos.';


-- b. só os status novos, cada um pelo seu método
MERGE INTO lakehouse_vertice.gold.status_estruturado AS alvo
USING (
  WITH novos AS (
    SELECT
      s.*,
      lower(coalesce(s.texto_status, '')) AS texto
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status
  ),

  com_metodo AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      texto_status,
      texto,
      status_vazio,
      CASE
        WHEN status_vazio
          OR texto LIKE '%bloqueios: nenhum%'
          OR texto LIKE '%sem bloqueios%'
          OR texto LIKE '%nada relevante%'      THEN 'regra'
        WHEN data_status >= DATE'2026-07-18'    THEN 'ia'
        ELSE 'palavra_chave'
      END AS metodo,
      -- os dias que o próprio texto declara (usado fora da IA)
      CASE
        WHEN texto RLIKE 'impacto estimado: 1 semana' THEN 7.0
        ELSE CAST(nullif(regexp_extract(texto, 'impacto estimado de ([0-9]+) dias', 1), '') AS DOUBLE)
      END AS dias_pelo_texto
    FROM novos
  ),

  -- só os textos da IA chamam a IA, e cada função roda uma vez por linha
  pela_ia AS (
    SELECT
      *,
      ai_classify(
        texto_status,
        '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
        map('version', '2.0')
      ):response[0]::STRING AS causa_ia,
      ai_extract(
        texto_status,
        '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"1 semana = 7"}}',
        map('version', '2.0')
      ) AS extraido
    FROM com_metodo
    WHERE metodo = 'ia'
  )

  SELECT
    projeto_id,
    data_status,
    farol,
    causa_ia                                   AS causa_bloqueio,
    extraido:response:bloqueio::STRING         AS bloqueio,
    extraido:response:quem_destrava::STRING    AS quem_destrava,
    extraido:response:dias_impacto::DOUBLE     AS dias_impacto,
    metodo,
    texto_status,
    current_timestamp()                        AS _classificado_em
  FROM pela_ia

  UNION ALL

  SELECT
    projeto_id,
    data_status,
    farol,
    CASE
      WHEN metodo = 'regra' AND status_vazio                           THEN 'nao_reportado'
      WHEN metodo = 'regra'                                            THEN 'sem_bloqueio'
      WHEN texto RLIKE 'freeze|congelamento|janela de deploy'          THEN 'change_freeze'
      WHEN texto RLIKE 'sre|infraestrutura|ambiente de homologação'    THEN 'falta_sre'
      WHEN texto RLIKE 'forge|consultoria|fornecedor'                  THEN 'dependencia_fornecedor'
      WHEN texto RLIKE 'saída de|rotatividade|onboarding'              THEN 'rotatividade'
      WHEN texto RLIKE 'escopo|change request|regra de negócio'        THEN 'mudanca_escopo'
      WHEN texto RLIKE 'bugs|regressão|refazendo'                      THEN 'bug_retrabalho'
      WHEN texto RLIKE 'aprovação do cliente|homologação do cliente'   THEN 'aprovacao_cliente'
    END                                        AS causa_bloqueio,
    CAST(NULL AS STRING)                       AS bloqueio,
    CAST(NULL AS STRING)                       AS quem_destrava,
    dias_pelo_texto                            AS dias_impacto,
    metodo,
    texto_status,
    current_timestamp()                        AS _classificado_em
  FROM com_metodo
  WHERE metodo <> 'ia'
) AS novo
ON alvo.projeto_id = novo.projeto_id AND alvo.data_status = novo.data_status
WHEN NOT MATCHED THEN INSERT *;


-- c. a leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, COUNT(*) AS status
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, status DESC;
