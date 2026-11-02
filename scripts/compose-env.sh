#!/usr/bin/env bash
# Writes .env for docker-compose.yml: three different endpoint keys, the Ops agent key and one test grant for
# scripts/recovery-smoke.py. Keeps an existing .env unless --force. .env is gitignored; never commit it.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ] && [ "${1:-}" != --force ]; then echo ".env exists (scripts/compose-env.sh --force replaces it)"; exit 0; fi
key() { python3 -c 'import secrets; print(secrets.token_hex(24))'; }
grant="grt-local-$(python3 -c 'import secrets; print(secrets.token_hex(4))')"
umask 077
cat > .env <<ENV
PLANNER_KEY=$(key)
ENGINEER_KEY=$(key)
RECOVERY_KEY=$(key)
OPS_AGENT_KEY=$(key)
GRANT=$grant
FAKE_GRANTS=drill-local-0001:restore_kv_secrets_user:$grant
ENV
echo "wrote .env (mode 600). Next: docker compose up -d --build"
