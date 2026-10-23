import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { useEffect, useState } from 'react';
import { CAUSAS, classeSituacao, indice, milhoes, num, pct, sim } from '../../lib/dados';

interface LinhaScore {
  projeto_id: string | null;
  prob_estouro_30d: string | null;
}

// a chance de estouro vem de uma rota do servidor: se a tabela do modelo faltar, mostra "—"
function useScore() {
  const [score, setScore] = useState<Map<string, number> | null>(null);
  useEffect(() => {
    fetch('/api/score-estouro')
      .then((r) => (r.ok ? r.json() : null))
      .then((corpo: { disponivel?: boolean; linhas?: LinhaScore[] } | null) => {
        if (!corpo?.disponivel) return;
        setScore(new Map((corpo.linhas ?? []).map((l) => [l.projeto_id ?? '', num(l.prob_estouro_30d)])));
      })
      .catch(() => setScore(null));
  }, []);
  return score;
}

function Kpi({ titulo, valor, detalhe }: { titulo: string; valor: string; detalhe: string }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{titulo}</CardDescription>
        <CardTitle className="text-3xl">{valor}</CardTitle>
      </CardHeader>
      <CardContent className="text-xs text-muted-foreground">{detalhe}</CardContent>
    </Card>
  );
}

export function ProjetosPage() {
  const kpis = useAnalyticsQuery('kpis', {});
  const projetos = useAnalyticsQuery('projetos_risco', {});
  const score = useScore();
  const k = kpis.data?.[0];

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Quais projetos estão em risco, e quanto isso custa?</h2>
        <p className="text-sm text-muted-foreground mt-1">
          Fotografia de 16/10/2026 dos projetos em andamento. SPI ou CPI abaixo de 0,9 é atenção, abaixo de 0,8 é
          crítico. Fonte: gold.projeto_situacao_atual e o modelo de estouro em 30 dias (gold.score_estouro_30d),
          recalculados toda segunda às 6h.
        </p>
      </div>

      {kpis.error && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível ler os KPIs</AlertTitle>
          <AlertDescription>{kpis.error}</AlertDescription>
        </Alert>
      )}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {kpis.loading || !k ? (
          [1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-28" />)
        ) : (
          <>
            <Kpi
              titulo="Projetos em risco"
              valor={`${num(k.projetos_em_risco)} de ${num(k.projetos_em_andamento)}`}
              detalhe={`${num(k.projetos_criticos)} críticos · ${num(k.projetos_melancia)} com farol verde e SPI abaixo de 0,9`}
            />
            <Kpi titulo="Estouro previsto" valor={milhoes(k.estouro_previsto)} detalhe="Quanto o custo final deve passar do orçamento" />
            <Kpi titulo="Carteira em andamento" valor={milhoes(k.carteira)} detalhe="Valor de contrato dos projetos em andamento" />
            <Kpi
              titulo="Alto risco em 30 dias"
              valor={String(num(k.alto_risco_30d))}
              detalhe="Projetos com chance de estouro de 50% ou mais, pelo modelo"
            />
          </>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Projetos em andamento, do pior para o melhor</CardTitle>
          <CardDescription>
            O farol do gerente ao lado do farol pelo número: 🍉 é o projeto verde por fora e vermelho por dentro.
            A causa é a mais frequente no status semanal dos últimos 90 dias.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {projetos.loading && <Skeleton className="h-64" />}
          {projetos.error && (
            <Alert variant="destructive">
              <AlertTitle>Não foi possível ler os projetos</AlertTitle>
              <AlertDescription>{projetos.error}</AlertDescription>
            </Alert>
          )}
          {projetos.data && projetos.data.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>Nenhum projeto em andamento</EmptyTitle>
                <EmptyDescription>Confira se o job vertice_farol rodou.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {projetos.data && projetos.data.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Projeto</TableHead>
                  <TableHead>Cliente</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">SPI</TableHead>
                  <TableHead className="text-right">CPI</TableHead>
                  <TableHead className="text-right">Estouro</TableHead>
                  <TableHead className="text-right">Atraso (dias)</TableHead>
                  <TableHead>Farol do gerente</TableHead>
                  <TableHead>Farol pelo número</TableHead>
                  <TableHead>Causa (90 dias)</TableHead>
                  <TableHead className="text-right">P(estouro 30d)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {projetos.data.map((p) => (
                  <TableRow key={p.projeto_id}>
                    <TableCell className="font-medium" title={p.nome_projeto}>
                      {p.projeto_id}
                    </TableCell>
                    <TableCell>{p.cliente}</TableCell>
                    <TableCell>
                      <span className={`rounded px-2 py-0.5 text-xs font-medium ${classeSituacao(p.situacao)}`}>
                        {p.situacao}
                      </span>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{indice(p.spi)}</TableCell>
                    <TableCell className="text-right tabular-nums">{indice(p.cpi)}</TableCell>
                    <TableCell className="text-right tabular-nums">{milhoes(p.estouro_previsto)}</TableCell>
                    <TableCell className="text-right tabular-nums">{num(p.atraso_projetado_dias)}</TableCell>
                    <TableCell>
                      {p.farol_do_gerente ?? '—'}
                      {sim(p.melancia) && ' 🍉'}
                    </TableCell>
                    <TableCell>{p.farol_calculado}</TableCell>
                    <TableCell>{p.causa_principal ? (CAUSAS[p.causa_principal] ?? p.causa_principal) : '—'}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {score?.has(p.projeto_id) ? pct(score.get(p.projeto_id)) : '—'}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
