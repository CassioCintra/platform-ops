#!/bin/sh
# Configura o ACL do Consul para as feature flags. Idempotente: pode rodar de novo.
#
# Requer: CONSUL_HTTP_ADDR, CONSUL_HTTP_TOKEN (token de gestão) e MS_AUTH_ISSUER.
set -eu

policy() {
    consul acl policy read -name "$1" >/dev/null 2>&1 \
        || consul acl policy create -name "$1" -rules "$2" >/dev/null
    echo "policy $1 ok"
}

role() {
    consul acl role read -name "$1" >/dev/null 2>&1 \
        || consul acl role create -name "$1" -policy-name "$2" >/dev/null
    echo "role $1 ok"
}

# O selector usa a claim "scope" do JWT do ms-auth, mapeada para list.scopes.
binding_rule() { # binding_rule <bind-type> <bind-name> <scope>
    consul acl binding-rule list -method ms-auth -format json | grep -qF "\"BindName\": \"$2\"" \
        || consul acl binding-rule create -method ms-auth -bind-type "$1" -bind-name "$2" \
               -selector "\"$3\" in list.scopes" >/dev/null
    echo "binding-rule $3 -> $2 ok"
}

policy flags-write 'key_prefix "feature-flags/" { policy = "write" }'
policy flags-admin 'acl = "write"'
role flags-writer flags-write
role flags-administrator flags-admin

# Valida os JWTs pela chave pública do ms-auth (JWKS). Só aceita tokens com aud "consul", que o
# ms-auth emite para os escopos flags:read/flags:write. Tokens do Consul valem no máximo 15 min.
# Cria ou atualiza, para que mudanças aqui cheguem a um Consul já configurado.
AUTH_CONFIG="{
    \"JWKSURL\": \"${MS_AUTH_ISSUER}/oauth2/jwks\",
    \"BoundIssuer\": \"${MS_AUTH_ISSUER}\",
    \"BoundAudiences\": [\"consul\"],
    \"ListClaimMappings\": { \"scope\": \"scopes\" },
    \"ClaimMappings\": { \"sub\": \"client_id\", \"workspace_id\": \"workspace_id\" }
}"
if consul acl auth-method read -name ms-auth >/dev/null 2>&1; then
    consul acl auth-method update -name ms-auth -max-token-ttl 15m -config "$AUTH_CONFIG" >/dev/null
else
    consul acl auth-method create -type jwt -name ms-auth -max-token-ttl 15m -config "$AUTH_CONFIG" >/dev/null
fi
echo "auth-method ms-auth ok"

binding_rule role flags-writer flags:write
binding_rule role flags-administrator flags:admin
# Leitura isolada por workspace: a policy flags-read-<workspace_id> é criada pelo ms-feature-flags-management.
# Sem ela (workspace sem flags), o login é recusado.
binding_rule policy 'flags-read-${value.workspace_id}' flags:read
