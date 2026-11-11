# LiveFire incident corpus (private)

The past incidents the LiveFire Planner agent searches during a drill. That's all this repo holds.

**The code is not here.** The WS3 MCP server, its contracts, Bicep modules and scripts moved to
[`livefire-team/livefire-fusion-poc`](https://github.com/livefire-team/livefire-fusion-poc) in PR #40 (ADR-022).
Change them there. This repo was called `ws3-mcp-server` until then.

## Why this repo still exists

The incidents are the agents' test material. During a drill the Planner must work out the cause from the evidence:
the telemetry, the repo's history and these past incidents. Two of these records point at the cause, one carries a
planted instruction (test T-08) and the rest are noise.

`livefire-fusion-poc` is public, and the agents read it. If the incidents were committed there, the answer would sit
next to the code and the drill would prove nothing. So, under ADR-004 and ADR-022, they stay in this private repo.
They reach the agents only through the AI Search index `incidents`, where the Planner's `search_incident_history` tool
ranks them like any other evidence.

Keep this repo **private**, give read access only to the people who deploy the lab, and don't copy these files into
any repo, issue, pull request or chat the agents can read.

## How the lab uses it

`postprovision.sh` in `livefire-fusion-poc` reloads the index on every provision from the folder named by the azd value
`INCIDENT_CORPUS`. On the machine that runs `azd provision`:

```bash
git clone git@github.com:livefire-team/livefire-incident-corpus.git ~/livefire-incident-corpus
cd <livefire-fusion-poc checkout>
azd env select lf-eh
azd env set INCIDENT_CORPUS ~/livefire-incident-corpus/evidence-corpus/incidents   # use the full path
```

Without it, the provision warns `incident index not loaded: set INCIDENT_CORPUS` and carries on; the Planner then has
no incident history to search. To load by hand: `python3 scripts/load-incidents.py --corpus <folder> --endpoint <search>`
from `livefire-fusion-poc`.

## What's here

| Path | What it is |
| --- | --- |
| `evidence-corpus/incidents/*.json` | One record per file: `id`, `kind`, `title`, `summary`, `resolution`, `service`, `source`, `occurred_at` |
| `evidence-corpus/README.md` | What each record is for in the drill |

Every record is invented for the LiveFire drill.
