# Databricks notebook source
# MAGIC %md
# MAGIC # Noite 4 · O modelo: o que vai dar errado no próximo mês
# MAGIC
# MAGIC A regra de corte (SPI ou CPI < 0,9) acende quando o projeto **já** estourou. Este notebook
# MAGIC treina um modelo que avisa **30 dias antes**, e só o registra no Unity Catalog se ele passar
# MAGIC em quatro testes. A ordem importa:
# MAGIC
# MAGIC 1. **divide no tempo** (treina no passado, cobra no futuro, como na vida real)
# MAGIC 2. **imprime os baselines antes de treinar** (o modelo só entra se ganhar da regra simples)
# MAGIC 3. treina, mede a **métrica do dono** (quantos estouros estariam no top 5, e quanto tempo antes)
# MAGIC 4. os `assert`, e só então o registro `@prod`

# COMMAND ----------

# MAGIC %md
# MAGIC O serverless vem com MLflow 2.11, que falha ao registrar no Unity Catalog (`s3:PutObject ...
# MAGIC explicit deny`). Com o MLflow 2.21 ou mais novo (ainda 2.x), funciona.

# COMMAND ----------

# MAGIC %pip install -q -U "mlflow-skinny[databricks]>=2.21,<3"

# COMMAND ----------

dbutils.library.restartPython()

# COMMAND ----------

import math

import mlflow
import numpy as np
import pandas as pd
from databricks.sdk import WorkspaceClient
from mlflow.models import infer_signature
from mlflow.tracking import MlflowClient
from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor
from sklearn.inspection import permutation_importance
from sklearn.metrics import roc_auc_score

dbutils.widgets.text("catalog", "lakehouse_vertice")
CATALOGO = dbutils.widgets.get("catalog")
NOME_MODELO = f"{CATALOGO}.ml.modelo_estouro_30d"

CORTE = 0.9
INICIO_TESTE = pd.Timestamp("2026-04-03")   # o futuro que o modelo nunca viu
FIM_TREINO = pd.Timestamp("2026-03-06")     # 4 semanas de folga: o horizonte do rótulo

# as 24 features: tudo menos identificação, segmento, farol do gerente, elegível e os alvos
FEATURES = [
    "spi", "cpi", "indice_min", "d_indice_min_4s", "pct_fisico", "pct_prazo",
    "d_spi_4s", "d_cpi_4s", "d_spi_8s", "d_cpi_8s", "semanas_cpi_caindo", "cpi_ultimas_4s", "spi_ultimas_4s",
    "ociosidade_4s", "pct_consultoria_4s", "pct_cloud_4s", "saidas_12s",
    "status_freeze_4s", "status_falta_sre_4s", "status_fornecedor_4s", "status_rotatividade_4s",
    "status_escopo_4s", "status_retrabalho_4s", "status_com_bloqueio_4s",
]

df = spark.table(f"{CATALOGO}.ml.features_projeto_semana").toPandas()
df["semana"] = pd.to_datetime(df["semana"])
df[FEATURES + ["alvo_pior_indice_30d", "estoura_30d"]] = df[FEATURES + ["alvo_pior_indice_30d", "estoura_30d"]].astype(float)
print(f"{len(df)} linhas · {len(FEATURES)} features")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Treino e teste, divididos no tempo
# MAGIC
# MAGIC Treino: as semanas rotuladas até 06/03/2026 (com o projeto já 15% andado). Teste: as semanas
# MAGIC elegíveis a partir de 03/04/2026. Com divisão aleatória, a semana 20 de um projeto iria para o
# MAGIC treino e a 21 para o teste, e não daria para saber se o modelo "colou".

# COMMAND ----------

rotulados = df[df["estoura_30d"].notna()]
treino = rotulados[(rotulados["semana"] <= FIM_TREINO) & (rotulados["pct_prazo"] > 0.15)]
teste = rotulados[(rotulados["elegivel"] == 1) & (rotulados["semana"] >= INICIO_TESTE)]
y_teste = teste["estoura_30d"].astype(int)
print(f"treino: {len(treino)} semanas · teste: {len(teste)} semanas, {int(y_teste.sum())} terminaram o mês abaixo de 0,9")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Os baselines, ANTES de treinar
# MAGIC
# MAGIC As regras simples que qualquer um usaria. O modelo só entra se ganhar da melhor delas.

# COMMAND ----------

baselines = {
    "a regra de corte atual (< 0,9)": (teste["indice_min"] < CORTE).astype(float),
    "a folga até o corte": -teste["indice_min"],
    "só o CPI": -teste["cpi"],
    "a tendência das últimas 4 semanas": -teste["d_indice_min_4s"].fillna(0),
}
auc_baselines = {nome: roc_auc_score(y_teste, pontos) for nome, pontos in baselines.items()}
for nome, auc in auc_baselines.items():
    print(f"{auc:.3f}  {nome}")
AUC_FOLGA = auc_baselines["a folga até o corte"]

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. O modelo
# MAGIC
# MAGIC Ele prevê **quanto o pior índice das próximas 4 semanas vai cair** em relação ao de hoje. A
# MAGIC chance de cruzar 0,9 sai daí, com um erro normal medido no teste. Um classificador sim/não
# MAGIC entra só para comparar.

# COMMAND ----------

PARAMETROS = dict(random_state=42, max_depth=3, learning_rate=0.05, max_iter=300, min_samples_leaf=20)


def probabilidade(pior_previsto, sigma):
    # P(pior índice < 0,9), com o erro da previsão seguindo uma normal
    z = (CORTE - np.asarray(pior_previsto)) / sigma
    return np.array([0.5 * (1 + math.erf(v / math.sqrt(2))) for v in z])


regressor = HistGradientBoostingRegressor(**PARAMETROS)
regressor.fit(treino[FEATURES], treino["alvo_pior_indice_30d"] - treino["indice_min"])

pior_previsto = teste["indice_min"] + regressor.predict(teste[FEATURES])
SIGMA = float(np.std(teste["alvo_pior_indice_30d"] - pior_previsto))
prob_teste = probabilidade(pior_previsto, SIGMA)
AUC = roc_auc_score(y_teste, prob_teste)

classificador = HistGradientBoostingClassifier(**PARAMETROS)
classificador.fit(treino[FEATURES], treino["estoura_30d"].astype(int))
AUC_CLASSIFICADOR = roc_auc_score(y_teste, classificador.predict_proba(teste[FEATURES])[:, 1])

print(f"AUC do modelo: {AUC:.3f} · classificador sim/não: {AUC_CLASSIFICADOR:.3f} · folga até o corte: {AUC_FOLGA:.3f} · sigma {SIGMA:.4f}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. A métrica do dono
# MAGIC
# MAGIC AUC não é a pergunta do dono. A pergunta é: *dos projetos que estouraram depois de abril, quantos
# MAGIC estariam na lista dos 5 mais arriscados da semana, e quanto tempo antes?*
# MAGIC
# MAGIC - **estouro**: o projeto vinha 4 semanas com SPI e CPI ≥ 0,9, cruza e **fica** abaixo por 2 semanas
# MAGIC   (já 15% andado), a partir de 4 semanas depois do início do teste
# MAGIC - **avisado**: esteve no top 5 da semana em alguma das 8 semanas anteriores

# COMMAND ----------

# a lista de cada sexta: as semanas do teste, ordenadas pela chance que o modelo deu
teste = teste.copy()
teste["prob"] = prob_teste
teste["posicao"] = teste.groupby("semana")["prob"].rank(ascending=False, method="first")
top5 = teste[teste["posicao"] <= 5]

estouros = []
for projeto, linhas in df.sort_values("semana").groupby("projeto_id"):
    linhas = linhas.reset_index(drop=True)
    for i in range(4, len(linhas) - 1):
        antes = linhas.loc[i - 4:i - 1]
        semana = linhas.loc[i, "semana"]
        if (semana >= INICIO_TESTE + pd.Timedelta(weeks=4)
                and linhas.loc[i, "pct_prazo"] > 0.15
                and (antes["spi"] >= CORTE).all() and (antes["cpi"] >= CORTE).all()
                and linhas.loc[i, "indice_min"] < CORTE and linhas.loc[i + 1, "indice_min"] < CORTE):
            estouros.append((projeto, semana))
            break

avisos = []
for projeto, semana in estouros:
    janela = top5[(top5["projeto_id"] == projeto)
                  & (top5["semana"] < semana) & (top5["semana"] >= semana - pd.Timedelta(weeks=8))]
    if len(janela):
        avisos.append((projeto, (semana - janela["semana"].min()).days))

ESTOUROS = len(estouros)
AVISADOS = len(avisos)
ANTECEDENCIA = float(np.mean([dias for _, dias in avisos])) if avisos else 0.0
print(f"{AVISADOS} de {ESTOUROS} estouros estavam no top 5 da semana, em média {ANTECEDENCIA:.0f} dias antes")
for projeto, semana in estouros:
    dias = dict(avisos).get(projeto)
    print(f"  {projeto} cruzou em {semana:%d/%m/%Y}: " + (f"avisado {dias} dias antes" if dias else "NÃO avisado"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. O que o modelo olha (importância por permutação)

# COMMAND ----------

importancia = permutation_importance(
    regressor, teste[FEATURES], teste["alvo_pior_indice_30d"] - teste["indice_min"],
    n_repeats=10, random_state=42,
)
ranking_features = pd.Series(importancia.importances_mean, index=FEATURES).sort_values(ascending=False)
print(ranking_features.head(10).round(4).to_string())
FEATURE_PRINCIPAL = ranking_features.index[0]

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Os testes, ANTES de registrar
# MAGIC
# MAGIC AUC acima de 0,98 não é sucesso: é sinal de que alguma feature está vendo o futuro (vazamento).

# COMMAND ----------

assert AUC >= 0.75, f"AUC {AUC:.3f} abaixo de 0,75: o modelo não serve"
assert AUC < 0.98, f"AUC {AUC:.3f}: bom DEMAIS, alguma feature vê o futuro (procure FOLLOWING fora dos alvos)"
assert AUC >= AUC_FOLGA, f"AUC {AUC:.3f} perde da regra simples da folga ({AUC_FOLGA:.3f})"
assert ESTOUROS > 0 and AVISADOS >= 0.7 * ESTOUROS, f"só {AVISADOS} de {ESTOUROS} estouros avisados (mínimo 70%)"
print("os 4 testes passaram")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. O registro: retreina com todo o histórico rotulado e publica `@prod`

# COMMAND ----------

# todo o histórico rotulado, com o mesmo filtro do treino: nas primeiras semanas do projeto
# ainda não há PV nem AC, e o índice de hoje é nulo
historico = rotulados[rotulados["pct_prazo"] > 0.15]
final = HistGradientBoostingRegressor(**PARAMETROS)
final.fit(historico[FEATURES], historico["alvo_pior_indice_30d"] - historico["indice_min"])

usuario = spark.sql("SELECT current_user()").first()[0]
pasta = f"/Users/{usuario}/vertice"
WorkspaceClient().workspace.mkdirs(pasta)          # o set_experiment não cria a pasta pai
mlflow.set_experiment(f"{pasta}/modelo_estouro_30d")
mlflow.set_registry_uri("databricks-uc")

exemplo = historico[FEATURES].head(5).astype(float)
with mlflow.start_run(run_name="modelo_estouro_30d") as run:
    mlflow.log_params(PARAMETROS)
    mlflow.log_metrics({"auc": AUC, "auc_classificador": AUC_CLASSIFICADOR, "auc_folga": AUC_FOLGA,
                        "sigma": SIGMA, "estouros_avisados": AVISADOS, "estouros_teste": ESTOUROS,
                        "antecedencia_media_dias": ANTECEDENCIA})
    info = mlflow.sklearn.log_model(
        final,
        artifact_path="modelo",
        input_example=exemplo,
        signature=infer_signature(exemplo, final.predict(exemplo)),
        registered_model_name=NOME_MODELO,
    )

versao = info.registered_model_version
MlflowClient().set_registered_model_alias(NOME_MODELO, "prod", versao)
print(f"registrado: {NOME_MODELO} versão {versao} com o alias @prod")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8. As métricas, numa tabela que o score, o Genie e o app leem

# COMMAND ----------

metricas = pd.DataFrame([{
    "versao_modelo": int(versao),
    "treinado_em": pd.Timestamp.utcnow().tz_localize(None),
    "auc": float(AUC),
    "auc_classificador": float(AUC_CLASSIFICADOR),
    "auc_baseline_regra": float(auc_baselines["a regra de corte atual (< 0,9)"]),
    "auc_baseline_folga": float(AUC_FOLGA),
    "auc_baseline_cpi": float(auc_baselines["só o CPI"]),
    "auc_baseline_tendencia": float(auc_baselines["a tendência das últimas 4 semanas"]),
    "sigma": SIGMA,
    "semanas_treino": int(len(treino)),
    "semanas_teste": int(len(teste)),
    "estouros_teste": int(ESTOUROS),
    "estouros_avisados": int(AVISADOS),
    "antecedencia_media_dias": float(ANTECEDENCIA),
    "feature_principal": FEATURE_PRINCIPAL,
}])
(spark.createDataFrame(metricas)
      .write.mode("overwrite").option("overwriteSchema", "true")
      .saveAsTable(f"{CATALOGO}.ml.modelo_metricas"))
spark.sql(f"COMMENT ON TABLE {CATALOGO}.ml.modelo_metricas IS "
          "'As métricas do modelo de estouro em 30 dias em produção (@prod): AUC contra as regras simples, "
          "o sigma usado no score e a métrica do dono (estouros avisados no top 5 e com quantos dias de antecedência).'")
display(spark.table(f"{CATALOGO}.ml.modelo_metricas"))
