# Databricks notebook source
# MAGIC %md
# MAGIC # Noite 4 · O score: a lista de segunda-feira
# MAGIC
# MAGIC O modelo `@prod` roda uma vez por semana, dentro do job, e grava o resultado numa tabela
# MAGIC (score em lote: ninguém chama o modelo ao vivo). Para cada projeto em andamento: a chance de
# MAGIC estourar nos próximos 30 dias, o ranking, a faixa e **os motivos em português**, porque
# MAGIC probabilidade sem motivo não gera ação.

# COMMAND ----------

# MAGIC %pip install -q -U "mlflow-skinny[databricks]>=2.21,<3"

# COMMAND ----------

dbutils.library.restartPython()

# COMMAND ----------

import math

import mlflow
import numpy as np
import pandas as pd

dbutils.widgets.text("catalog", "lakehouse_vertice")
CATALOGO = dbutils.widgets.get("catalog")
HOJE = "2026-10-16"
CORTE = 0.9

FEATURES = [
    "spi", "cpi", "indice_min", "d_indice_min_4s", "pct_fisico", "pct_prazo",
    "d_spi_4s", "d_cpi_4s", "d_spi_8s", "d_cpi_8s", "semanas_cpi_caindo", "cpi_ultimas_4s", "spi_ultimas_4s",
    "ociosidade_4s", "pct_consultoria_4s", "pct_cloud_4s", "saidas_12s",
    "status_freeze_4s", "status_falta_sre_4s", "status_fornecedor_4s", "status_rotatividade_4s",
    "status_escopo_4s", "status_retrabalho_4s", "status_com_bloqueio_4s",
]

# o spark_udf quebra no serverless (InvalidVersion): o modelo vem como sklearn e roda no pandas
mlflow.set_registry_uri("databricks-uc")
modelo = mlflow.sklearn.load_model(f"models:/{CATALOGO}.ml.modelo_estouro_30d@prod")
SIGMA = float(spark.table(f"{CATALOGO}.ml.modelo_metricas").first()["sigma"])

# a foto de hoje: as features da sexta 16/10 e a fotografia das ferramentas (a da gold)
hoje = spark.sql(f"""
    SELECT f.*,
           CAST(p.spi AS DOUBLE) AS spi_ferramentas,
           CAST(p.cpi AS DOUBLE) AS cpi_ferramentas
    FROM {CATALOGO}.ml.features_projeto_semana f
    JOIN {CATALOGO}.gold.projeto_situacao_atual p USING (projeto_id)
    WHERE f.semana = DATE'{HOJE}' AND p.status = 'em_andamento'
""").toPandas()
hoje[FEATURES + ["spi_ferramentas", "cpi_ferramentas"]] = hoje[FEATURES + ["spi_ferramentas", "cpi_ferramentas"]].astype(float)
print(f"{len(hoje)} projetos em andamento para pontuar")

# COMMAND ----------

# MAGIC %md
# MAGIC ## A chance de estourar em 30 dias
# MAGIC
# MAGIC Quem já está abaixo de 0,9 na fotografia de hoje recebe 1,0: a regra de corte já vê esse
# MAGIC projeto. O modelo serve para os que a regra ainda diz "ok".

# COMMAND ----------

pior_previsto = hoje["indice_min"] + modelo.predict(hoje[FEATURES])
z = (CORTE - pior_previsto) / SIGMA
hoje["prob_estouro_30d"] = [0.5 * (1 + math.erf(v / math.sqrt(2))) for v in z]

hoje["indice_ferramentas"] = hoje[["spi_ferramentas", "cpi_ferramentas"]].min(axis=1)
hoje.loc[hoje["indice_ferramentas"] < CORTE, "prob_estouro_30d"] = 1.0

# ranking único: maior chance primeiro; no empate, o índice mais baixo
hoje = hoje.sort_values(["prob_estouro_30d", "indice_ferramentas", "projeto_id"], ascending=[False, True, True])
hoje["ranking"] = range(1, len(hoje) + 1)
hoje["faixa_risco"] = np.where(hoje["prob_estouro_30d"] >= 0.5, "alto",
                               np.where(hoje["prob_estouro_30d"] >= 0.2, "medio", "baixo"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Os motivos, em português
# MAGIC
# MAGIC Os sinais vêm em ordem de gravidade, e cada projeto leva os 2 ou 3 primeiros.

# COMMAND ----------

def num(x):
    return f"{x:.2f}".replace(".", ",")


def pct(x):
    return f"{x * 100:.0f}%"


def motivos(r):
    sinais = []
    if r.indice_ferramentas < CORTE:
        sinais.append(f"já abaixo do corte: SPI {num(r.spi_ferramentas)} e CPI {num(r.cpi_ferramentas)}")
    elif r.indice_min < CORTE:
        sinais.append(f"o status semanal já está abaixo do corte ({num(r.indice_min)}), "
                      f"mas o cronograma da ferramenta diz {num(r.indice_ferramentas)}: as fontes não batem")
    if r.indice_ferramentas >= CORTE and r.indice_ferramentas - CORTE < 0.05:
        # a folga que o dono vê no dashboard: a da fotografia das ferramentas
        sinais.append(f"a {num(r.indice_ferramentas - CORTE)} do corte de 0,9 (índice {num(r.indice_ferramentas)})")
    if r.semanas_cpi_caindo >= 3:
        sinais.append(f"CPI caindo em {int(r.semanas_cpi_caindo)} das últimas 4 semanas")
    ritmos = [v for v in (r.cpi_ultimas_4s, r.spi_ultimas_4s) if pd.notna(v)]
    if ritmos and min(ritmos) < 0.85:
        sinais.append(f"ritmo do último mês em {num(min(ritmos))}")
    if r.status_falta_sre_4s > 0:
        sinais.append(f"falta de SRE em {int(r.status_falta_sre_4s)} dos últimos 4 status")
    if r.status_freeze_4s > 0:
        sinais.append("change freeze citado no status")
    if r.saidas_12s > 0 or r.status_rotatividade_4s > 0:
        sinais.append(f"rotatividade: {int(r.saidas_12s)} saída(s) do time em 12 semanas")
    if r.status_escopo_4s > 0:
        sinais.append("mudança de escopo no status")
    if pd.notna(r.pct_consultoria_4s) and r.pct_consultoria_4s >= 0.3:
        sinais.append(f"consultoria é {pct(r.pct_consultoria_4s)} do custo do mês")
    if pd.notna(r.ociosidade_4s) and r.ociosidade_4s >= 0.25:
        sinais.append(f"{pct(r.ociosidade_4s)} das horas do time paradas no mês")
    if not sinais:
        sinais.append(f"nenhum sinal grave: índice {num(r.indice_min)}, folga de {num(r.indice_min - CORTE)} até o corte")
    return "; ".join(sinais[:3])


hoje["principais_fatores"] = [motivos(r) for r in hoje.itertuples()]
hoje["data_referencia"] = pd.Timestamp(HOJE).date()

# COMMAND ----------

# MAGIC %md
# MAGIC ## Os testes e a gravação na gold
# MAGIC
# MAGIC O nome e o tipo das colunas são um contrato: o Genie e o app leem daqui.

# COMMAND ----------

score = hoje[["projeto_id", "data_referencia", "prob_estouro_30d", "ranking", "faixa_risco", "principais_fatores"]].copy()
score["prob_estouro_30d"] = score["prob_estouro_30d"].astype(float)
score["ranking"] = score["ranking"].astype("int32")    # INT no contrato da tabela

em_andamento = spark.sql(f"SELECT COUNT(*) FROM {CATALOGO}.gold.projeto_situacao_atual WHERE status = 'em_andamento'").first()[0]
assert len(score) == em_andamento, f"{len(score)} linhas no score, mas {em_andamento} projetos em andamento"
assert score["projeto_id"].is_unique, "projeto repetido no score"
assert score["prob_estouro_30d"].between(0, 1).all(), "probabilidade fora de 0 a 1"
assert score["ranking"].is_unique, "ranking repetido"
assert (score["principais_fatores"].str.len() > 0).all(), "projeto sem motivo"

spark.sql(f"""
CREATE OR REPLACE TABLE {CATALOGO}.gold.score_estouro_30d (
  projeto_id         STRING  COMMENT 'Projeto (PRJ-xxx), só os em andamento',
  data_referencia    DATE    COMMENT 'A sexta-feira da foto: 2026-10-16',
  prob_estouro_30d   DOUBLE  COMMENT 'Chance de o pior índice (menor entre SPI e CPI) cair abaixo de 0,9 nos próximos 30 dias. 1,0 = já está abaixo hoje',
  ranking            INT     COMMENT 'Posição na lista de segunda-feira (1 = maior risco)',
  faixa_risco        STRING  COMMENT 'alto (>= 0,5), medio (>= 0,2) ou baixo',
  principais_fatores STRING  COMMENT 'Os 2 ou 3 sinais mais graves, em português'
)
COMMENT 'O score de estouro em 30 dias (modelo @prod do schema ml): um projeto em andamento por linha, com a probabilidade, o ranking, a faixa e os motivos em português. O Genie e o app leem daqui.'
""")
spark.createDataFrame(score).write.insertInto(f"{CATALOGO}.gold.score_estouro_30d", overwrite=True)

display(spark.sql(f"SELECT * FROM {CATALOGO}.gold.score_estouro_30d ORDER BY ranking"))
