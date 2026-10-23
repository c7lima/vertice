"""Gera resources/farol.geniespace.json: o Genie Agent "Farol · Diretoria", como código.

As instruções de negócio (o "hoje" do dataset, as regras de corte, onde achar a causa do
atraso, o que é "próximo mês") viram arquivo versionado, com diff e revisão. Mudou a
instrução? Rode este script, faça o `bundle deploy` e rode o benchmark de novo. Nunca edite
o Genie no workspace: o deploy seguinte recusa ("modified remotely").

O JSON é o serialized_space versão 2: ids de 32 caracteres hex, únicos e em ordem, e as
tabelas ordenadas pelo nome.

Uso:  python3 scripts/gerar_genie.py
"""
import json
import pathlib

SAIDA = pathlib.Path(__file__).resolve().parent.parent / "resources" / "farol.geniespace.json"

TABELAS = [
    "lakehouse_vertice.gold.fato_projeto_semana",
    "lakehouse_vertice.gold.projeto_situacao_atual",
    "lakehouse_vertice.gold.score_estouro_30d",
    "lakehouse_vertice.gold.status_estruturado",
    "lakehouse_vertice.gold.utilizacao_pessoa_semana",
    "lakehouse_vertice.silver.entregas_fornecedor",
]
METRICAS = ["lakehouse_vertice.gold.mv_projetos"]

# as 4 perguntas do dono: aparecem como sugestão na tela do Genie
PERGUNTAS = [
    "Quais projetos estão atrasados, e de quais clientes?",
    "Quanto esse atraso vai me custar?",
    "Tenho gente parada enquanto outro projeto pede gente?",
    "O que vai dar errado no próximo mês, e o que eu faço agora?",
]

INSTRUCOES = [
    "Quem pergunta é o dono da Vértice Tecnologia e a diretoria. Responda em português, direto, com números em reais e índices com 2 casas decimais.",
    "HOJE é 2026-10-16 (sexta-feira). Nunca use current_date(). 'Últimos 90 dias' = data_status >= 2026-07-18. 'Últimas 12 semanas' = semana > 2026-07-24. 'Próximo mês' = os próximos 30 dias, até 2026-11-15.",
    "Fórmulas: SPI = EV / PV (prazo) e CPI = EV / AC (custo). Abaixo de 1 é atraso ou estouro. Regras de corte: SPI ou CPI abaixo de 0,9 = atenção, abaixo de 0,8 = crítico. EAC = orçamento / CPI. Estouro previsto = EAC - orçamento, quando positivo.",
    "Para totais e KPIs da carteira de HOJE (SPI, CPI, estouro previsto, margem, quantos projetos em risco, críticos ou melancias) use a metric view gold.mv_projetos com MEASURE(). Ela já filtra os projetos em andamento e calcula razão como soma dividida por soma, nunca média de razões.",
    "Para listar, ordenar ou fazer ranking de projetos (o mais atrasado, o maior estouro, o maior atraso projetado) use gold.projeto_situacao_atual com status = 'em_andamento'. A coluna projeto_id é o código (PRJ-011).",
    "Em gold.fato_projeto_semana, PV, EV e AC são ACUMULADOS até a semana: nunca some semanas diferentes do mesmo projeto. Para a evolução, leia a linha de cada semana. Para 'o SPI na semana X', filtre semana = X (as semanas são sextas-feiras).",
    "Farol do gerente é o que ele publicou no status de sexta. Farol calculado é o da regra do manual (verde com SPI a partir de 0,95, amarelo a partir de 0,90). Melancia = projeto em andamento com farol do gerente verde e SPI abaixo de 0,9 (coluna melancia).",
    "'Por que o projeto X atrasou?' responde com gold.status_estruturado dos últimos 90 dias, sem as causas sem_bloqueio e nao_reportado: a causa_bloqueio mais frequente, quantas semanas e a soma de dias_impacto. Junte o SPI e o CPI de hoje. Se a causa for falta_sre, mostre também os SREs ociosos (utilização abaixo de 20% nas últimas 12 semanas).",
    "Gente parada = pessoa com utilização (soma das horas apontadas dividida pela soma das horas disponíveis) abaixo de 20% nas últimas 12 semanas, em gold.utilizacao_pessoa_semana. O papel vem em minúsculas (sre, dev_backend...).",
    "Fornecedor que mais atrasa = maior média de prazo_real_dias / prazo_prometido_dias em silver.entregas_fornecedor. Entrega em atraso hoje = coluna em_atraso. A CodeForge Consultoria Ltda já vem com o nome normalizado.",
    "'O que vai dar errado no próximo mês' junta TRÊS fontes, numa resposta só: (1) o modelo, gold.score_estouro_30d, com os projetos que hoje estão com situacao = 'ok' e faixa_risco alto ou medio, e os principais_fatores de cada um. Os que já estão em atenção ou crítico a regra de corte já vê, não são novidade. (2) As entregas de consultoria em atraso (em_atraso em silver.entregas_fornecedor). (3) O change freeze do varejo, de 01/11/2026 a 10/01/2027, que trava deploy nos projetos de e-commerce em andamento (tipo_projeto com commerce, checkout ou marketplace). Um projeto que aparece em mais de uma fonte merece destaque.",
    "A probabilidade de estouro em 30 dias vem de gold.score_estouro_30d, na data_referencia mais recente. 1,0 significa que o projeto já está abaixo do corte hoje.",
    "'Quais clientes' devolve cada cliente uma vez só (DISTINCT), mesmo que ele tenha mais de um projeto.",
]

EXEMPLOS = [
    ("Quais projetos estão atrasados, e de quais clientes?", """
SELECT projeto_id, nome_projeto, cliente, situacao, spi, cpi, estouro_previsto
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento' AND situacao IN ('crítico', 'atenção')
ORDER BY least(spi, cpi)
"""),
    ("Quanto esse atraso vai me custar?", """
SELECT MEASURE(estouro_previsto) AS estouro_previsto,
       MEASURE(margem_projetada) AS margem_projetada,
       MEASURE(projetos_em_risco) AS projetos_em_risco,
       MEASURE(carteira) AS carteira
FROM lakehouse_vertice.gold.mv_projetos
"""),
    ("Tenho gente parada enquanto outro projeto pede gente?", """
WITH parados AS (
  SELECT colaborador_id, nome, papel, projeto_id,
         SUM(horas_apontadas) / SUM(horas_disponiveis) AS utilizacao,
         SUM(horas_ociosas) AS horas_paradas
  FROM lakehouse_vertice.gold.utilizacao_pessoa_semana
  WHERE semana > DATE'2026-07-24'
  GROUP BY colaborador_id, nome, papel, projeto_id
  HAVING SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2
),
pedidos AS (
  SELECT projeto_id, COUNT(*) AS semanas, SUM(coalesce(dias_impacto, 0)) AS dias_impacto
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= DATE'2026-07-18' AND causa_bloqueio = 'falta_sre'
  GROUP BY projeto_id
)
SELECT 'parado' AS tipo, projeto_id, concat(colaborador_id, ' ', nome, ' (', papel, ')') AS quem,
       concat(CAST(ROUND(utilizacao * 100, 1) AS STRING), '% de utilização, ', CAST(ROUND(horas_paradas) AS STRING), ' horas paradas') AS detalhe
FROM parados
UNION ALL
SELECT 'pedindo SRE no status' AS tipo, projeto_id, 'falta de SRE' AS quem,
       concat(CAST(semanas AS STRING), ' semanas, ', CAST(dias_impacto AS STRING), ' dias de impacto declarados') AS detalhe
FROM pedidos
"""),
    ("O que vai dar errado no próximo mês, e o que eu faço agora?", """
SELECT 'modelo: risco de estouro em 30 dias' AS fonte, s.projeto_id, p.cliente,
       concat(CAST(ROUND(s.prob_estouro_30d * 100) AS INT), '% de chance (', s.faixa_risco, ')') AS sinal,
       s.principais_fatores AS detalhe
FROM lakehouse_vertice.gold.score_estouro_30d s
JOIN lakehouse_vertice.gold.projeto_situacao_atual p USING (projeto_id)
WHERE s.data_referencia = (SELECT MAX(data_referencia) FROM lakehouse_vertice.gold.score_estouro_30d)
  AND p.situacao = 'ok' AND s.faixa_risco IN ('alto', 'medio')
UNION ALL
SELECT 'entrega de consultoria em atraso' AS fonte, e.projeto_id, p.cliente,
       concat(e.fornecedor, ': ', e.item) AS sinal,
       concat('prometida para ', CAST(e.data_prometida AS STRING), ', ', CAST(datediff(DATE'2026-10-16', e.data_prometida) AS STRING), ' dias de atraso') AS detalhe
FROM lakehouse_vertice.silver.entregas_fornecedor e
JOIN lakehouse_vertice.gold.projeto_situacao_atual p USING (projeto_id)
WHERE e.em_atraso
UNION ALL
SELECT 'change freeze da Black Friday (01/11/2026 a 10/01/2027)' AS fonte, projeto_id, cliente,
       tipo_projeto AS sinal, 'deploy travado no varejo a partir de 01/11/2026' AS detalhe
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
  AND (lower(tipo_projeto) LIKE '%commerce%' OR lower(tipo_projeto) LIKE '%checkout%' OR lower(tipo_projeto) LIKE '%marketplace%')
"""),
    ("Qual a chance de o PRJ-024 estourar no próximo mês?", """
SELECT s.projeto_id, ROUND(s.prob_estouro_30d, 2) AS prob_estouro_30d, s.faixa_risco, s.ranking,
       s.principais_fatores, p.situacao, p.spi, p.cpi
FROM lakehouse_vertice.gold.score_estouro_30d s
JOIN lakehouse_vertice.gold.projeto_situacao_atual p USING (projeto_id)
WHERE s.projeto_id = 'PRJ-024'
  AND s.data_referencia = (SELECT MAX(data_referencia) FROM lakehouse_vertice.gold.score_estouro_30d)
"""),
]


def ident(prefixo, n):
    # 32 caracteres hex: um prefixo por tipo e o número com zeros à esquerda (únicos e em ordem)
    return f"{prefixo}{n:0{32 - len(prefixo)}d}"


def montar():
    return {
        "version": 2,
        "config": {"sample_questions": [{"id": ident("a1", i), "question": [q]} for i, q in enumerate(PERGUNTAS, 1)]},
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(TABELAS)],
            "metric_views": [{"identifier": m} for m in sorted(METRICAS)],
        },
        "instructions": {
            "text_instructions": [{"id": ident("b1", 1), "content": [linha + "\n" for linha in INSTRUCOES]}],
            "example_question_sqls": [{"id": ident("c1", i), "question": [q], "sql": [sql.strip()]}
                                      for i, (q, sql) in enumerate(EXEMPLOS, 1)],
        },
    }


if __name__ == "__main__":
    espaco = montar()
    # newline="\n": no Windows o arquivo também sai com fim de linha LF
    with SAIDA.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(espaco, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"ok: {SAIDA.name} · {len(TABELAS)} tabelas + {len(METRICAS)} metric view · "
          f"{len(PERGUNTAS)} perguntas · {len(INSTRUCOES)} instruções · {len(EXEMPLOS)} exemplos de SQL")
