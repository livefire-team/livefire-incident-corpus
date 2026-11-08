# WS3: MCP server, evidence corpus and GitHub controls

Workstream 3 of LiveFire Fusion, extracted to drop into another repository. It gives the drill's three AI agents
their tools, and nothing else:

- **`/planner/mcp`**: nine read-only evidence tools (telemetry, identity, secret metadata, app configuration, SQL
  network rules, incident history, runbooks, repository files, commit history).
- **`/engineer/mcp`**: six branch-only repository tools (a `candidate/<drill>-<attempt>` branch, a patch to two
  allowed files, a regression test, a runbook update, CI status).
- **`/recovery/mcp`**: two grant-gated tools that execute one approved recovery action through WS2's Ops Service and
  check the twin's drift.

Every call is authenticated per endpoint, checked against a server-side allowlist, wrapped as untrusted data,
redacted, and written to the drill's audit trail with its tool version, caller, authorization result and source. This is the code that ran in Azure on Nov 1–2, 2026, with real
Foundry agents completing every Autonomous drill scenario.

**What it does in the whole system, with diagrams, and the Azure services and tools it uses: [ARCHITECTURE.md](ARCHITECTURE.md).**
**How other workstreams call it: [CONTRACT.md](CONTRACT.md).** Per-tool reference:
[contracts/mcp-tools.md](contracts/mcp-tools.md). Machine-readable schemas:
[contracts/mcp-tools.schema.json](contracts/mcp-tools.schema.json).

## What's in this folder

| Path | What it is |
| --- | --- |
| `src/mcp-server/` | The server (Python 3.12, MCP SDK, Starlette): `app/`, the fixtures for laptop runs, 68 tests, `Dockerfile` |
| `src/mcp-server/app/planner_tools.py`, `engineer_tools.py`, `recovery_tools.py` | The three tool registries |
| `src/mcp-server/app/guard.py` | Allowlists, the result envelope, redaction, refusals, the audit record |
| `src/mcp-server/app/entra_auth.py` | Entra mode: validates each agent identity's token |
| `src/mcp-server/app/backends/` | `azure.py` (Log Analytics, ARM, Key Vault, SQL, AI Search), `github.py` (GitHub Apps), `fixtures.py` (offline) |
| `evidence-corpus/` | The curated incidents and runbook the Planner searches (8 records, one with a planted instruction for T-08) |
| `contracts/` | The tool contract, its generated schemas, and WS2's Ops actions contract that `/recovery` depends on |
| `infra/modules/mcp.bicep` | The MCP Container App, its identity and roles, and the AI Search service |
| `infra/modules/mcp-twin-access.bicep` | The evidence tools' read roles on the twin |
| `infra/main.wiring.example.bicep` | How a `main.bicep` calls the two modules, with each input's source |
| `.github/workflows/mcp-server.yml` | CI: tests, Bandit, Semgrep, pip-audit, gitleaks, Trivy; pushes the image through OIDC |
| `github/CODEOWNERS.snippet` | The protected paths to add to your CODEOWNERS |
| `docker-compose.yml` | The server and the stand-in Ops Service in containers, plus an opt-in `smoke` service |
| `scripts/compose-env.sh` | Writes `.env` for Compose: fresh endpoint keys and a test grant (gitignored, mode 600) |
| `scripts/run-local.sh` | The same without Docker: the server on fixtures plus a stand-in Ops Service, then both smoke tests |
| `scripts/mcp-smoke.py`, `recovery-smoke.py` | Smoke tests, against a local or deployed server |
| `scripts/fake-ops.py` | A local stand-in for WS2's Ops Service (recover, attempt_unsafe, check_drift) |
| `scripts/load-incidents.py` | Builds and loads the AI Search index from `evidence-corpus/` |
| `scripts/export-tool-schemas.py` | Regenerates `contracts/mcp-tools.schema.json` from the code |
| `scripts/create-secrets.sh`, `setup-github.sh`, `setup-entra.sh` | One-time setup: Key Vault secrets, GitHub rulesets, Entra mode |

## Run it on a laptop (no Azure, no GitHub)

### With Docker only

```bash
scripts/compose-env.sh                 # once: .env with three fresh endpoint keys and a test grant
docker compose up -d --build           # the MCP server on http://127.0.0.1:8100, plus the stand-in Ops Service
curl http://127.0.0.1:8100/health      # {"status":"up","backend":"fixtures","auth":"key"}
docker compose run --rm smoke          # ends with SMOKE TEST PASSED and RECOVERY SMOKE TEST PASSED
docker compose exec mcp-server cat /home/appuser/evidence/drill-local-0001/events.jsonl   # the audit trail
docker compose down -v                 # stop, and delete the audit volume
```

The keys for your own client are in `.env`. The test grant works once: to rerun the smoke service, run
`docker compose restart fake-ops` first. Ports are published on 127.0.0.1 only.

### With Python

```bash
python3.12 -m venv .venv && . .venv/bin/activate
pip install -r src/mcp-server/requirements.txt pytest
(cd src/mcp-server && pytest -q)          # 68 passed
scripts/run-local.sh                      # ends with SMOKE TEST PASSED and RECOVERY SMOKE TEST PASSED
scripts/run-local.sh --serve              # keep it running and print the three keys, for your own client
```

`run-local.sh` generates three endpoint keys, starts the server with `BACKEND=fixtures` and
`EVENT_SOURCE=dir:./evidence`, starts `fake-ops.py` with one valid grant, and runs:

- `mcp-smoke.py`: lists every endpoint's tools, calls every Planner tool, and proves a key for one endpoint gets 403
  on the others;
- `recovery-smoke.py`: a valid grant executes, the same grant again is refused, `check_recovery` answers, and the
  Planner's key gets 403 on `/recovery`.

The audit trail is then in `evidence/<drill-id>/events.jsonl`.

## Move it into your team's repo

Copy the folders to the same places at your repo's root, so the paths in the tests, scripts and CI keep working:

```bash
cp -r src/mcp-server <repo>/src/
cp -r evidence-corpus contracts scripts <repo>/          # merge with existing folders of the same name
cp infra/modules/mcp*.bicep <repo>/infra/modules/
cp .github/workflows/mcp-server.yml <repo>/.github/workflows/
cp docker-compose.yml <repo>/docker-compose.ws3.yml      # optional: docker compose -f docker-compose.ws3.yml ...
```

Then:

1. **CODEOWNERS:** add the lines from `github/CODEOWNERS.snippet`, with a real team or username.
2. **gitleaks:** if your repo already has a `.gitleaks.toml`, add this folder's two allowlists to it; otherwise copy
   it. The CI's secret scan reads it.
3. **Bicep:** add the two module blocks from `infra/main.wiring.example.bicep` to your `main.bicep`, mapping each
   input to your own outputs (the comments say which workstream provides each one).
4. **Ops Service:** `/recovery/mcp` calls WS2's Ops Service. If yours differs, match `contracts/ops-actions.md`
   (or adapt `OpsClient` in `recovery_tools.py`).
5. **Repository layout:** the Planner reads `src/order-service/**` and `runbooks/*.md` (never `docs/` or `CLAUDE.md`: POC ADR-004); the Engineer
   writes only `src/order-service/app/secret_provider.py`, `src/order-service/app/db.py`,
   `src/order-service/tests/test_*.py` and `runbooks/*.md`. If your service under test lives elsewhere, change
   `READ_PATHS` (`planner_tools.py`) and `CODE_PATHS`/`TEST_PATHS`/`RUNBOOK_PATHS` (`engineer_tools.py`), keep WS4's
   `ENGINEER_WRITE_PATHS` the same, bump the contract version, and rerun `scripts/export-tool-schemas.py`.
6. Run the tests from `src/mcp-server` and `scripts/run-local.sh` again in the new repo.

## Deploy to Azure

Prerequisites from the other workstreams: WS2's platform (Container Apps environment, private registry and its
pull identity, control Key Vault, evidence storage, Ops Service) and WS1's twin. See CONTRACT.md, section 8.

1. **GitHub Apps** (Build Steps section 3). Create two GitHub Apps installed on the repo only:
   - **Planner:** Contents read, Metadata read.
   - **Engineer:** Contents read and write, Actions read, Metadata read.

   Note each App's **App ID** and **installation ID**. The installation ID is a **number**, at the end of the
   installation's URL, or from `gh api /orgs/<org>/installations`. Don't use the App's Client ID (`Iv23…`): with it,
   every GitHub tool fails.
2. **Secrets** in the control Key Vault: the three endpoint keys, `ops-agent-key` (if WS2 hasn't created it), and
   both Apps' private keys:

   ```bash
   scripts/create-secrets.sh <control-vault> planner-app.pem engineer-app.pem
   ```
3. **Image:** CI pushes `<registry>/mcp-server:sha-<commit>` on every push to `main` (OIDC through the `acr-push`
   environment; repo variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACR_NAME`,
   `ACR_SERVER`). Or build and push it yourself from `src/mcp-server`.
4. **Deploy** your `main.bicep` with the two modules (key mode first). The module creates `ca-mcp`, its identity
   `id-lf-mcp` (Key Vault Secrets User on the control vault, Storage Blob Data Contributor on evidence, AI Search
   roles), and the AI Search service. `mcp-twin-access.bicep` adds read roles on the twin: Log Analytics Reader,
   Reader on the vault, the SQL server and the order app, and secret metadata only: Key Vault Reader on an RBAC vault, or
   an access policy with secrets `list` (never `get`) on an access-policy vault. Pass the twin's `kvPermissionModel`.
   If a region is out of AI Search capacity, set `searchLocation` to another region.
5. **Load the incident index** on every rebuild, for example in your post-provision hook:

   ```bash
   python scripts/load-incidents.py --endpoint "$SEARCH_ENDPOINT"          # keyword (BM25)
   python scripts/load-incidents.py --endpoint "$SEARCH_ENDPOINT" \
     --embedding-endpoint "$OPENAI_ENDPOINT" --embedding-deployment text-embedding-3-small   # hybrid, once WS4
   ```

   Use the Foundry account's own endpoint (`https://<account>.cognitiveservices.azure.com`) for embeddings. A
   recreated account's legacy `<account>.openai.azure.com` host can answer "Subdomain does not map to a resource".
6. **Smoke-test the deployed server** in key mode, with the keys from Key Vault:

   ```bash
   MCP_URL=<mcp.bicep output mcpUrl> PLANNER_KEY=... ENGINEER_KEY=... RECOVERY_KEY=... \
     python scripts/mcp-smoke.py drill-deploy-check
   ```
7. **GitHub rulesets** (after the service under test's seeded commits are on `main`):
   `scripts/setup-github.sh <owner>/<repo>`. Rulesets on a **private** repo need GitHub Team (or Pro), a plan
   feature rather than a paid security add-on. On GitHub Free, the MCP server's own branch and path enforcement is
   the only control on the Engineer's writes; record that residual risk.
8. **Entra mode (the target)**, once WS4 has the three agent identities:
   `scripts/setup-entra.sh <planner-oid> <engineer-oid> <recovery-oid>`. Then redeploy with `authMode: 'entra'`,
   `mcpClientId` and the three object IDs. From then on only those identities get in, and a person's token gets 401.
9. **Code freeze:** pin `repoRef` to the rehearsal's base commit instead of `main`.

## Configuration

| Setting | Meaning |
| --- | --- |
| `BACKEND` | `fixtures` (laptop) or `azure` |
| `AUTH_MODE` | `key` or `entra` |
| `PLANNER_KEY`, `ENGINEER_KEY`, `RECOVERY_KEY` | Key mode: the three endpoint keys (different, ≥ 32 characters) |
| `ENTRA_TENANT_ID`, `MCP_CLIENT_ID`, `PLANNER_AGENT_OBJECT_ID`, `ENGINEER_AGENT_OBJECT_ID`, `RECOVERY_AGENT_OBJECT_ID` | Entra mode |
| `EVENT_SOURCE` | Where audit events go: `dir:<path>` or `blob:https://<account>.blob.core.windows.net/<container>` |
| `MCP_ALLOWED_HOSTS` | Host names the server answers to (default `127.0.0.1:*,localhost:*`; `mcp.bicep` sets its FQDN) |
| `REPO_REF` | The branch or commit the tools read and branch from (`main` until code freeze) |
| `GITHUB_REPO` | `owner/name` |
| `GITHUB_PLANNER_APP_ID`, `GITHUB_PLANNER_INSTALLATION_ID`, `GITHUB_PLANNER_PRIVATE_KEY` (or `GITHUB_PLANNER_TOKEN`) | The Planner's GitHub credential; the same three for `ENGINEER` |
| `OPS_URL`, `OPS_AGENT_KEY` | The Ops Service, for `/recovery`; without `OPS_URL` both recovery tools refuse |
| `LOG_ANALYTICS_WORKSPACE_ID`, `TWIN_KEYVAULT_ID`, `APP_IDENTITY_PRINCIPAL_ID`, `ORDER_APP_NAME`, `TWIN_SQL_SERVER_NAME`, `DESIRED_SQL_DB_NAME`, `TWIN_SECRET_NAME` | The twin the evidence tools read (Azure backend) |
| `SEARCH_ENDPOINT`, `SEARCH_INDEX`, `SEARCH_VECTOR_FIELD` | AI Search (`content_vector` once the index is hybrid) |
| `AZURE_CLIENT_ID` | The managed identity the server signs in to Azure with |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Optional: OpenTelemetry to Application Insights |
| `FIXTURES`, `KNOWLEDGE_DIR` | Fixtures backend only: the evidence file, and findings earlier local drills left |

## Security controls, in short

- One credential per endpoint. A credential for another endpoint gets 403, recorded as a deny event (T-03).
- Server-side allowlists for every path and branch; the agents never hold the GitHub or Azure credentials (T-04).
- All tool output is marked untrusted and redacted. The corpus's planted instruction (INC-1055) causes no tool call
  (T-08).
- The Recovery tools pass on a single-use grant they can't forge or read. The grant is never logged.
- Fixed telemetry queries only; secret values never leave Key Vault (metadata only).
- The image runs as a non-root user; CI scans code, dependencies, secrets and the image.

## Verified for this extract (Nov 2, 2026)

In a clean Python 3.12 environment, from this folder alone:
- 68 tests pass.
- `docker compose up` plus the `smoke` service: both smoke tests pass, and the audit trail is written.
- `scripts/run-local.sh`: both smoke tests pass.
- The Docker image builds, runs and passes the smoke test.
- Both Bicep modules and the wiring example compile.
- Bandit, Semgrep, pip-audit and gitleaks are clean.
- `load-incidents.py --dry-run` finds all 8 records.

The Azure path (real Log Analytics, Key Vault, SQL, AI Search, GitHub Apps and the Ops Service) is the same code
that ran the Azure drills; it hasn't been redeployed from this folder.
