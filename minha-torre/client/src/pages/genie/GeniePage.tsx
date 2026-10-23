import { Badge, GenieChat } from '@databricks/appkit-ui/react';
import { useEffect, useState } from 'react';

export function GeniePage() {
  // quem está perguntando: o e-mail vem do login do workspace (proxy do Databricks Apps)
  const [eu, setEu] = useState<{ email?: string | null } | null>(null);
  useEffect(() => {
    fetch('/api/whoami')
      .then((r) => (r.ok ? r.json() : null))
      .then(setEu)
      .catch(() => setEu(null));
  }, []);

  return (
    <div className="space-y-4 w-full max-w-4xl mx-auto">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 className="text-2xl font-bold text-foreground">Perguntar</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Pergunte em português ao Genie “Farol · Diretoria”. Exemplos: “Por que o PRJ-011 atrasou?”, “O que vai dar
            errado no próximo mês?”, “Quanto esse atraso vai me custar?”
          </p>
        </div>
        <Badge variant="secondary">{eu?.email ?? 'login do workspace'}</Badge>
      </div>
      <p className="text-xs text-muted-foreground">
        As perguntas rodam com as SUAS permissões no Unity Catalog (o app usa o Genie em seu nome). Cada resposta mostra
        o SQL que o Genie gerou: as respostas são geradas por IA, confira o SQL antes de decidir.
      </p>
      <div className="h-[min(640px,72vh)] border rounded-lg overflow-hidden">
        <GenieChat alias="default" />
      </div>
    </div>
  );
}
