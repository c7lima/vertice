#!/usr/bin/env bash
# Dá ao app (o service principal dele) acesso de LEITURA à Torre no Unity Catalog.
#
# O app é um usuário: nasce sem acesso a nada. CAN_USE no warehouse dá o computador,
# não o dado. Sem estes GRANT, o build do app falha no typegen com INSUFFICIENT_PERMISSIONS.
#
# Uso:  bash scripts/conceder-acesso.sh <perfil> [nome-do-app]
set -euo pipefail
PERFIL="${1:?informe o profile}"
APP="${2:-minha-torre}"
WAREHOUSE="${WAREHOUSE_ID:-5e59f9f92f866a12}"
export MSYS_NO_PATHCONV=1   # no Git Bash do Windows, /api/... não pode virar um caminho C:/...

SP=$(databricks apps get "$APP" --profile "$PERFIL" -o json \
     | python3 -c "import json, sys; print(json.load(sys.stdin)['service_principal_client_id'])")
echo "service principal do app $APP: $SP"

for GRANT in \
  "GRANT USE CATALOG ON CATALOG lakehouse_vertice TO \`$SP\`" \
  "GRANT USE SCHEMA, SELECT ON SCHEMA lakehouse_vertice.gold TO \`$SP\`" \
  "GRANT USE SCHEMA, SELECT ON SCHEMA lakehouse_vertice.silver TO \`$SP\`"
do
  CORPO=$(python3 -c "import json, sys; print(json.dumps({'statement': sys.argv[1], 'warehouse_id': sys.argv[2], 'wait_timeout': '30s'}))" \
          "$GRANT" "$WAREHOUSE")
  ESTADO=$(databricks api post /api/2.0/sql/statements --json "$CORPO" --profile "$PERFIL" \
           | python3 -c "import json, sys; s = json.load(sys.stdin)['status']; print(s['state'], s.get('error', {}).get('message', ''))")
  echo "$ESTADO · $GRANT"
done
