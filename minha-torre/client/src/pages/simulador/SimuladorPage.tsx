import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Button,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
  Textarea,
} from '@databricks/appkit-ui/react';
import { useMemo, useState } from 'react';
import { CAUSAS, decimal, indice, mil, num, pct, reais } from '../../lib/dados';

const SEMANAS_NO_MES = 4;

function Linha({ rotulo, valor, destaque = false }: { rotulo: string; valor: string; destaque?: boolean }) {
  return (
    <div className="flex items-baseline justify-between border-b py-2 last:border-0">
      <span className="text-sm text-muted-foreground">{rotulo}</span>
      <span className={`tabular-nums ${destaque ? 'text-2xl font-bold text-foreground' : 'text-lg font-semibold'}`}>
        {valor}
      </span>
    </div>
  );
}

export function SimuladorPage() {
  const pessoas = useAnalyticsQuery('pessoas_ociosas', {});
  const projetos = useAnalyticsQuery('projetos_risco', {});
  const [pessoaId, setPessoaId] = useState<string>('');
  const [destinoId, setDestinoId] = useState<string>('');
  const [horasOnboarding, setHorasOnboarding] = useState<number>(40);
  // a decisão: a justificativa, o envio e a resposta do servidor
  const [justificativa, setJustificativa] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [resultado, setResultado] = useState<{ ok: boolean; texto: string } | null>(null);

  // a pessoa escolhida (padrão: a que mais custa parada)
  const pessoa = pessoas.data?.find((p) => p.colaborador_id === pessoaId) ?? pessoas.data?.[0];
  const ehSre = pessoa?.papel === 'sre';

  // só projetos em atenção ou crítico; para SRE, quem mais pede SRE vem primeiro
  const destinos = useMemo(() => {
    const emRisco = (projetos.data ?? []).filter((p) => p.situacao === 'crítico' || p.situacao === 'atenção');
    return ehSre ? [...emRisco].sort((a, b) => num(b.dias_falta_sre) - num(a.dias_falta_sre)) : emRisco;
  }, [projetos.data, ehSre]);
  const destino = destinos.find((p) => p.projeto_id === destinoId) ?? destinos[0];

  if (pessoas.loading || projetos.loading) return <Skeleton className="h-96 w-full max-w-5xl mx-auto" />;
  if (pessoas.error || projetos.error) {
    return (
      <Alert variant="destructive" className="max-w-5xl mx-auto">
        <AlertTitle>Não foi possível ler os dados do simulador</AlertTitle>
        <AlertDescription>{pessoas.error ?? projetos.error}</AlertDescription>
      </Alert>
    );
  }
  if (!pessoa || !destino) {
    return (
      <Empty className="max-w-5xl mx-auto">
        <EmptyHeader>
          <EmptyTitle>Nada para simular</EmptyTitle>
          <EmptyDescription>Ninguém está com utilização abaixo de 20%, ou nenhum projeto está em risco.</EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  // a conta, linha por linha (a mesma do <details> lá embaixo)
  const horasMes = num(pessoa.horas_paradas_semana) * SEMANAS_NO_MES;
  const ociosidadeEvitada = num(pessoa.custo_ocioso_semana) * SEMANAS_NO_MES;
  const diasImpacto90 = ehSre ? num(destino.dias_falta_sre) : num(destino.dias_rotatividade);
  const causaUsada = ehSre ? 'falta_sre' : 'rotatividade';
  const diasRecuperados = (diasImpacto90 / 90) * 30;
  const mobilizacao = num(horasOnboarding) * num(pessoa.custo_hora);
  const saldo = ociosidadeEvitada - mobilizacao;

  // grava a decisão no Lakebase (POST /api/decisoes), com a conta que está na tela
  async function decidir(decisao: 'aprovada' | 'recusada') {
    if (!pessoa || !destino) return;
    setEnviando(true);
    setResultado(null);
    try {
      const resposta = await fetch('/api/decisoes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          projeto_origem: pessoa.projeto_id,
          projeto_destino: destino.projeto_id,
          recurso_id: pessoa.colaborador_id,
          tipo: 'pessoa',
          decisao,
          justificativa,
          horas_recuperadas_mes: Math.round(horasMes * 10) / 10,
          economia_mes: Math.round(ociosidadeEvitada * 100) / 100,
          dias_recuperados: Math.round(diasRecuperados * 10) / 10,
        }),
      });
      const corpo = (await resposta.json()) as { id?: number; decisao?: string; usuario?: string; erro?: string };
      if (resposta.ok) {
        setResultado({ ok: true, texto: `Decisão nº ${corpo.id} ${corpo.decisao} e registrada por ${corpo.usuario}` });
        setJustificativa('');
      } else {
        setResultado({ ok: false, texto: corpo.erro ?? `O servidor recusou a decisão (${resposta.status})` });
      }
    } catch (erro) {
      setResultado({ ok: false, texto: erro instanceof Error ? erro.message : 'Falha de rede ao gravar a decisão' });
    } finally {
      setEnviando(false);
    }
  }
  const podeDecidir = justificativa.trim().length >= 10 && !enviando;

  return (
    <div className="space-y-6 w-full max-w-5xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Tenho gente parada enquanto outro projeto pede gente?</h2>
        <p className="text-sm text-muted-foreground mt-1">
          Escolha uma pessoa com utilização abaixo de 20% nas últimas 12 semanas e um projeto em risco. A conta mostra
          de onde vem cada número.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>A realocação</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="space-y-2">
            <Label>Pessoa parada</Label>
            <Select value={pessoa.colaborador_id} onValueChange={(v) => { setPessoaId(v); setDestinoId(''); }}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {(pessoas.data ?? []).map((p) => (
                  <SelectItem key={p.colaborador_id} value={p.colaborador_id}>
                    {p.colaborador_id} · {p.nome} ({p.papel}, {p.projeto_id}, uso {pct(p.utilizacao)})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Projeto destino (em risco)</Label>
            <Select value={destino.projeto_id} onValueChange={setDestinoId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {destinos.map((p) => (
                  <SelectItem key={p.projeto_id} value={p.projeto_id}>
                    {p.projeto_id} · {p.situacao} · SPI {indice(p.spi)}
                    {num(p.dias_falta_sre) > 0 ? ` · ${decimal(p.dias_falta_sre, 0)} dias de falta de SRE` : ''}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="onboarding">Horas de onboarding</Label>
            <Input
              id="onboarding"
              type="number"
              min={0}
              value={horasOnboarding}
              onChange={(e) => setHorasOnboarding(num(e.target.value))}
            />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>
            {pessoa.nome} → {destino.projeto_id}
          </CardTitle>
          <CardDescription>
            {pessoa.papel} {pessoa.senioridade}, hoje no {pessoa.projeto_id} com {pct(pessoa.utilizacao, 1)} de
            utilização. O {destino.projeto_id} está em {destino.situacao}; causa mais frequente no status:{' '}
            {destino.causa_principal ? (CAUSAS[destino.causa_principal] ?? destino.causa_principal) : 'nenhuma'}.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Linha rotulo="Horas que passam a ser usadas no mês" valor={`${decimal(horasMes, 0)} h`} />
          <Linha rotulo="Ociosidade que deixa de ser paga no mês" valor={mil(ociosidadeEvitada)} />
          <Linha rotulo="Mobilização (onboarding)" valor={`− ${mil(mobilizacao)}`} />
          <Linha rotulo="Saldo no mês" valor={mil(saldo)} destaque />
          <Linha
            rotulo={`Dias de cronograma recuperados no mês (${CAUSAS[causaUsada]})`}
            valor={`${decimal(diasRecuperados, 1)} dias`}
          />
          <details className="mt-4 text-sm text-muted-foreground">
            <summary className="cursor-pointer font-medium text-foreground">Como a conta é feita</summary>
            <ul className="mt-2 list-disc space-y-1 pl-5">
              <li>
                Horas no mês = horas paradas por semana ({decimal(pessoa.horas_paradas_semana, 1)} h, média das últimas 12
                semanas) × {SEMANAS_NO_MES} semanas.
              </li>
              <li>
                Ociosidade evitada = custo ocioso por semana ({reais(pessoa.custo_ocioso_semana)}) × {SEMANAS_NO_MES}{' '}
                semanas: é o salário que hoje é pago sem trabalho no projeto.
              </li>
              <li>
                Mobilização = {num(horasOnboarding)} horas de onboarding × custo/hora ({reais(pessoa.custo_hora)}).
              </li>
              <li>Saldo = ociosidade evitada − mobilização.</li>
              <li>
                Dias recuperados = dias de impacto por {CAUSAS[causaUsada]} declarados no status do {destino.projeto_id} nos
                últimos 90 dias ({decimal(diasImpacto90, 0)} dias) ÷ 90 × 30. Fica fora do saldo em R$: dia de cronograma
                só vira dinheiro com uma premissa (multa, receita adiada) que o dono precisa escolher.
              </li>
            </ul>
          </details>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>A decisão</CardTitle>
          <CardDescription>
            Aprovar ou recusar grava a decisão no Lakebase, com o seu e-mail e o horário. Ela aparece na tela Decisões.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="space-y-2">
            <Label htmlFor="justificativa">Justificativa (mínimo de 10 caracteres)</Label>
            <Textarea
              id="justificativa"
              rows={3}
              maxLength={1000}
              value={justificativa}
              onChange={(e) => setJustificativa(e.target.value)}
              placeholder={`Por que mover ${pessoa.colaborador_id} do ${pessoa.projeto_id} para o ${destino.projeto_id}?`}
            />
          </div>
          <div className="flex gap-2">
            <Button disabled={!podeDecidir} onClick={() => void decidir('aprovada')}>
              Aprovar
            </Button>
            <Button variant="outline" disabled={!podeDecidir} onClick={() => void decidir('recusada')}>
              Recusar
            </Button>
          </div>
          {resultado && (
            <Alert variant={resultado.ok ? 'default' : 'destructive'}>
              <AlertTitle>{resultado.ok ? 'Decisão registrada' : 'A decisão não foi gravada'}</AlertTitle>
              <AlertDescription>{resultado.texto}</AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
