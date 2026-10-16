#!/usr/bin/env bash
# Verifica a integração ms-auth -> Consul (auth method JWT) na stack do docker-compose.consul.yml.
# Uso: ./scripts/consul/verify-jwt-login.sh   (com a stack no ar)
#
# Confere o isolamento por workspace: o client order-service (flags:read, workspace de dev) só lê
# feature-flags/<workspace>/, e só depois que a policy do workspace existe. Requer curl e jq.
set -uo pipefail

AUTH=${AUTH_URL:-http://localhost:9000}
CONSUL=${CONSUL_URL:-http://localhost:8500}
MGMT_TOKEN=${CONSUL_MANAGEMENT_TOKEN:-dev-management-token}
WORKSPACE=${ORDER_SERVICE_WORKSPACE_ID:-7a1c0e2e-4d5b-4c8e-9f10-2b3c4d5e6f70}
OTHER_WORKSPACE=0b9d8c7a-6e5f-4a3b-8c2d-1e0f9a8b7c6d
KEY=feature-flags/$WORKSPACE/verify/dev/flag
OTHER_KEY=feature-flags/$OTHER_WORKSPACE/verify/dev/flag
failures=0

# O consul-setup roda em segundo plano depois do "up -d"; espera ele terminar antes de verificar.
docker compose -f "$(dirname "$0")/../../docker-compose.consul.yml" wait consul-setup >/dev/null

check() { # check <descrição> <esperado> <obtido>
    if [ "$2" = "$3" ]; then echo "✓ $1"; else echo "✗ $1 (esperado: $2, obtido: $3)"; failures=$((failures + 1)); fi
}

jwt() { # jwt <client> <scope>
    curl -s -u "$1:$1-secret" -d grant_type=client_credentials --data-urlencode "scope=$2" "$AUTH/oauth2/token" | jq -r .access_token
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

READER_JWT=$(jwt order-service flags:read)
check "JWT com flags:read tem aud [\"consul\"]" '["consul"]' "$(claim "$READER_JWT" '[.aud] | flatten')"
check "JWT do order-service traz o workspace" "\"$WORKSPACE\"" "$(claim "$READER_JWT" '.workspace_id')"
check "JWT sem escopo de flags mantém aud = client_id" '["ms-workspace-management"]' \
    "$(claim "$(jwt ms-workspace-management users:admin)" '[.aud] | flatten')"

POLICY_ID=$(curl -s -H "X-Consul-Token: $MGMT_TOKEN" "$CONSUL/v1/acl/policy/name/flags-read-$WORKSPACE" | jq -r '.ID // empty' 2>/dev/null)
[ -n "$POLICY_ID" ] && status DELETE "$MGMT_TOKEN" "/v1/acl/policy/$POLICY_ID" >/dev/null
check "login de leitura recusado enquanto o workspace não tem policy" "" "$(login "$READER_JWT")"

WRITER=$(login "$(jwt ms-feature-flags-management "flags:write flags:admin")")
check "login com flags:write + flags:admin" "ok" "${WRITER:+ok}"
check "flags:admin cria a policy de leitura do workspace" 200 "$(status PUT "$WRITER" /v1/acl/policy \
    "{\"Name\":\"flags-read-$WORKSPACE\",\"Rules\":\"key_prefix \\\"feature-flags/$WORKSPACE/\\\" { policy = \\\"read\\\" }\"}")"
check "flags:write escreve em feature-flags/" 200 "$(status PUT "$WRITER" "/v1/kv/$KEY" '{"enabled":true}')"
check "flags:write não escreve fora de feature-flags/" 403 "$(status PUT "$WRITER" /v1/kv/outra-coisa x)"
status PUT "$MGMT_TOKEN" "/v1/kv/$OTHER_KEY" '{"enabled":true}' >/dev/null

READER=$(login "$READER_JWT")
check "login com flags:read depois da policy" "ok" "${READER:+ok}"
check "flags:read lê o próprio workspace" 200 "$(status GET "$READER" "/v1/kv/$KEY")"
check "flags:read não lê outro workspace" 403 "$(status GET "$READER" "/v1/kv/$OTHER_KEY")"
check "flags:read não escreve no próprio workspace" 403 "$(status PUT "$READER" "/v1/kv/$KEY" x)"
check "flags:read não lê fora de feature-flags/" 403 "$(status GET "$READER" /v1/kv/outra-coisa)"

check "sem token não lê" 403 "$(status GET "" "/v1/kv/$KEY")"
check "login recusado sem escopo de flags" "" "$(login "$(jwt ms-workspace-management users:admin)")"
# JWT de leitura com o payload trocado para outro workspace, mantendo a assinatura original
IFS=. read -r H P S <<<"$READER_JWT"
FORGED_PAYLOAD=$(claim "$READER_JWT" ".workspace_id = \"$OTHER_WORKSPACE\"" | base64 -w0 | tr '/+' '_-' | tr -d '=')
check "login recusado com JWT adulterado (workspace trocado)" "" "$(login "$H.$FORGED_PAYLOAD.$S")"

status POST "$READER" /v1/acl/logout >/dev/null
check "token não vale depois do logout" 403 "$(status GET "$READER" "/v1/kv/$KEY")"

status DELETE "$MGMT_TOKEN" "/v1/kv/$OTHER_KEY" >/dev/null
status DELETE "$MGMT_TOKEN" "/v1/kv/$KEY" >/dev/null
[ "$failures" -eq 0 ] && echo "Tudo certo." || echo "$failures verificação(ões) falharam."
exit "$failures"
