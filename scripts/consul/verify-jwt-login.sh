#!/usr/bin/env bash
# Verifica a integração ms-auth -> Consul (auth method JWT) na stack do docker-compose.consul.yml.
# Uso: ./scripts/consul/verify-jwt-login.sh   (com a stack no ar)
#
# Registra pelo fluxo de admin do ms-auth um client com flags:write (o ClientSeeder não tem um)
# e confere leitura, escrita e recusas. Requer curl e jq.
set -uo pipefail

AUTH=${AUTH_URL:-http://localhost:9000}
CONSUL=${CONSUL_URL:-http://localhost:8500}
MGMT_TOKEN=${CONSUL_MANAGEMENT_TOKEN:-dev-management-token}
KEY=feature-flags/verify/flag
COMPOSE=(docker compose -f "$(dirname "$0")/../../docker-compose.consul.yml")
failures=0

check() { # check <descrição> <esperado> <obtido>
    if [ "$2" = "$3" ]; then echo "✓ $1"; else echo "✗ $1 (esperado: $2, obtido: $3)"; failures=$((failures + 1)); fi
}

jwt() { # jwt <client> <scope>
    curl -s -u "$1:$1-secret" -d grant_type=client_credentials -d "scope=$2" "$AUTH/oauth2/token" | jq -r .access_token
}

claim() { # claim <jwt> <jq filter>
    local p; p=$(cut -d. -f2 <<<"$1" | tr '_-' '/+')
    while (( ${#p} % 4 )); do p+="="; done   # base64url vem sem padding
    base64 -d <<<"$p" | jq -c "$2"
}

login() { # login <jwt> -> SecretID do token do Consul ("" se recusado)
    curl -s -X POST "$CONSUL/v1/acl/login" -d "{\"AuthMethod\":\"ms-auth\",\"BearerToken\":\"$1\"}" | jq -r '.SecretID // empty' 2>/dev/null
}

status() { # status <método> <token> <caminho> [dados]
    curl -s -o /dev/null -w '%{http_code}' -X "$1" ${2:+-H "X-Consul-Token: $2"} ${4:+-d "$4"} "$CONSUL$3"
}

# Client de escrita pelo fluxo de admin do ms-auth (idempotente)
curl -s -o /dev/null -X POST "$AUTH/auth/register" -H 'Content-Type: application/json' \
    -d '{"username":"admin","email":"admin@dev.local","password":"senha1234","fullName":"Admin"}'
"${COMPOSE[@]}" exec -T auth-postgres psql -q -U "${AUTH_DB_USER:-postgres}" -d ms_auth -c \
    "INSERT INTO authorities (username, authority) VALUES ('admin','ROLE_AUTH_ADMIN') ON CONFLICT DO NOTHING;" >/dev/null
curl -s -o /dev/null -u admin:senha1234 -X POST "$AUTH/auth/admin/clients" -H 'Content-Type: application/json' \
    -d '{"clientId":"ms-feature-flags-management","clientSecret":"ms-feature-flags-management-secret","grantTypes":["client_credentials"],"scopes":["flags:write"]}'
status PUT "$MGMT_TOKEN" "/v1/kv/$KEY" '{"enabled":false}' >/dev/null

READER_JWT=$(jwt order-service flags:read)
check "JWT com flags:read tem aud [\"consul\"]" '["consul"]' "$(claim "$READER_JWT" '[.aud] | flatten')"
check "JWT sem escopo de flags mantém aud = client_id" '["ms-workspace-management"]' \
    "$(claim "$(jwt ms-workspace-management users:admin)" '[.aud] | flatten')"

READER=$(login "$READER_JWT")
check "login com flags:read" "ok" "${READER:+ok}"
check "flags:read lê feature-flags/" 200 "$(status GET "$READER" "/v1/kv/$KEY")"
check "flags:read não escreve em feature-flags/" 403 "$(status PUT "$READER" "/v1/kv/$KEY" x)"
check "flags:read não lê fora de feature-flags/" 403 "$(status GET "$READER" /v1/kv/outra-coisa)"

WRITER=$(login "$(jwt ms-feature-flags-management flags:write)")
check "login com flags:write" "ok" "${WRITER:+ok}"
check "flags:write escreve em feature-flags/" 200 "$(status PUT "$WRITER" "/v1/kv/$KEY" '{"enabled":true}')"
check "flags:write não escreve fora de feature-flags/" 403 "$(status PUT "$WRITER" /v1/kv/outra-coisa x)"

check "sem token não lê" 403 "$(status GET "" "/v1/kv/$KEY")"
check "login recusado sem escopo de flags" "" "$(login "$(jwt ms-workspace-management users:admin)")"
# JWT de leitura com o payload trocado para flags:write, mantendo a assinatura original
IFS=. read -r H P S <<<"$READER_JWT"
FORGED_PAYLOAD=$(claim "$READER_JWT" '.scope = ["flags:write"]' | base64 -w0 | tr '/+' '_-' | tr -d '=')
check "login recusado com JWT adulterado (scope trocado para flags:write)" "" "$(login "$H.$FORGED_PAYLOAD.$S")"

status POST "$READER" /v1/acl/logout >/dev/null
check "token não vale depois do logout" 403 "$(status GET "$READER" "/v1/kv/$KEY")"

status DELETE "$MGMT_TOKEN" "/v1/kv/$KEY" >/dev/null
[ "$failures" -eq 0 ] && echo "Tudo certo." || echo "$failures verificação(ões) falharam."
exit "$failures"
