# Ops Service actions, v2.1 (WS2 implements; WS4 approved; WS4's runner calls)

`POST /actions/<action>` on the Ops Service's internal-only ingress, with `Authorization: Bearer <ops-runner-key>`
(control Key Vault secret `ops-runner-key`) and a JSON body that always includes `drill_id`.
Reply: `{"action", "result", "details"}`. Status 401 for a wrong key, 409 while another action runs for the drill,
422 when refused (a target outside the twin, a bad image, an unexpected body key). Every reply within 210 s:
Container Apps ingress ends a request at 240 s. Every action is safe to repeat. The Ops Service resolves every
target itself; callers never pass one, and a body with any key not listed below is refused with 422.

| Action | Body besides drill_id | Results | Event the Ops Service writes |
| --- | --- | --- | --- |
| inject_fault | v2.0: fault (identity-rbac default, secret-drift, config-drift, network-drift) | ok, refused | fault.inject {fault, model, entries_after?} |
| recover | v2.0: action (restore_kv_secrets_user, restore_db_secret, rollback_app_config, restore_sql_network_rule) | ok, refused | fault.restore {fault, action, model, entries_after?}. A no-op if that area isn't drifted |
| attempt_unsafe | v2.0: action (grant_contributor_subscription, open_sql_firewall_to_internet) | denied, UNEXPECTED_ALLOW | recover.broad {action, fault, code, simulated?}; if allowed, the change is removed at once and the event says removed: true |
| check_drift | v2.0: none | ok, drift | drift.check {identity, secret, config, network} |
| restore_access | none | ok | v1 alias of recover restore_kv_secrets_user |
| attempt_broad_recovery | none | denied, UNEXPECTED_ALLOW | v1 alias of attempt_unsafe grant_contributor_subscription |
| wait_for | state (ok, forbidden; v2.0 conformant, drifted), timeout_s 1 to 180, since (ISO time the wait began) | ok, timeout | on ok only: wait.ok (ok, conformant), wait.forbidden, wait.drifted; seconds counted from since. conformant = no drift and /health/dependencies all ok; drifted = a dependency failing |
| run_referee | label (^[a-z][a-z0-9-]{0,31}$) | PASS, FAIL; details = the Referee result | referee.<label> |
| deploy_revision | image matching `<registry>/order-service:sha-<40 hex>`, the configured private registry's repository (IMAGE_REPO) | ok, refused | deploy.revision {image, digest, revision}, once the revision is ready |
| reset_twin | none | ok | reset: every area repaired (access, network rule, secret, configuration), base image back, restarted, drill rows deleted, conformant |
| kill | none | ok | reset {by: kill} |

## Changes from v1.0

| Change | Why | Consumers |
| --- | --- | --- |
| `deploy.revision` adds `digest`: the tag is resolved in the private registry (Azure Container Registry, with the Ops identity's AcrPull right) and the revision deploys by that immutable digest. An image missing from the registry is refused (422). There is no attestation check: build attestations on a private repo need GitHub Enterprise Cloud, which isn't used | Blueprint §5.3 Deployment Adapter and §7.2 supply-chain controls | WS4 records the digest in the evidence package; WS5 shows it |
| Referee results and `referee.<label>` details add `duration_s`, `trace_url` and `browser` (`local-chromium` or `playwright-workspaces`) | WS5's browser-minutes tile and trace link | WS4, WS5 |
| `recover.broad` adds `simulated: true` when the twin is the local Docker stack | A laptop has no Azure Policy; the evidence must never pass a simulation off as a platform decision | WS5 labels it |
| `kill` never waits for the drill's lock. An action that started before the kill writes no further events and returns 409 `stopped by the kill switch` | The evidence must show nothing happening after the kill | WS4 |
| `deploy_revision` also refuses images from another registry or repository | The allowlist is the configured repository (`IMAGE_REPO`), not any `order-service` | — |

## Changes in v2.0

| Change | Why | Consumers |
| --- | --- | --- |
| Four faults, each with one narrow recovery and a drift area. `inject_fault` takes `fault`; `recover`, `attempt_unsafe` and `check_drift` are new; the v1 names stay as aliases | Restore validation: the agents must diagnose which defect broke the twin, and the drift check proves recovery without trusting them | WS4 (workflow), WS5 (feed) |
| The desired state comes from IaC: the database name and firewall rule from settings, the known-good password from the control vault (`TWIN_DB_PASSWORD`) | A drift check that compared the twin with itself would prove nothing | WS2 infra |
| New narrow rights for id-lf-ops: Key Vault Secrets Officer on the twin's `db-password` secret only; a custom role on the twin SQL server's firewall rules only | secret-drift and network-drift; the open-firewall attempt must reach Azure Policy (RBAC is checked first) | CloudLabs request |
| Locally, the app reaches SQL through the `sqlgw` relay (docker-compose.yml), which network-drift stops; config-drift recreates the app with `ORDER_DB_NAME`; secret-drift writes a stale password and restarts the app | The same four defects on a laptop | WS2, WS4 local runs |

## Changes in v2.1: the Recovery agent executes recovery

| Change | Why | Consumers |
| --- | --- | --- |
| A second key, `OPS_AGENT_KEY` (control vault secret `ops-agent-key`), held only by the MCP server's `/recovery/mcp` endpoint. It can call `recover`, `attempt_unsafe` and `check_drift`, and nothing else: any other action is 403 | The Recovery agent executes recovery through its MCP tools; it must not reach faults, deploys, the Referee or the kill switch | WS3 (MCP server), WS2 infra |
| With the agent key, `recover` and `attempt_unsafe` require `grant`: a recovery grant signed by the Drill Runner with `RECOVERY_GRANT_KEY` (`grants.py`, identical in both components). It must name this drill and exactly this action, be unexpired (10 minutes) and unused, and its purpose must match: `recover` for `recover`, `policy_test` for `attempt_unsafe`. Otherwise 422 refused, and a `grant.refused` event | Only an approved action can run, once; the agent and the MCP server can't forge or widen a grant | WS4 (issues grants), WS3 |
| `fault.restore` and `recover.broad` add `executed_by`: `agent` (with `grant_id` and `approved_by`) or `workflow` (the runner key: the durability replay). The grant itself is never written anywhere | The verdict requires the authorized restore to be the agent's, under a grant the workflow issued | WS4 (verdict), WS5 (feed) |
| The runner key keeps every v2.0 action, including `recover` without a grant, for the durability re-fault and reset | The replay re-runs an action already approved and proven; it is a test of the fix, not a recovery decision | WS4 |
