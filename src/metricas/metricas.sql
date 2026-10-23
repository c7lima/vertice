-- gold.mv_projetos: a fórmula de cada KPI num lugar só (metric view).
--
-- A metric view guarda a FÓRMULA, não o número. MEASURE(cpi) no Genie, no SQL e no app é
-- sempre SUM(ev) / SUM(ac), recalculado no grão que a pergunta pedir (projeto, cliente,
-- segmento, ferramenta, carteira). Razão não se soma: o CPI da carteira é a soma do EV
-- dividida pela soma do AC, nunca a média dos CPIs.
--
-- comment e synonyms são para o Genie: "índice de custo" passa a significar CPI.
-- ATENÇÃO: a sql_task do job corta o arquivo em todo ponto e vírgula, inclusive dentro do
-- YAML entre os cifrões. Nenhum ponto e vírgula daqui até o fim, nem em comentário.

CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos
WITH METRICS
LANGUAGE YAML
COMMENT 'KPIs dos projetos em andamento na fotografia de hoje (16/10/2026), calculados sobre as tarefas das 3 ferramentas. Regras de corte: SPI ou CPI abaixo de 0,9 é atenção, abaixo de 0,8 é crítico.'
AS $$
version: 1.1
source: lakehouse_vertice.gold.projeto_situacao_atual
filter: status = 'em_andamento'
dimensions:
  - name: projeto_id
    expr: projeto_id
    comment: Código do projeto, como PRJ-011
    synonyms: [código do projeto, projeto]
  - name: projeto
    expr: projeto
    comment: Identificação do projeto (o mesmo código do projeto_id)
  - name: cliente
    expr: cliente
    synonyms: [conta, empresa cliente]
  - name: segmento
    expr: segmento
    comment: varejo, financeiro, saude, logistica ou industria
    synonyms: [setor, vertical]
  - name: ferramenta
    expr: ferramenta
    comment: Onde o projeto é gerenciado - excel, clickup ou msproject
    synonyms: [sistema de gestão, ferramenta de gestão]
  - name: situacao
    expr: situacao
    comment: ok, atenção ou crítico, pela regra de corte de SPI e CPI
    synonyms: [status de risco, saúde do projeto]
  - name: farol_do_gerente
    expr: farol_do_gerente
    comment: Farol publicado pelo gerente no status desta sexta - verde, amarelo ou vermelho
    synonyms: [farol, farol do status]
  - name: farol_calculado
    expr: farol_calculado
    comment: Farol pela regra do manual - verde com SPI a partir de 0,95, amarelo a partir de 0,90, vermelho abaixo
    synonyms: [farol pelo número, farol real]
  - name: gerente_projeto
    expr: gerente_projeto
    synonyms: [gerente, gestor do projeto]
measures:
  - name: projetos
    expr: COUNT(1)
    comment: Quantidade de projetos em andamento
    synonyms: [quantidade de projetos, número de projetos]
  - name: carteira
    expr: SUM(valor_contrato)
    comment: Valor de contrato somado, em reais
    synonyms: [valor da carteira, valor contratado, receita contratada]
  - name: spi
    expr: SUM(ev) / SUM(pv)
    comment: Índice de desempenho de prazo, a soma do EV dividida pela soma do PV. Abaixo de 1 é atraso
    synonyms: [índice de prazo, desempenho de prazo, schedule performance index]
  - name: cpi
    expr: SUM(ev) / SUM(ac)
    comment: Índice de desempenho de custo, a soma do EV dividida pela soma do AC. Abaixo de 1 é estouro de custo
    synonyms: [índice de custo, desempenho de custo, cost performance index]
  - name: eac
    expr: SUM(eac)
    comment: Estimativa no término, o custo final projetado, em reais
    synonyms: [custo projetado, estimativa no término]
  - name: estouro_previsto
    expr: SUM(estouro_previsto)
    comment: Quanto o custo final deve passar do orçamento, em reais. É o custo do atraso
    synonyms: [estouro, custo do atraso, prejuízo previsto]
  - name: margem_projetada
    expr: (SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)
    comment: Margem esperada no fim, em fração do valor de contrato
    synonyms: [margem, margem prevista]
  - name: atraso_projetado_medio_dias
    expr: AVG(atraso_projetado_dias)
    comment: Atraso médio projetado no término, em dias
    synonyms: [atraso médio, dias de atraso]
  - name: projetos_em_risco
    expr: COUNT(1) FILTER (WHERE situacao IN ('atenção', 'crítico'))
    comment: Projetos em atenção ou críticos
    synonyms: [projetos atrasados, projetos em risco]
  - name: projetos_criticos
    expr: COUNT(1) FILTER (WHERE situacao = 'crítico')
    comment: Projetos com SPI ou CPI abaixo de 0,8
    synonyms: [críticos]
  - name: projetos_melancia
    expr: COUNT(1) FILTER (WHERE melancia)
    comment: Projetos com farol do gerente verde e SPI abaixo de 0,9 - verdes por fora, vermelhos por dentro
    synonyms: [melancias, farol mentiroso, farol enganoso]
$$
