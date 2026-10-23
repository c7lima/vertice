import { createApp, analytics, genie, server } from '@databricks/appkit';
import { buscarScore } from './routes/score';

// Leitura: config/queries/*.sql no SQL warehouse (a gold da Vértice).
// Conversa: o Genie "Farol · Diretoria" do bundle vertice, sob o alias "default".
createApp({
  plugins: [
    analytics(),
    genie({ spaces: { default: process.env.DATABRICKS_GENIE_SPACE_ID ?? '' } }),
    server(),
  ],
  // Sem cache: o dono quer ver o número de agora, não o da última vez que alguém abriu.
  cache: { enabled: false },
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // a chance de estouro em 30 dias (tabela do modelo; "—" se ainda não existir)
      app.get('/api/score-estouro', async (_req, res) => {
        res.json(await buscarScore());
      });
      // quem está perguntando: o proxy do Databricks Apps manda o e-mail de quem fez login
      app.get('/api/whoami', (req, res) => {
        res.json({ email: req.header('x-forwarded-email') ?? null, user: req.header('x-forwarded-user') ?? null });
      });
    });
  },
}).catch(console.error);
