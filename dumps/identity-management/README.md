# MaaS Identity & API Key Provisioning

Admin-driven bulk provisioning of RHOAI Models-as-a-Service API keys.

Replaces the interactive per-user flow with a single declarative config plus one script,
so a cluster admin can stand up groups, subscriptions and API keys for a whole roster in
one shot and hand out a CSV.

## The flow this replaces

```
Create user → Create sub → Create group → Add user to group → Add sub to group
            → user logs into RHOAI → user requests an API token themselves
```

## What this does instead

```
config.json  ──►  provision-maas-keys.sh  ──►  out/maas-api-keys.csv

  groups + users            reconciles:                api_key, key_id, user,
  + subscriptions           1. htpasswd identities     group, subscription,
  + models/limits           2. OpenShift Groups        expiry, base_url,
                            3. MaaSSubscriptions       models, verified
                            4. MaaSAuthPolicies
                            5. API keys per user
```

Users never touch the RHOAI dashboard. They receive a key and call the inference
endpoint directly.

---

## Why the script authenticates as each user

This is the one non-obvious constraint, and it drives the whole design.

**maas-api has no admin "mint-on-behalf-of" endpoint.** Inspecting the running
`maas-api` binary and its Postgres schema confirms the `api_keys` row snapshots
identity from the *caller's* bearer token:

```
Table "public.api_keys"
  username      text    NOT NULL   ← from the caller's token
  user_groups   text[]  NOT NULL   ← from the caller's token, at creation time
  subscription  text    NOT NULL   ← from the X-MaaS-Subscription request header
  key_hash      text    NOT NULL
  expires_at    timestamptz
  status        text    NOT NULL   ('active' | 'revoked' | 'expired')
```

So the only way to produce a key carrying a given user's identity is to hold that
user's token once. Since the cluster uses the **htpasswd** identity provider and the
admin owns `openshift-config/htpass-secret`, the script sets each user's password,
exchanges it for a token via the OAuth challenge flow, mints the key, and moves on.
It never runs `oc login`, so your admin kubeconfig is untouched.

**The useful consequence:** `user_groups` is a stored snapshot, and key validation
reads that DB row rather than querying OpenShift live. A minted key therefore keeps
working even after the user's cluster access is reduced or removed entirely — see
[Locking users out of RHOAI](#locking-users-out-of-rhoai).

---

## Usage

```bash
cd dumps/identity-management

./provision-maas-keys.sh --dry-run     # show the plan, change nothing
./provision-maas-keys.sh               # reconcile + mint (prompts once)
./provision-maas-keys.sh --yes         # unattended
```

| Flag | Effect |
|---|---|
| `-c, --config FILE` | Config file (default `./config.json`) |
| `-o, --out DIR` | Output directory (default `./out`) |
| `-n, --dry-run` | Print planned changes, mutate nothing |
| `-r, --rotate` | Mint fresh keys even if already minted |
| `-u, --users LIST` | Only mint for these usernames (comma-separated) |
| `--skip-infra` | Only mint keys; leave users/groups/subscriptions alone |
| `-p, --parallel N` | Mint N users concurrently (default 1) |
| `--no-verify` | Skip the per-key gateway check, halving HTTP calls |
| `--keep-raw` | Also write one raw response file per key |
| `-y, --yes` | Skip the confirmation prompt |

Requires `oc` (logged in as cluster-admin), `jq`, `curl`, `htpasswd`.

### Outputs

| Path | Contents | Mode |
|---|---|---|
| `out/subscriptions.json` | **Every subscription, each with its users and keys** | `0600` |
| `out/subscriptions/<sub>.json` | The same, split one file per subscription | `0600` |
| `out/maas-api-keys.csv` | Flat one-row-per-key export | `0600` |
| `out/.keys-ledger.jsonl` | **Durable record of every key ever issued** | `0600` |
| `out/.passwords.json` | Generated htpasswd passwords | `0600` |
| `out/.minted-index.json` | Which keys have been issued (idempotency) | — |
| `out/responses/*.json` | Raw per-key responses — only with `--keep-raw` | — |

`out/` is gitignored. **It contains live credentials — never commit it.**

### Collated output

`subscriptions.json` is an array of subscriptions, each carrying its own users and
keys — the natural grouping when a roster is large enough that one file per key is
unusable:

```jsonc
[
  {
    "subscription": "team-alpha",
    "group": "team-alpha",
    "baseUrl": "https://maas.apps.<cluster-domain>",
    "models": ["llama-32-1b-instruct-maas", "qwen25-05b-instruct-maas"],
    "generatedAt": "2026-07-26T07:30:00Z",
    "userCount": 2,
    "keyCount": 2,
    "keys": [
      {
        "username":   "user-01",
        "displayName":"Alpha User One",
        "keyName":    "user-01-team-alpha-01",
        "id":         "1eb35cd5-e8a6-4595-805c-e6e37f7133db",
        "keyPrefix":  "sk-oai-1BJatfuwnj1M...",
        "apiKey":     "sk-oai-...",
        "createdAt":  "2026-07-26T07:09:07Z",
        "expiresAt":  "2026-10-24T07:09:07Z",
        "verified":   "yes"
      }
    ]
  }
]
```

Pull one subscription's keys straight out of it:

```bash
jq -r '.[] | select(.subscription=="team-alpha") | .keys[] | [.username,.apiKey] | @tsv' \
  out/subscriptions.json
```

Raw per-key response files are **off by default** — at roster scale they produce one
file per user for no benefit. Pass `--keep-raw` to restore them.

### Outputs are cumulative

`.keys-ledger.jsonl` is the source of truth, and every export is rebuilt from the
whole ledger on each run. A re-run therefore still contains users minted earlier,
even though it skipped them.

This matters more than it sounds: **maas-api returns a key's secret only once, at
creation, and has no endpoint to read it back.** The ledger is the only place that
secret exists. If an export were rebuilt from a single run's mints, any user skipped
as already-provisioned would drop out of the file and their key would be gone for
good.

Where the same key name appears more than once — after a `--rotate` — the newest
record wins.

If the script ever finds a key it knows was issued but holds no secret for, it says
so and prints the exact command to re-mint:

```
! issued previously but no secret on record (unrecoverable - re-mint these):
      user-02-team-alpha-01
      fix: ./provision-maas-keys.sh --rotate --users user-02
```

A re-minted key is a *new* credential; the old row stays `active` in the database
until you revoke it (see [Revoking a key](#revoking-a-key)). Since nobody holds its
secret, revoking it is the right move.

---

## config.json

```jsonc
{
  "defaults": {
    "subscriptionNamespace": "models-as-a-service",
    "modelNamespace": "vllm-project",
    "keyExpiration": "2160h",   // Go duration, hour-form; 2160h = 90d = cluster max
    "keysPerUser": 1,
    "passwordLength": 24
  },
  "groups": [
    {
      "name": "team-alpha",           // OpenShift Group name
      "displayName": "Team Alpha",
      "subscription": {
        "name": "team-alpha",
        "priority": 0,                // lower wins when a user is in several subs
        "tokenMetadata": {            // surfaces as telemetry labels on every call
          "costCenter": "CC-00001",
          "organizationId": "ORG-00001"
        },
        "models": [
          { "name": "llama-32-1b-instruct-maas",
            "tokenRateLimits": [ { "limit": 10000, "window": "1m" } ] }
        ]
      },
      "users": [
        { "username": "user1", "displayName": "Alpha User One" }
      ]
    }
  ]
}
```

`users` entries may be plain strings (`"user1"`) or objects with a `displayName`.

### Adding a group or a user

Append to `config.json` and re-run. The script is idempotent: existing users keep
their password, and keys already recorded in `.minted-index.json` are not re-issued
unless you pass `--rotate`.

> **Group membership is declarative.** Applying a group replaces its user list with
> exactly what the config declares. Anyone omitted is removed from that group.

### Key expiration

`keyExpiration` is a Go duration in hour form. The cluster ceiling comes from
`api-key-max-expiration-days` in the `maas-parameters` ConfigMap (currently **90**),
and the script refuses anything longer.

---

## Running at scale

The script is built to stay linear in the number of users. Config marshalling happens
in single `jq` passes that emit a pre-rendered work list, and `.passwords.json` /
`.minted-index.json` are merged once at the end rather than rewritten per user — the
latter would otherwise be quadratic. The per-user cost is then just two HTTP calls,
token + mint.

For a large roster:

```bash
./provision-maas-keys.sh --parallel 8 --no-verify --yes
```

- `--parallel 8` mints eight users concurrently. Wall time is dominated by the two
  round trips per user, so this scales close to linearly. Raise it cautiously — every
  worker hits the OAuth server.
- `--no-verify` drops the post-mint `/v1/models` check, roughly halving HTTP calls.
  Worth keeping on for a first run, then dropping for bulk.

Two costs stay unavoidable: one OAuth exchange and one mint call per user. Rollout of
new htpasswd identities is a single batched secret update, not per user.

If a run is interrupted, just re-run it. Already-issued keys are recorded in
`.minted-index.json` and skipped, so it resumes rather than restarting.

## Model inventory

Only models in `Ready` state can serve traffic. Current cluster state:

| Model | Status |
|---|---|
| `llama-32-1b-instruct-maas` | Ready |
| `qwen25-05b-instruct-maas` | Ready |
| `llama-32-1b-instruct-llmd-2` | Stopped |
| `qwen25-05b-instruct-llmd` | Stopped |

The shipped config references only the two `Ready` models. The pre-existing
subscriptions on the cluster also list the two stopped `llmd` models, which is why
they report `Degraded / 2 of 4 model references are invalid or unavailable`. Running
this script reconciles them to the Ready-only set and clears that condition.

To add the `llmd` models back once their `LLMInferenceService` resources are started,
append them to the group's `models` array and re-run.

---

## Using a key

The key is a standard OpenAI-compatible bearer credential:

```bash
curl -sk https://maas.apps.<cluster-domain>/vllm-project/llama-32-1b-instruct-maas/v1/chat/completions \
  -H "Authorization: Bearer sk-oai-..." \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama-32-1b-instruct-maas",
       "messages":[{"role":"user","content":"hello"}]}'
```

List what a key can reach:

```bash
curl -sk https://maas.apps.<cluster-domain>/v1/models \
  -H "Authorization: Bearer sk-oai-..."
```

The script already runs this check for every key it mints and records the result in
the CSV's `verified` column.

---

## Does a key require an RHOAI login?

**No.** Not to use one, and not even to create one.

Only one moment needs any credential at all:

| | Needs an OpenShift token | Needs an RHOAI login |
|---|---|---|
| **Creating** a key | Yes — once | No |
| **Using** a key | No | No |

Creating a key needs a valid *cluster* token for that user. That is OpenShift OAuth,
not RHOAI dashboard access — they are separate systems, which is why a user excluded
from the `Auth` CR can still mint. And the script brokers that token as admin, so end
users never log into RHOAI, never log into OpenShift, and never see a dashboard. They
receive a key from the CSV and call the endpoint.

### Why, at the enforcement point

The per-model `AuthPolicy` declares two mutually exclusive authentication rules:

```yaml
api-keys:           # when: Authorization matches ^Bearer sk-oai-.*
kubernetes-tokens:  # when: NOT startsWith("Bearer sk-oai-")
```

An `sk-oai-` key never reaches `kubernetesTokenReview`. No OpenShift identity takes
part in the request.

Its authorization rules then read identity from the database, not from the cluster —
note which branch the API-key path takes:

```cel
has(auth.metadata.apiKeyValidation)
  ? auth.metadata.apiKeyValidation.groups     // API key: stored DB snapshot
  : auth.identity.user.groups                 // token:   live OpenShift lookup
```

RHOAI's dashboard authorization never enters the picture: `maas-api` holds no
reference to `allowedGroups`, `adminGroups`, or `services.platform.opendatahub.io`,
and its RBAC covers only `maas.opendatahub.io`.

This is the same snapshot behaviour described in
[What happens when you remove things](#what-happens-when-you-remove-things) — here
confirmed at the point of enforcement rather than inferred from the schema.

---

## Locking users out of RHOAI

The script deliberately **does not** change access — it provisions and mints only.
If you want key-holders to have no RHOAI or cluster access at all, apply one of these
afterwards. Minted keys keep working either way, because validation reads the stored
`user_groups` snapshot.

**Option A — remove cluster login entirely (strictest).** Delete the users' htpasswd
entries once keys are minted. They can no longer authenticate to OpenShift at all;
their API keys are unaffected.

```bash
oc get secret htpass-secret -n openshift-config -o jsonpath='{.data.htpasswd}' \
  | base64 -d | grep -vE '^(user1|user2|user3|user4):' > /tmp/htpasswd
oc create secret generic htpass-secret --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config --dry-run=client -o yaml | oc apply -f -
```

Note this makes `--rotate` impossible later — re-running the script would have to
re-create the credentials first.

**Option B — keep cluster login, block the dashboard.** The `Auth` CR currently
grants dashboard access to everyone:

```yaml
spec:
  adminGroups:  [rhods-admins]
  allowedGroups: [system:authenticated]   # ← everyone
```

Narrow `allowedGroups` to only the groups that should see the RHOAI UI, leaving the
MaaS-only groups out.

---

## What happens when you remove things

| What you remove | Key row deleted? | Key still works? |
|---|---|---|
| User from `config.json` (→ dropped from Group) | No | Yes |
| htpasswd entry | No | Yes |
| OpenShift `User` / `Identity` object | No | Yes |
| The `Group` | No | Yes |
| **The `MaaSSubscription`** | No | **No — requests fail** |
| Key reaches `expires_at` | No (status → `expired`) | No |
| Explicit revoke | No (status → `revoked`) | No |

**Identity removal is safe.** `username` and `user_groups` are snapshot columns
written at creation, and validation reads that row. `maas-api` holds no watch on
`users.user.openshift.io`, `groups.user.openshift.io`, or
`identities.user.openshift.io`, so nothing triggers a revoke when they disappear.

**The `maas-api-key-cleanup` CronJob will not touch them.** Its only delete is
`DELETE FROM api_keys WHERE ephemeral = TRUE AND expires_at IS NOT NULL AND ...`.
Keys minted by this script are non-ephemeral — supplying a `name` is what makes them
so, and the script always does.

**Do not delete the subscription.** Unlike identity, the subscription is resolved
*live* at request time rather than from the snapshot. Deleting it leaves the key row
intact but every call fails with `API key missing bound subscription` /
`Model not included in subscription`. The `subscription-cleanup` finalizer tidies up
the derived Kuadrant policies, not API keys — the controller only ever calls
`internal/v1/api-keys/validate`, never a revoke endpoint.

Only three things stop a key: expiry, explicit revocation, or removal of its
subscription.

## Revoking a key

Keys are rows in the maas-api Postgres database. To revoke without waiting for expiry:

```bash
POD=$(oc get pod -n redhat-ods-applications -l name=maas-postgres -o name | head -1)
oc exec -n redhat-ods-applications "$POD" -- bash -c \
  "psql -U \$POSTGRESQL_USER -d \$POSTGRESQL_DATABASE \
   -c \"UPDATE api_keys SET status='revoked' WHERE username='user1' AND name='user1-team-alpha-01';\""
```

Audit what is currently issued:

```bash
oc exec -n redhat-ods-applications "$POD" -- bash -c \
  "psql -U \$POSTGRESQL_USER -d \$POSTGRESQL_DATABASE \
   -c 'SELECT username, name, subscription, status, expires_at, last_used_at FROM api_keys ORDER BY created_at DESC;'"
```

---

## How it works, step by step

1. **Preflight** — verifies tooling, cluster-admin rights, and discovers the OAuth
   route, MaaS gateway hostname, and max key lifetime from `maas-parameters`.
2. **Identities** — reads `htpass-secret`, adds a bcrypt entry for each new user with
   a generated password, applies the secret back. Passwords persist in
   `out/.passwords.json` so re-runs are stable.
3. **Groups & subscriptions** — applies `Group`, `MaaSSubscription`, and
   `MaaSAuthPolicy` per configured group.
4. **Rollout wait** — new htpasswd identities are unusable until the oauth pods
   restart, so it waits for the `authentication` cluster operator to settle.
5. **Minting** — for each user: exchange credentials for a token via
   `/oauth/authorize?client_id=openshift-challenging-client`, then
   `POST /maas-api/v1/api-keys` with an `X-MaaS-Subscription` header. Verifies each
   key against `/v1/models`.
6. **Export** — writes the CSV.

### maas-api endpoints used

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/maas-api/v1/api-keys` | Mint. Body `{name, description, expiration}`, header `X-MaaS-Subscription` |
| `GET` | `/maas-api/v1/subscriptions` | Subscriptions visible to the caller |
| `GET` | `/v1/models` | OpenAI-compatible model list; used to verify a key |

There is no list-keys endpoint, which is why idempotency is tracked locally in
`.minted-index.json` rather than by querying the API.
