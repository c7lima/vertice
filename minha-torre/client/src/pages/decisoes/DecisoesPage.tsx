import {
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
import { reais } from '../../lib/dados';

interface Decisao {
  id: number;
  projeto_origem: string;
  projeto_destino: string;
  recurso_id: string;
  decisao: string;
  justificativa: string;
  economia_mes: string | null;
  usuario: string;
  criado_em: string;
}

const quando = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo' });

// a decisão vira dado: o histórico vem do Lakebase pela rota do servidor (não do warehouse)
export function DecisoesPage() {
  const [decisoes, setDecisoes] = useState<Decisao[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/decisoes')
      .then(async (r) => {
        if (!r.ok) throw new Error(((await r.json()) as { erro?: string }).erro ?? `erro ${r.status}`);
        return (await r.json()) as Decisao[];
      })
      .then(setDecisoes)
      .catch((e: unknown) => setErro(e instanceof Error ? e.message : String(e)));
  }, []);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Quem decidiu o quê, e quando?</h2>
        <p className="text-sm text-muted-foreground mt-1">
          Cada Aprovar ou Recusar do simulador vira uma linha no Lakebase (torre.decisoes), com o e-mail de quem clicou
          e o horário. Daqui a três meses: as realocações aprovadas melhoraram o SPI do projeto destino?
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Histórico de decisões</CardTitle>
          <CardDescription>As 200 mais recentes, da mais nova para a mais antiga.</CardDescription>
        </CardHeader>
        <CardContent>
          {!decisoes && !erro && <Skeleton className="h-40" />}
          {erro && (
            <Alert variant="destructive">
              <AlertTitle>Não foi possível ler as decisões</AlertTitle>
              <AlertDescription>{erro}</AlertDescription>
            </Alert>
          )}
          {decisoes && decisoes.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>Nenhuma decisão registrada ainda</EmptyTitle>
                <EmptyDescription>Simule uma realocação e clique em Aprovar ou Recusar.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {decisoes && decisoes.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nº</TableHead>
                  <TableHead>Quando</TableHead>
                  <TableHead>Pessoa: origem → destino</TableHead>
                  <TableHead>Decisão</TableHead>
                  <TableHead>Justificativa</TableHead>
                  <TableHead className="text-right">Ociosidade evitada no mês</TableHead>
                  <TableHead>Por quem</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {decisoes.map((d) => (
                  <TableRow key={d.id}>
                    <TableCell className="font-medium">{d.id}</TableCell>
                    <TableCell>{quando(d.criado_em)}</TableCell>
                    <TableCell>
                      {d.recurso_id}: {d.projeto_origem} → {d.projeto_destino}
                    </TableCell>
                    <TableCell>
                      <span
                        className={`rounded px-2 py-0.5 text-xs font-medium ${
                          d.decisao === 'aprovada' ? 'bg-success/15 text-success' : 'bg-destructive/15 text-destructive'
                        }`}
                      >
                        {d.decisao}
                      </span>
                    </TableCell>
                    <TableCell className="max-w-md whitespace-normal">{d.justificativa}</TableCell>
                    <TableCell className="text-right tabular-nums">{d.economia_mes ? reais(d.economia_mes) : '—'}</TableCell>
                    <TableCell>{d.usuario}</TableCell>
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
