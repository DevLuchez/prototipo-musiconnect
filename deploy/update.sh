#!/bin/sh
# Atualiza o servidor com a última versão da main (chamado pelo deploy
# automático do GitHub Actions, ou à mão: /opt/musiconnect/deploy/update.sh).
#
# Só reconstrói o que mudou:
#   back_musiconnect/ ou docker-compose*.yml → reconstrói e reinicia a API
#   deploy/Caddyfile                         → recarrega o Caddy
#   deploy/site/                             → nada (o Caddy lê direto da pasta)
#
# O servidor nunca edita arquivos do repositório: o código é sempre o da
# main. O .env (fora do Git) não é afetado.
set -eu

cd /opt/musiconnect
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

OLD=$(git rev-parse HEAD)
git fetch -q origin main
git reset -q --hard origin/main
NEW=$(git rev-parse HEAD)
echo "Versão: $(git log -1 --format='%h %s')"

changed() {
    ! git diff --quiet "$OLD" "$NEW" -- "$@"
}

if changed back_musiconnect docker-compose.yml docker-compose.prod.yml; then
    echo "API ou compose mudaram — reconstruindo..."
    $COMPOSE up -d --build
    docker image prune -f >/dev/null
fi

if changed deploy/Caddyfile; then
    echo "Caddyfile mudou — recarregando o Caddy..."
    docker exec musiconnect_caddy caddy reload --config /etc/caddy/Caddyfile
fi

# Confere se a API voltou a responder.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if docker exec musiconnect_caddy wget -qO- http://api:8000/ >/dev/null 2>&1; then
        echo "API no ar."
        exit 0
    fi
    sleep 5
done
echo "A API não respondeu depois da atualização." >&2
exit 1
