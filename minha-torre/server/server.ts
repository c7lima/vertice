import { createApp, analytics, genie, lakebase, server } from '@databricks/appkit';
import { buscarScore } from './routes/score';
import {
  type Consulta,
  DecisaoSchema,
  criarTabela,
  gravarDecisao,
  listarDecisoes,
  usuarioDaRequisicao,
} from './routes/decisoes';

// Leitura: config/queries/*.sql no SQL warehouse (a gold da Vértice).
// Conversa: o Genie "Farol · Diretoria" do bundle vertice, sob o alias "default".
// Escrita: as decisões de realocação no Lakebase (Postgres), tabela torre.decisoes.
createApp({
  plugins: [
    analytics(),
    genie({ spaces: { default: process.env.DATABRICKS_GENIE_SPACE_ID ?? '' } }),
    lakebase(),
    server(),
  ],
  // Sem cache: o dono quer ver o número de agora, não o da última vez que alguém abriu.
  cache: { enabled: false },
  async onPluginsReady(appkit) {
    const consulta: Consulta = (sql, params) => appkit.lakebase.query(sql, params);

    // o app cria o próprio schema na subida (o service principal não enxerga o public)
    try {
      await criarTabela(consulta);
      console.log('[decisoes] torre.decisoes pronta');
    } catch (erro) {
      console.warn('[decisoes] não consegui criar a tabela:', erro instanceof Error ? erro.message : erro);
    }

    appkit.server.extend((app) => {
      // a chance de estouro em 30 dias (tabela do modelo; "—" se ainda não existir)
      app.get('/api/score-estouro', async (_req, res) => {
        res.json(await buscarScore());
      });

      // quem está perguntando: o proxy do Databricks Apps manda o e-mail de quem fez login
      app.get('/api/whoami', (req, res) => {
        res.json({ email: req.header('x-forwarded-email') ?? null, user: req.header('x-forwarded-user') ?? null });
      });
      app.get('/api/quem-sou', (req, res) => {
        res.json({ usuario: usuarioDaRequisicao(req) });
      });

      // o histórico: as 200 decisões mais recentes
      app.get('/api/decisoes', async (_req, res) => {
        try {
          res.json(await listarDecisoes(consulta));
        } catch (erro) {
          console.error('[decisoes] listar', erro);
          res.status(500).json({ erro: 'Não consegui ler as decisões' });
        }
      });

      // a decisão: validada pelo zod antes de chegar no banco
      app.post('/api/decisoes', async (req, res) => {
        const validacao = DecisaoSchema.safeParse(req.body);
        if (!validacao.success) {
          res.status(400).json({ erro: validacao.error.issues[0]?.message ?? 'Decisão inválida' });
          return;
        }
        if (validacao.data.projeto_origem === validacao.data.projeto_destino) {
          res.status(400).json({ erro: 'Origem e destino são o mesmo projeto' });
          return;
        }
        try {
          res.status(201).json(await gravarDecisao(consulta, validacao.data, usuarioDaRequisicao(req)));
        } catch (erro) {
          console.error('[decisoes] gravar', erro);
          res.status(500).json({ erro: 'Não consegui gravar a decisão' });
        }
      });
    });
  },
}).catch(console.error);
