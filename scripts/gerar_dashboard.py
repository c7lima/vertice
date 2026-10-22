"""Gera resources/dashboard-portfolio.lvdash.json: o dashboard "Projeto Farol · Portfólio".

Dashboard como CÓDIGO: o JSON fica no Git e sai deste script (escrever o JSON à mão é
pedir para errar uma vírgula). Mudou o dashboard? Mude aqui, rode de novo e faça o
`bundle deploy`. Nunca edite no workspace: o deploy seguinte recusa ("modified remotely").

As queries da gold usam o nome de tabela PURO (`FROM projeto_situacao_atual`): o catálogo
e o schema vêm do recurso do bundle (dataset_catalog e dataset_schema). Razão é sempre
SUM/SUM, nunca a média de razões.

Uso:  python3 scripts/gerar_dashboard.py
"""
import json
import pathlib

SAIDA = pathlib.Path(__file__).resolve().parent.parent / "resources" / "dashboard-portfolio.lvdash.json"

# ── formatos e cores ─────────────────────────────────────────────────────────
BRL = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
       "decimalPlaces": {"type": "max", "places": 2}}
DUAS_CASAS = {"type": "number-plain", "decimalPlaces": {"type": "exact", "places": 2}}
INTEIRO = {"type": "number-plain", "decimalPlaces": {"type": "max", "places": 0}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}

# cor com significado: vermelho é crítico, não "bonito"
CORES_SITUACAO = [
    {"value": "crítico", "color": "#FF5F46"},
    {"value": "atenção", "color": "#F6C344"},
    {"value": "ok", "color": "#22C2F4"},
]

# o visual da Jornada: azul #0059DB, ciano #22C2F4, fundo #14141A no escuro
TEMA = {
    "canvasBackgroundColor": {"light": "#F5F6FC", "dark": "#14141A"},
    "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1E1E24"},
    "widgetBorderColor": {"light": "#FFFFFF", "dark": "#1E1E24"},
    "fontColor": {"light": "#14141A", "dark": "#F5F6FC"},
    "selectionColor": {"light": "#0059DB", "dark": "#22C2F4"},
    "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF8A4C", "#9B6BDB", "#3ECF8E", "#6E7180"],
    "widgetHeaderAlignment": "LEFT",
}


# ── os datasets: a gold faz a conta, o gráfico só mostra ─────────────────────
DATASETS = [
    ("ds_kpis", "KPIs da carteira em andamento", """
SELECT SUM(valor_contrato)                                  AS carteira,
       SUM(ev) / SUM(pv)                                    AS spi,
       SUM(ev) / SUM(ac)                                    AS cpi,
       SUM(estouro_previsto)                                AS estouro_previsto,
       COUNT_IF(situacao IN ('atenção', 'crítico'))         AS projetos_em_risco,
       COUNT_IF(situacao = 'crítico')                       AS projetos_criticos,
       COUNT_IF(melancia)                                   AS projetos_melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
"""),
    ("ds_projetos", "Projetos em andamento hoje", """
SELECT projeto_id, nome_projeto, cliente, segmento, situacao, spi, cpi,
       estouro_previsto, margem_projetada, atraso_projetado_dias,
       farol_do_gerente, farol_calculado,
       CASE WHEN melancia THEN 'sim' ELSE '' END AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC
"""),
    ("ds_estouro", "Projetos com estouro previsto", """
SELECT projeto_id, nome_projeto, situacao, estouro_previsto
FROM projeto_situacao_atual
WHERE status = 'em_andamento' AND estouro_previsto > 0
ORDER BY estouro_previsto DESC
"""),
    ("ds_evolucao", "SPI e CPI da carteira, semana a semana", """
SELECT semana,
       SUM(ev) / SUM(pv) AS spi,
       SUM(ev) / SUM(ac) AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana
"""),
    ("ds_pessoas_top", "Top 15 pessoas por custo da hora parada (12 semanas)", """
SELECT concat(nome, ' (', papel, ')') AS pessoa,
       SUM(custo_ocioso)              AS custo_parado,
       SUM(horas_ociosas)             AS horas_paradas
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel
ORDER BY custo_parado DESC
LIMIT 15
"""),
    ("ds_utilizacao", "Utilização por pessoa e projeto (12 semanas)", """
SELECT colaborador_id, nome, papel, senioridade, projeto_id,
       SUM(horas_disponiveis)                       AS horas_disponiveis,
       SUM(horas_apontadas)                         AS horas_apontadas,
       SUM(horas_ociosas)                           AS horas_ociosas,
       SUM(horas_apontadas) / SUM(horas_disponiveis) AS utilizacao,
       SUM(custo_ocioso)                            AS custo_parado
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY ALL
ORDER BY utilizacao ASC
"""),
    ("ds_causas", "Causas de bloqueio por projeto (90 dias)", """
WITH causas AS (
  SELECT projeto_id, causa_bloqueio, COUNT(*) AS semanas, SUM(coalesce(dias_impacto, 0)) AS dias_impacto
  FROM status_estruturado
  WHERE data_status >= DATE'2026-07-18'
    AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
  GROUP BY projeto_id, causa_bloqueio
),
top15 AS (
  SELECT projeto_id, SUM(semanas) AS total
  FROM causas
  GROUP BY projeto_id
  ORDER BY total DESC, projeto_id
  LIMIT 15
)
SELECT c.projeto_id, c.causa_bloqueio, c.semanas, c.dias_impacto
FROM causas c
JOIN top15 t USING (projeto_id)
ORDER BY t.total DESC, c.projeto_id
"""),
    ("ds_fornecedores", "Fornecedores: prazo prometido × real", """
SELECT fornecedor,
       COUNT(DISTINCT fornecedor_como_veio)                AS grafias,
       COUNT(*)                                            AS entregas,
       AVG(prazo_real_dias / prazo_prometido_dias)         AS prazo_real_sobre_prometido,
       AVG(CASE WHEN data_entrega <= data_prometida THEN 1.0 ELSE 0.0 END)
         FILTER (WHERE data_entrega IS NOT NULL)           AS pct_no_prazo,
       COUNT_IF(em_atraso)                                 AS em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY prazo_real_sobre_prometido DESC
"""),
    ("ds_atrasadas", "Entregas de fornecedor em atraso hoje", """
SELECT entrega_id, projeto_id, fornecedor, item, valor, data_pedido, data_prometida,
       datediff(DATE'2026-10-16', data_prometida) AS dias_de_atraso
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_de_atraso DESC
"""),
]


# ── as peças: cada função monta um tipo de widget ────────────────────────────
def dataset(nome, titulo, sql):
    # queryLines é concatenado sem separador: cada linha termina em \n
    return {"name": nome, "displayName": titulo,
            "queryLines": [linha + "\n" for linha in sql.strip().splitlines()]}


def pos(x, y, largura, altura):
    return {"x": x, "y": y, "width": largura, "height": altura}


def consulta(ds, campos, desagregado=True):
    return [{"name": "main_query", "query": {
        "datasetName": ds,
        "fields": [{"name": nome, "expression": expressao} for nome, expressao in campos],
        "disaggregated": desagregado,
    }}]


def coluna(c):
    return (c, f"`{c}`")


def soma(c):
    return (f"sum({c})", f"SUM(`{c}`)")


def texto(nome, titulo, subtitulo, p):
    return {"widget": {"name": nome, "multilineTextboxSpec": {"lines": [f"## {titulo}\n", "\n", subtitulo]}},
            "position": p}


def contador(nome, titulo, campo, formato, p):
    return {"widget": {
        "name": nome,
        "queries": consulta("ds_kpis", [coluna(campo)]),
        "spec": {"version": 2, "widgetType": "counter",
                 "encodings": {"value": {"fieldName": campo, "displayName": titulo, "format": formato}},
                 "frame": {"showTitle": True, "title": titulo}},
    }, "position": p}


def tabela(nome, titulo, ds, colunas, p):
    # colunas: (campo, título, formato ou None)
    encodings = []
    for campo, rotulo, formato in colunas:
        c = {"fieldName": campo, "displayName": rotulo}
        if formato:
            c["format"] = formato
        encodings.append(c)
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [coluna(c[0]) for c in colunas]),
        "spec": {"version": 2, "widgetType": "table", "encodings": {"columns": encodings},
                 "frame": {"showTitle": True, "title": titulo}},
    }, "position": p}


def barra_horizontal(nome, titulo, ds, categoria, rotulo_cat, medida, rotulo_med, formato=None,
                     cor=None, rotulo_cor=None, mapa_cores=None, p=None):
    # a categoria no eixo y, ordenada pela medida (a maior em cima)
    campos = [coluna(categoria), soma(medida)]
    x = {"fieldName": f"sum({medida})", "scale": {"type": "quantitative"}, "displayName": rotulo_med}
    if formato:
        x["format"] = formato
    encodings = {
        "y": {"fieldName": categoria, "scale": {"type": "categorical", "sort": {"by": "x-reversed"}},
              "displayName": rotulo_cat},
        "x": x,
    }
    if cor:
        campos.append(coluna(cor))
        escala = {"type": "categorical"}
        if mapa_cores:
            escala["mappings"] = mapa_cores
        encodings["color"] = {"fieldName": cor, "scale": escala, "displayName": rotulo_cor}
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, campos, desagregado=False),
        "spec": {"version": 3, "widgetType": "bar", "encodings": encodings,
                 "frame": {"showTitle": True, "title": titulo}},
    }, "position": p}


def dispersao(nome, titulo, ds, x, rotulo_x, y, rotulo_y, cor, rotulo_cor, p):
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [coluna(x), coluna(y), coluna(cor)]),
        "spec": {"version": 3, "widgetType": "scatter",
                 "encodings": {
                     "x": {"fieldName": x, "scale": {"type": "quantitative"}, "displayName": rotulo_x},
                     "y": {"fieldName": y, "scale": {"type": "quantitative"}, "displayName": rotulo_y},
                     "color": {"fieldName": cor, "scale": {"type": "categorical", "mappings": CORES_SITUACAO},
                               "displayName": rotulo_cor},
                 },
                 "frame": {"showTitle": True, "title": titulo}},
    }, "position": p}


def linha_do_tempo(nome, titulo, ds, x, series, p):
    # series: (campo, título), cada uma vira uma linha
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [coluna(x)] + [coluna(c) for c, _ in series]),
        "spec": {"version": 3, "widgetType": "line",
                 "encodings": {
                     "x": {"fieldName": x, "scale": {"type": "temporal"}, "displayName": "Semana"},
                     "y": {"scale": {"type": "quantitative"},
                           "fields": [{"fieldName": c, "displayName": rotulo} for c, rotulo in series]},
                 },
                 "frame": {"showTitle": True, "title": titulo}},
    }, "position": p}


# ── as 3 páginas: uma pergunta do dono em cada ───────────────────────────────
def pagina(nome, titulo, layout):
    return {"name": nome, "displayName": titulo, "pageType": "PAGE_TYPE_CANVAS",
            "layoutVersion": "GRID_V1", "layout": layout}


PORTFOLIO = pagina("portfolio", "Portfólio", [
    texto("titulo-portfolio", "Quais projetos atrasam, e quanto isso custa?",
          "Os 41 projetos em andamento em 16/10/2026. SPI e CPI abaixo de 0,9 = atenção, abaixo de 0,8 = crítico.",
          pos(0, 0, 12, 2)),
    contador("kpi-carteira", "Carteira em andamento", "carteira", BRL, pos(0, 2, 3, 3)),
    contador("kpi-estouro", "Estouro previsto", "estouro_previsto", BRL, pos(3, 2, 3, 3)),
    contador("kpi-spi", "SPI da carteira (prazo)", "spi", DUAS_CASAS, pos(6, 2, 3, 3)),
    contador("kpi-cpi", "CPI da carteira (custo)", "cpi", DUAS_CASAS, pos(9, 2, 3, 3)),
    contador("kpi-risco", "Projetos em risco (atenção + crítico)", "projetos_em_risco", INTEIRO, pos(0, 5, 4, 3)),
    contador("kpi-criticos", "Projetos críticos", "projetos_criticos", INTEIRO, pos(4, 5, 4, 3)),
    contador("kpi-melancias", "Melancias (farol verde, SPI < 0,9)", "projetos_melancia", INTEIRO, pos(8, 5, 4, 3)),
    barra_horizontal("estouro-por-projeto", "Estouro previsto por projeto", "ds_estouro",
                     "projeto_id", "Projeto", "estouro_previsto", "Estouro previsto", formato=BRL,
                     cor="situacao", rotulo_cor="Situação", mapa_cores=CORES_SITUACAO, p=pos(0, 8, 6, 7)),
    dispersao("spi-x-cpi", "SPI × CPI: um ponto por projeto", "ds_projetos",
              "spi", "SPI (prazo)", "cpi", "CPI (custo)", "situacao", "Situação", pos(6, 8, 6, 7)),
    linha_do_tempo("evolucao", "SPI e CPI da carteira, semana a semana", "ds_evolucao",
                   "semana", [("spi", "SPI"), ("cpi", "CPI")], pos(0, 15, 12, 6)),
    tabela("tabela-projetos", "Projetos em andamento: o farol do gerente × o farol pelo número", "ds_projetos", [
        ("projeto_id", "Projeto", None), ("cliente", "Cliente", None), ("situacao", "Situação", None),
        ("spi", "SPI", DUAS_CASAS), ("cpi", "CPI", DUAS_CASAS), ("estouro_previsto", "Estouro previsto", BRL),
        ("margem_projetada", "Margem projetada", PCT), ("atraso_projetado_dias", "Atraso projetado (dias)", INTEIRO),
        ("farol_do_gerente", "Farol do gerente", None), ("farol_calculado", "Farol pelo número", None),
        ("melancia", "Melancia", None),
    ], pos(0, 21, 12, 8)),
])

PESSOAS = pagina("pessoas", "Pessoas", [
    texto("titulo-pessoas", "Tenho gente parada enquanto outro projeto pede gente?",
          "Últimas 12 semanas do timesheet, lado a lado com a causa que a IA tirou do texto do status semanal.",
          pos(0, 0, 12, 2)),
    barra_horizontal("pessoas-paradas", "Top 15 pessoas por custo da hora parada", "ds_pessoas_top",
                     "pessoa", "Pessoa", "custo_parado", "Custo da hora parada", formato=BRL, p=pos(0, 2, 6, 8)),
    barra_horizontal("causas-por-projeto", "Causas de bloqueio por projeto (90 dias)", "ds_causas",
                     "projeto_id", "Projeto", "semanas", "Semanas com bloqueio",
                     cor="causa_bloqueio", rotulo_cor="Causa", p=pos(6, 2, 6, 8)),
    tabela("tabela-utilizacao", "Utilização por pessoa e projeto: da mais parada à mais ocupada", "ds_utilizacao", [
        ("colaborador_id", "Pessoa", None), ("nome", "Nome", None), ("papel", "Papel", None),
        ("senioridade", "Senioridade", None), ("projeto_id", "Projeto", None),
        ("horas_disponiveis", "Horas disponíveis", INTEIRO), ("horas_apontadas", "Horas apontadas", INTEIRO),
        ("horas_ociosas", "Horas paradas", INTEIRO), ("utilizacao", "Utilização", PCT),
        ("custo_parado", "Custo da hora parada", BRL),
    ], pos(0, 10, 12, 8)),
])

FORNECEDORES = pagina("fornecedores", "Fornecedores", [
    texto("titulo-fornecedores", "Qual fornecedor não cumpre prazo?",
          "As entregas das consultorias: o prazo prometido × o real, e o que está em atraso hoje.",
          pos(0, 0, 12, 2)),
    tabela("tabela-fornecedores", "Fornecedores: prazo prometido × real", "ds_fornecedores", [
        ("fornecedor", "Fornecedor", None), ("grafias", "Grafias no cadastro", INTEIRO),
        ("entregas", "Entregas", INTEIRO), ("prazo_real_sobre_prometido", "Prazo real ÷ prometido", DUAS_CASAS),
        ("pct_no_prazo", "% no prazo", PCT), ("em_atraso_hoje", "Em atraso hoje", INTEIRO),
    ], pos(0, 2, 12, 5)),
    tabela("tabela-atrasadas", "Entregas em atraso hoje", "ds_atrasadas", [
        ("entrega_id", "Entrega", None), ("projeto_id", "Projeto", None), ("fornecedor", "Fornecedor", None),
        ("item", "Item", None), ("valor", "Valor", BRL), ("data_prometida", "Prometida para", None),
        ("dias_de_atraso", "Dias de atraso", INTEIRO),
    ], pos(0, 7, 12, 5)),
])


def montar():
    return {
        "datasets": [dataset(*d) for d in DATASETS],
        "pages": [PORTFOLIO, PESSOAS, FORNECEDORES],
        "uiSettings": {"theme": TEMA},
    }


if __name__ == "__main__":
    painel = montar()
    # newline="\n": no Windows o arquivo também sai com fim de linha LF
    with SAIDA.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(painel, f, ensure_ascii=False, indent=2)
        f.write("\n")
    widgets = sum(len(p["layout"]) for p in painel["pages"])
    print(f"ok: {SAIDA.name} · {len(painel['datasets'])} datasets · {len(painel['pages'])} páginas · {widgets} widgets")
