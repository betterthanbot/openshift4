#!/usr/bin/env bash
#
# provision-maas-keys.sh
#
# Cluster-admin driven bulk provisioning of RHOAI MaaS API keys.
#
# Reads config.json (groups -> subscription + users) and reconciles:
#   1. htpasswd identities for every user           (openshift-config/htpass-secret)
#   2. OpenShift Groups with the declared members   (user.openshift.io/v1 Group)
#   3. MaaSSubscription per group                   (models + token rate limits)
#   4. MaaSAuthPolicy per group                     (which groups may call which models)
#   5. One or more MaaS API keys per user           (minted as that user, via OAuth)
#   6. Per-subscription JSON + a flat CSV of every key
#
# WHY IT LOGS IN AS EACH USER:
#   maas-api has no admin "mint-on-behalf-of" endpoint. The api_keys row snapshots
#   `username` and `user_groups` from the *caller's* bearer token. So the only way to
#   produce a key that carries a given user's identity is to authenticate as them once.
#   Because user_groups is a stored snapshot and key validation reads that DB row (not
#   live OpenShift), the key keeps working even if the user's access is revoked later.
#
# SCALE:
#   Built for large rosters. All config/state marshalling happens in single jq passes
#   rather than per-user, and state files are append-only, so cost stays linear in the
#   number of users. The per-user work is then two HTTP calls (token + mint), which
#   --parallel fans out.
#
# Safe to re-run: existing users keep their password, existing keys are left alone
# unless --rotate is passed.

# This script needs real bash. Invoked as `sh provision-maas-keys.sh`, macOS runs it
# as bash in POSIX mode, which disables process substitution and fails to parse.
# BASH_VERSION is still set in that mode, so test the posix option too.
if [ -z "${BASH_VERSION:-}" ] || shopt -qo posix 2>/dev/null; then
  exec bash "$0" "$@"
fi

set -euo pipefail

# ---------------------------------------------------------------------------
# defaults / args
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.json"
OUT_DIR="${SCRIPT_DIR}/out"
DRY_RUN=false
ROTATE=false
SKIP_INFRA=false
ASSUME_YES=false
KEEP_RAW=false
VERIFY=true
PARALLEL=1
ONLY_USERS=""

usage() {
  cat <<'EOF'
Usage: provision-maas-keys.sh [options]

  -c, --config FILE   Config file            (default: ./config.json)
  -o, --out DIR       Output directory       (default: ./out)
  -n, --dry-run       Print planned changes, mutate nothing
  -r, --rotate        Mint fresh keys even if the user already has one
  -u, --users LIST    Only mint for these usernames (comma-separated)
      --skip-infra    Only mint keys; do not touch users/groups/subscriptions
  -p, --parallel N    Mint N users concurrently (default 1; try 8 for big rosters)
      --no-verify     Skip the per-key gateway check (halves HTTP calls)
      --keep-raw      Also write one raw response file per key
  -y, --yes           Do not prompt for confirmation
  -h, --help          Show this help

Outputs (in --out):
  subscriptions.json        every subscription, each with its users and keys
  subscriptions/<sub>.json  the same, split one file per subscription
  maas-api-keys.csv         flat one-row-per-key export
  .keys-ledger.jsonl        durable record of every key ever issued (mode 0600)
  .passwords.json           generated htpasswd passwords (mode 0600)

Outputs are cumulative: every run rebuilds them from the full ledger, so users
minted in earlier runs are always included.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)   CONFIG="$2"; shift 2 ;;
    -o|--out)      OUT_DIR="$2"; shift 2 ;;
    -n|--dry-run)  DRY_RUN=true; shift ;;
    -r|--rotate)   ROTATE=true; shift ;;
    -u|--users)    ONLY_USERS="$2"; shift 2 ;;
    --skip-infra)  SKIP_INFRA=true; shift ;;
    -p|--parallel) PARALLEL="$2"; shift 2 ;;
    --no-verify)   VERIFY=false; shift ;;
    --keep-raw)    KEEP_RAW=true; shift ;;
    -y|--yes)      ASSUME_YES=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$PARALLEL" =~ ^[0-9]+$ ]] && (( PARALLEL >= 1 )) || { echo "--parallel must be a positive integer" >&2; exit 2; }

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s+%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
skip() { printf '    %s.%s %s\n' "$C_DIM" "$C_RESET" "$*"; }

# Field separators for the generated work list. Raw separators rather than @tsv
# because jq's @tsv escapes backslashes, which would corrupt the embedded JSON
# request bodies. These are the ASCII separator characters; do NOT substitute
# \001 or \177 -- bash reserves those internally (CTLESC/CTLNUL) and silently
# refuses to split on them, collapsing every row into a single field.
SEP_FIELD=$'\037'   # US - between columns of a row
SEP_KEY=$'\036'     # RS - between keys belonging to one user
SEP_PAIR=$'\035'    # GS - between a key's name and its request body

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------

step "Preflight"

for bin in oc jq curl htpasswd base64; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found in PATH"
done

[[ -f "$CONFIG" ]] || die "config not found: $CONFIG"
jq empty "$CONFIG" 2>/dev/null || die "config is not valid JSON: $CONFIG"

WHOAMI="$(oc whoami 2>/dev/null)" || die "not logged in to a cluster (try: oc login)"
oc auth can-i get secret -n openshift-config >/dev/null 2>&1 \
  || die "current user '$WHOAMI' cannot read secrets in openshift-config; cluster-admin required"
ok "authenticated as $WHOAMI"

OAUTH_HOST="$(oc get route oauth-openshift -n openshift-authentication \
  -o jsonpath='{.spec.host}' 2>/dev/null)" || true
[[ -n "$OAUTH_HOST" ]] || die "could not resolve the oauth-openshift route"
ok "oauth endpoint   https://${OAUTH_HOST}"

GW_NAME="$(oc get configmap maas-parameters -n redhat-ods-applications \
  -o jsonpath='{.data.gateway-name}' 2>/dev/null)"
GW_NS="$(oc get configmap maas-parameters -n redhat-ods-applications \
  -o jsonpath='{.data.gateway-namespace}' 2>/dev/null)"
GW_NAME="${GW_NAME:-maas-default-gateway}"
GW_NS="${GW_NS:-openshift-ingress}"

MAAS_HOST="$(oc get gateway "$GW_NAME" -n "$GW_NS" \
  -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null)" || true
[[ -n "$MAAS_HOST" ]] || die "could not resolve hostname from gateway ${GW_NS}/${GW_NAME}"

MAAS_BASE="https://${MAAS_HOST}"
MAAS_API="${MAAS_BASE}/maas-api"
ok "maas gateway     ${MAAS_BASE}"

MAX_EXP_DAYS="$(oc get configmap maas-parameters -n redhat-ods-applications \
  -o jsonpath='{.data.api-key-max-expiration-days}' 2>/dev/null)"
MAX_EXP_DAYS="${MAX_EXP_DAYS:-90}"
ok "max key lifetime ${MAX_EXP_DAYS} days"

SUB_NS="$(jq -r '.defaults.subscriptionNamespace // "models-as-a-service"' "$CONFIG")"
MODEL_NS="$(jq -r '.defaults.modelNamespace // "vllm-project"' "$CONFIG")"
KEY_EXP="$(jq -r '.defaults.keyExpiration // "2160h"' "$CONFIG")"
KEYS_PER_USER="$(jq -r '.defaults.keysPerUser // 1' "$CONFIG")"
PW_LEN="$(jq -r '.defaults.passwordLength // 24' "$CONFIG")"

[[ "$KEY_EXP" =~ ^[0-9]+h$ ]] \
  || die "defaults.keyExpiration must be an hour-form Go duration (e.g. \"2160h\"), got \"$KEY_EXP\""
EXP_HOURS="${KEY_EXP%h}"
if (( EXP_HOURS > MAX_EXP_DAYS * 24 )); then
  die "keyExpiration ${KEY_EXP} exceeds the cluster maximum of ${MAX_EXP_DAYS}d ($((MAX_EXP_DAYS * 24))h)"
fi

N_GROUPS="$(jq '.groups | length' "$CONFIG")"
N_USERS="$(jq '[.groups[].users[]] | length' "$CONFIG")"
(( N_GROUPS > 0 )) || die "config declares no groups"
ok "config           ${N_GROUPS} group(s), ${N_USERS} user(s), ${KEYS_PER_USER} key(s) each"

# Duplicate usernames inside one group would mint duplicate keys silently.
DUPES="$(jq -r '[.groups[] | .name as $g | .users[] | ((if type=="string" then . else .username end) + "@" + $g)]
  | group_by(.) | map(select(length>1) | .[0]) | join(", ")' "$CONFIG")"
[[ -z "$DUPES" ]] || die "duplicate user entries within a group: $DUPES"

# ---------------------------------------------------------------------------
# workspace
# ---------------------------------------------------------------------------

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT_DIR/subscriptions"
[[ "$KEEP_RAW" == true ]] && mkdir -p "$OUT_DIR/responses"

PW_STORE="$OUT_DIR/.passwords.json"
[[ -f "$PW_STORE" ]] || echo '{}' > "$PW_STORE"
chmod 600 "$PW_STORE"

INDEX="$OUT_DIR/.minted-index.json"
[[ -f "$INDEX" ]] || echo '{}' > "$INDEX"

# The durable record of every key ever issued. maas-api returns a key's secret only
# at creation and has no list endpoint, so this file is the only place it survives.
# Exports are rebuilt from here, which is what makes them cumulative across runs.
LEDGER="$OUT_DIR/.keys-ledger.jsonl"
if [[ ! -f "$LEDGER" ]] && [[ "$DRY_RUN" != true ]]; then
  : > "$LEDGER"
  chmod 600 "$LEDGER"
  # One-time recovery: earlier versions rebuilt the per-subscription files from the
  # current run alone, so any key still recorded there is salvaged into the ledger.
  if compgen -G "$OUT_DIR/subscriptions/*.json" >/dev/null 2>&1; then
    for _f in "$OUT_DIR"/subscriptions/*.json; do
      jq -c --arg base "$MAAS_BASE" '
        . as $s
        | .keys[]?
        | select((.apiKey // "") | startswith("sk-oai-"))
        | { key: .apiKey, id: .id, keyPrefix: .keyPrefix, keyName: .keyName,
            username: .username, displayName: .displayName,
            group: ($s.group // ""), subscription: $s.subscription,
            createdAt: .createdAt, expiresAt: .expiresAt,
            baseUrl: ($s.baseUrl // $base),
            models: (($s.models // []) | join(" ")),
            verified: (.verified // "") }' "$_f" >> "$LEDGER" 2>/dev/null || true
    done
    _recovered="$(wc -l < "$LEDGER" | tr -d ' ')"
    (( _recovered > 0 )) && ok "recovered ${_recovered} previously-issued key(s) into the ledger"
  fi
fi
[[ -f "$LEDGER" ]] && chmod 600 "$LEDGER"

CSV="$OUT_DIR/maas-api-keys.csv"
COLLATED="$OUT_DIR/subscriptions.json"
MINTED="$WORK/minted.jsonl"; : > "$MINTED"
FAILED="$WORK/failed.txt";   : > "$FAILED"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN - no cluster changes, no keys minted"
elif [[ "$ASSUME_YES" != true ]]; then
  printf '\n    This will reconcile %s group(s)/%s user(s) on %s%s%s and mint API keys.\n' \
    "$N_GROUPS" "$N_USERS" "$C_BOLD" "$(oc config current-context)" "$C_RESET"
  reply=""
  read -r -p "    Continue? [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]] || die "aborted"
fi

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

apply_json() {
  local desc="$1" json="$2"
  if [[ "$DRY_RUN" == true ]]; then
    skip "would apply $desc"
    return 0
  fi
  if printf '%s' "$json" | oc apply -f - >/dev/null 2>"$WORK/apply.err"; then
    ok "applied $desc"
  else
    warn "failed to apply $desc: $(tr '\n' ' ' < "$WORK/apply.err")"
    return 1
  fi
}

gen_password() {
  # Reads a fixed block and truncates with cut; piping /dev/urandom into `head`
  # would SIGPIPE the producer and trip `set -o pipefail`.
  LC_ALL=C dd if=/dev/urandom bs=1024 count=1 2>/dev/null \
    | LC_ALL=C tr -dc 'A-Za-z0-9' \
    | cut -c1-"$PW_LEN"
}

compute_expiry() {
  local hours="$1"
  if date -u -v+1H >/dev/null 2>&1; then
    date -u -v+"${hours}"H +"%Y-%m-%dT%H:%M:%SZ"      # BSD / macOS
  else
    date -u -d "+${hours} hours" +"%Y-%m-%dT%H:%M:%SZ" # GNU
  fi
}

# Exchange htpasswd credentials for an OpenShift access token without touching
# the caller's kubeconfig (oc login would clobber the admin context).
get_user_token() {
  local user="$1" pass="$2" headers
  headers="$(curl -sk -m 30 -D - -o /dev/null \
    -u "${user}:${pass}" \
    -H 'X-CSRF-Token: 1' \
    "https://${OAUTH_HOST}/oauth/authorize?client_id=openshift-challenging-client&response_type=token" \
    2>/dev/null)" || return 1
  # Strip only the leading key; cutting on '=' would truncate a token containing one.
  printf '%s' "$headers" \
    | grep -oE 'access_token=[^&[:space:]]+' \
    | head -1 | sed 's/^access_token=//'
}

# ---------------------------------------------------------------------------
# phase 1 - identities (htpasswd)
# ---------------------------------------------------------------------------

HTPASSWD_CHANGED=false

if [[ "$SKIP_INFRA" == true ]]; then
  step "Identities (skipped: --skip-infra)"
else
  step "Identities"

  HTFILE="$WORK/htpasswd"
  if oc get secret htpass-secret -n openshift-config >/dev/null 2>&1; then
    oc get secret htpass-secret -n openshift-config \
      -o jsonpath='{.data.htpasswd}' | base64 -d > "$HTFILE" 2>/dev/null || : > "$HTFILE"
  else
    warn "htpass-secret does not exist; it will be created"
    : > "$HTFILE"
  fi
  chmod 600 "$HTFILE"

  # Existing htpasswd principals, one per line, for a single-pass set difference.
  cut -d: -f1 "$HTFILE" 2>/dev/null | sort -u > "$WORK/have_ht.txt" || : > "$WORK/have_ht.txt"

  # Users still needing a credential = configured, minus those that already have
  # both an htpasswd entry and a stored password. One jq pass, not one per user.
  jq -r --slurpfile store "$PW_STORE" --rawfile have "$WORK/have_ht.txt" '
    ($store[0] // {})                                as $pw
    | ($have | split("\n") | map(select(length > 0))) as $ht
    | [ .groups[].users[] | if type == "string" then . else .username end ]
    | unique
    | map(select(($pw[.] // "") == "" or (. as $u | $ht | index($u) | not)))
    | .[]' "$CONFIG" > "$WORK/need_pw.txt"

  NEED_PW="$(wc -l < "$WORK/need_pw.txt" | tr -d ' ')"

  if [[ "$DRY_RUN" == true ]]; then
    if (( NEED_PW > 0 )); then
      skip "would create/update ${NEED_PW} htpasswd entr$( (( NEED_PW == 1 )) && echo y || echo ies)"
    else
      skip "all users already provisioned"
    fi
  elif (( NEED_PW == 0 )); then
    skip "all ${N_USERS} user(s) already provisioned"
  else
    : > "$WORK/newpw.jsonl"
    while IFS= read -r username; do
      [[ -n "$username" ]] || continue
      pw="$(gen_password)"
      htpasswd -bB "$HTFILE" "$username" "$pw" >/dev/null 2>&1 \
        || die "htpasswd failed for $username"
      # Append-only; merged into the store in one pass below.
      jq -nc --arg u "$username" --arg p "$pw" '{u:$u,p:$p}' >> "$WORK/newpw.jsonl"
      HTPASSWD_CHANGED=true
    done < "$WORK/need_pw.txt"

    jq -s --slurpfile store "$PW_STORE" \
      '($store[0] // {}) + (map({key:.u, value:.p}) | from_entries)' \
      "$WORK/newpw.jsonl" > "$WORK/pw.merged" \
      && mv "$WORK/pw.merged" "$PW_STORE" && chmod 600 "$PW_STORE"

    ok "provisioned ${NEED_PW} credential(s)"

    oc create secret generic htpass-secret \
      --from-file=htpasswd="$HTFILE" -n openshift-config \
      --dry-run=client -o yaml | oc apply -f - >/dev/null \
      || die "failed to update htpass-secret"
    ok "htpass-secret updated"
  fi
fi

# ---------------------------------------------------------------------------
# phase 2 - groups, subscriptions, auth policies
# ---------------------------------------------------------------------------

if [[ "$SKIP_INFRA" == true ]]; then
  step "Groups & subscriptions (skipped: --skip-infra)"
else
  step "Groups, subscriptions & auth policies"

  while IFS= read -r g; do
    gname="$(jq -r '.name' <<<"$g")"
    gdisplay="$(jq -r '.displayName // .name' <<<"$g")"
    sub_name="$(jq -r '.subscription.name // .name' <<<"$g")"

    # Declarative: membership is replaced with exactly the configured list.
    group_json="$(jq -nc \
      --arg name "$gname" \
      --argjson users "$(jq -c '[.users[] | if type == "string" then . else .username end]' <<<"$g")" \
      '{apiVersion:"user.openshift.io/v1", kind:"Group",
        metadata:{name:$name}, users:$users}')"
    apply_json "Group/$gname" "$group_json" || true

    sub_json="$(jq -nc \
      --arg name "$sub_name" --arg ns "$SUB_NS" --arg display "$gdisplay" --arg group "$gname" \
      --argjson priority "$(jq -r '.subscription.priority // 0' <<<"$g")" \
      --argjson meta "$(jq -c '.subscription.tokenMetadata // {}' <<<"$g")" \
      --argjson models "$(jq -c --arg mns "$MODEL_NS" '
        [ .subscription.models[]
          | { name: .name,
              namespace: (.namespace // $mns),
              tokenRateLimits: (.tokenRateLimits // [{limit:1000, window:"1m"}]) } ]' <<<"$g")" \
      '{apiVersion:"maas.opendatahub.io/v1alpha1", kind:"MaaSSubscription",
        metadata:{name:$name, namespace:$ns,
                  annotations:{"openshift.io/display-name":$display}},
        spec:{priority:$priority, owner:{groups:[{name:$group}]},
              tokenMetadata:$meta, modelRefs:$models}}')"
    apply_json "MaaSSubscription/$sub_name" "$sub_json" || true

    pol_json="$(jq -nc \
      --arg name "${sub_name}-policy" --arg ns "$SUB_NS" --arg sub "$sub_name" --arg group "$gname" \
      --argjson models "$(jq -c --arg mns "$MODEL_NS" '
        [ .subscription.models[] | { name: .name, namespace: (.namespace // $mns) } ]' <<<"$g")" \
      '{apiVersion:"maas.opendatahub.io/v1alpha1", kind:"MaaSAuthPolicy",
        metadata:{name:$name, namespace:$ns,
                  annotations:{"openshift.io/display-name":$name,
                               "openshift.io/description":("Auth policy created for subscription \"" + $sub + "\"")}},
        spec:{modelRefs:$models, subjects:{groups:[{name:$group}]}}}')"
    apply_json "MaaSAuthPolicy/${sub_name}-policy" "$pol_json" || true

  done < <(jq -c '.groups[]' "$CONFIG")
fi

# ---------------------------------------------------------------------------
# phase 3 - wait for the oauth server to pick up new identities
# ---------------------------------------------------------------------------

if [[ "$HTPASSWD_CHANGED" == true && "$DRY_RUN" != true ]]; then
  step "Waiting for authentication operator rollout"
  info "new htpasswd identities are not usable until the oauth pods restart"
  deadline=$((SECONDS + 300))
  settled=false
  sleep 15   # let the operator notice the secret change before polling
  while (( SECONDS < deadline )); do
    prog="$(oc get clusteroperator authentication \
      -o jsonpath='{.status.conditions[?(@.type=="Progressing")].status}' 2>/dev/null)"
    avail="$(oc get clusteroperator authentication \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)"
    if [[ "$prog" == "False" && "$avail" == "True" ]]; then
      settled=true
      break
    fi
    printf '    %swaiting... (Progressing=%s Available=%s)%s\r' "$C_DIM" "$prog" "$avail" "$C_RESET"
    sleep 10
  done
  printf '\033[2K'
  if [[ "$settled" == true ]]; then
    ok "authentication operator settled"
  else
    warn "operator still progressing after 300s; token requests may fail"
  fi
fi

# ---------------------------------------------------------------------------
# phase 4 - mint API keys
# ---------------------------------------------------------------------------

step "Minting API keys"

# Already-issued key names, for the idempotency check. maas-api exposes no
# list-keys endpoint, so this local index is the only record.
jq -r 'keys[]' "$INDEX" 2>/dev/null | sort -u > "$WORK/minted_names.txt" || : > "$WORK/minted_names.txt"

# One jq pass builds the entire work list: a row per user, carrying that user's
# password and every key request body already rendered. The mint loop below then
# spawns no jq at all, which is what keeps 20k users tractable.
jq -r \
  --slurpfile store "$PW_STORE" \
  --argjson kpu "$KEYS_PER_USER" \
  --arg exp "$KEY_EXP" \
  --arg fs "$SEP_FIELD" --arg ks "$SEP_KEY" --arg ps "$SEP_PAIR" \
  --arg only "$ONLY_USERS" '
  ($store[0] // {}) as $pw
  | ($only | split(",") | map(select(length > 0))) as $filter
  | .groups[] as $g
  | (($g.subscription.name) // $g.name)              as $sub
  | ([$g.subscription.models[].name] | join(" "))    as $models
  | $g.users[]
  | (if type == "string"
       then {username: ., displayName: .}
       else {username: .username, displayName: (.displayName // .username)} end) as $u
  | select(($filter | length) == 0 or ($filter | index($u.username)))
  | [ $u.username, $u.displayName, $g.name, $sub, $models, ($pw[$u.username] // ""),
      ([ range(1; $kpu + 1)
         | . as $i
         | ($u.username + "-" + $sub + "-"
            + (if $i < 10 then "0" else "" end) + ($i | tostring)) as $kname
         | $kname + $ps + ({ name: $kname,
                             description: ("MaaS key for " + $u.displayName + " (" + $g.name + ")"),
                             expiration: $exp } | tojson)
       ] | join($ks))
    ] | join($fs)' "$CONFIG" > "$WORK/worklist.txt"
chmod 600 "$WORK/worklist.txt"

N_ROWS="$(wc -l < "$WORK/worklist.txt" | tr -d ' ')"

# Mint every key for one user. Runs as a background job under --parallel, so it
# reports results by appending to files rather than setting variables.
mint_user() {
  local username="$1" display="$2" gname="$3" sub="$4" models="$5" pw="$6" keysfield="$7"
  local token pair kname body resp_file http_code api_key key_id key_prefix created expires verified verify_code
  local -a pairs

  if [[ -z "$pw" ]]; then
    printf 'no-password\t%s\n' "$username" >> "$FAILED"
    warn "no stored password for ${username} (re-run without --skip-infra)"
    return 0
  fi

  token="$(get_user_token "$username" "$pw" || true)"
  if [[ -z "$token" ]]; then
    printf 'no-token\t%s\n' "$username" >> "$FAILED"
    warn "could not obtain an OpenShift token for ${username}"
    return 0
  fi

  IFS="$SEP_KEY" read -ra pairs <<< "$keysfield"
  for pair in "${pairs[@]}"; do
    [[ -n "$pair" ]] || continue
    kname="${pair%%${SEP_PAIR}*}"
    body="${pair#*${SEP_PAIR}}"

    if [[ "$ROTATE" != true ]] && grep -qxF "$kname" "$WORK/minted_names.txt" 2>/dev/null; then
      skip "${kname} already minted (use --rotate for a fresh key)"
      continue
    fi

    if [[ "$KEEP_RAW" == true ]]; then
      resp_file="$OUT_DIR/responses/${kname}.json"
    else
      resp_file="$WORK/resp-${kname}.json"
    fi

    http_code="$(curl -sk -m 60 -w '%{http_code}' -o "$resp_file" \
      -X POST "${MAAS_API}/v1/api-keys" \
      -H "Authorization: Bearer ${token}" \
      -H "X-MaaS-Subscription: ${sub}" \
      -H 'Content-Type: application/json' \
      -d "$body" 2>/dev/null || echo 000)"

    if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
      printf 'http-%s\t%s\n' "$http_code" "$kname" >> "$FAILED"
      warn "${kname}: HTTP ${http_code} - $(jq -rc '.error // .message // .' "$resp_file" 2>/dev/null | head -c 160)"
      continue
    fi

    # The secret is only ever returned here. Prefer the documented field, but fall
    # back to a prefix scan so a field rename cannot silently lose the key.
    api_key="$(jq -r '.key // .apiKey // .api_key // empty' "$resp_file" 2>/dev/null)"
    [[ -n "$api_key" ]] || api_key="$(grep -oE 'sk-oai-[A-Za-z0-9._-]+' "$resp_file" | head -1)"
    if [[ -z "$api_key" ]]; then
      printf 'no-key-in-response\t%s\n' "$kname" >> "$FAILED"
      warn "${kname}: minted but no key found in response"
      continue
    fi

    key_id="$(jq -r '.id // .keyId // empty' "$resp_file" 2>/dev/null)"
    key_prefix="$(jq -r '.keyPrefix // empty' "$resp_file" 2>/dev/null)"
    created="$(jq -r '.createdAt // empty' "$resp_file" 2>/dev/null)"
    expires="$(jq -r '.expiresAt // .expires_at // empty' "$resp_file" 2>/dev/null)"
    [[ -n "$expires" ]] || expires="$(compute_expiry "$EXP_HOURS")"

    if [[ "$VERIFY" == true ]]; then
      verify_code="$(curl -sk -m 30 -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${api_key}" "${MAAS_BASE}/v1/models" 2>/dev/null || echo 000)"
      [[ "$verify_code" == "200" ]] && verified="yes" || verified="no(${verify_code})"
    else
      verified="skipped"
    fi

    # Single-line append; concurrent workers stay intact because each record is
    # written by one write() well under the atomic-append size.
    jq -nc \
      --arg key "$api_key" --arg id "$key_id" --arg prefix "$key_prefix" --arg kname "$kname" \
      --arg user "$username" --arg disp "$display" --arg grp "$gname" --arg sub "$sub" \
      --arg created "$created" --arg exp "$expires" --arg base "$MAAS_BASE" \
      --arg models "$models" --arg ver "$verified" \
      '{key:$key, id:$id, keyPrefix:$prefix, keyName:$kname, username:$user,
        displayName:$disp, group:$grp, subscription:$sub, createdAt:$created,
        expiresAt:$exp, baseUrl:$base, models:$models, verified:$ver}' >> "$MINTED"

    if [[ "$verified" == "no("* ]]; then
      warn "${kname} minted but gateway check returned ${verify_code}"
    else
      ok "${kname}  ${C_DIM}${api_key:0:18}...${C_RESET}"
    fi
  done
}

if [[ "$DRY_RUN" == true ]]; then
  skip "would mint up to $(( N_ROWS * KEYS_PER_USER )) key(s) for ${N_ROWS} user(s)"
else
  (( PARALLEL > 1 )) && info "minting with ${PARALLEL} concurrent workers"
  launched=0
  while IFS="$SEP_FIELD" read -r f_user f_disp f_group f_sub f_models f_pw f_keys; do
    [[ -n "$f_user" ]] || continue
    if (( PARALLEL > 1 )); then
      mint_user "$f_user" "$f_disp" "$f_group" "$f_sub" "$f_models" "$f_pw" "$f_keys" &
      launched=$(( launched + 1 ))
      (( launched % PARALLEL == 0 )) && wait || true
    else
      mint_user "$f_user" "$f_disp" "$f_group" "$f_sub" "$f_models" "$f_pw" "$f_keys"
    fi
  done < "$WORK/worklist.txt"
  wait || true
fi

MINT_OK="$(wc -l < "$MINTED" | tr -d ' ')"
MINT_FAIL="$(wc -l < "$FAILED" | tr -d ' ')"

# ---------------------------------------------------------------------------
# phase 5 - collate and export
# ---------------------------------------------------------------------------

step "Export"

if [[ "$DRY_RUN" == true ]]; then
  skip "dry run - nothing written"
else
  # Fold this run's mints into the durable ledger, then rebuild every export from
  # the ledger as a whole. Exports must never be derived from one run alone: a
  # re-run skips already-minted users, so doing so drops them from the output and
  # (since the secret is unrecoverable) loses their key for good.
  if (( MINT_OK > 0 )); then
    cat "$MINTED" >> "$LEDGER"
    chmod 600 "$LEDGER"
  fi

  if [[ ! -s "$LEDGER" ]]; then
    warn "no keys on record; nothing written"
  else
  # Last-wins dedup by key name, so a --rotate supersedes the earlier record.
  jq -s 'reduce .[] as $r ({}; .[$r.keyName] = $r) | [.[]] | sort_by(.subscription, .username)' \
    "$LEDGER" > "$WORK/all.json"
  TOTAL_KEYS="$(jq 'length' "$WORK/all.json")"
  CARRIED=$(( TOTAL_KEYS - MINT_OK ))
  (( CARRIED > 0 )) && info "carrying ${CARRIED} key(s) from previous runs"

  # --- per-subscription collation (one pass over all records) ---------------
  jq --arg gen "$GENERATED_AT" '
    group_by(.subscription)
    | map({
        subscription: .[0].subscription,
        group:        .[0].group,
        baseUrl:      .[0].baseUrl,
        models:       (.[0].models | split(" ")),
        generatedAt:  $gen,
        userCount:    (map(.username) | unique | length),
        keyCount:     length,
        keys: ( sort_by(.username)
                | map({ username, displayName, keyName,
                        id, keyPrefix, apiKey: .key,
                        createdAt, expiresAt, verified }) )
      })
    | sort_by(.subscription)' "$WORK/all.json" > "$COLLATED"
  chmod 600 "$COLLATED"
  ok "wrote $COLLATED (${TOTAL_KEYS} key(s) across $(jq 'length' "$COLLATED") subscription(s))"

  while IFS= read -r sub; do
    jq --arg s "$sub" '.[] | select(.subscription == $s)' "$COLLATED" \
      > "$OUT_DIR/subscriptions/${sub}.json"
    chmod 600 "$OUT_DIR/subscriptions/${sub}.json"
    ok "wrote subscriptions/${sub}.json ($(jq -r --arg s "$sub" \
      '.[] | select(.subscription == $s) | "\(.keyCount) key(s), \(.userCount) user(s)"' "$COLLATED"))"
  done < <(jq -r '.[].subscription' "$COLLATED")

  # --- flat CSV -------------------------------------------------------------
  {
    printf 'api_key,key_id,key_name,username,display_name,group,subscription,expires_at,base_url,models,verified,key_prefix,created_at\n'
    jq -r '.[] | [.key, .id, .keyName, .username, .displayName, .group, .subscription,
            .expiresAt, .baseUrl, .models, .verified, .keyPrefix, .createdAt] | @csv' "$WORK/all.json"
  } > "$CSV"
  chmod 600 "$CSV"
  ok "wrote $CSV"

  # --- idempotency index (single merge, not one rewrite per key) ------------
  jq --slurpfile idx "$INDEX" \
    '($idx[0] // {}) + (map({key: .keyName, value: {id: .id, expiresAt: .expiresAt}}) | from_entries)' \
    "$WORK/all.json" > "$WORK/idx.merged" && mv "$WORK/idx.merged" "$INDEX"

  # --- reconcile: keys we know were issued but hold no secret for -----------
  # Only flag users still present in the config; stale names from an older roster
  # are not actionable.
  # Deliberately unfiltered by --users: a missing secret is worth surfacing on every
  # run, not just the one that happened to target that user.
  jq -r --argjson kpu "$KEYS_PER_USER" '
    .groups[] as $g
    | (($g.subscription.name) // $g.name) as $sub
    | $g.users[]
    | (if type == "string" then . else .username end) as $un
    | range(1; $kpu + 1)
    | ($un + "-" + $sub + "-" + (if . < 10 then "0" else "" end) + (. | tostring))
      + "\t" + $un' \
    "$CONFIG" | sort -u > "$WORK/expected_pairs.txt"
  cut -f1 "$WORK/expected_pairs.txt" | sort -u > "$WORK/expected.txt"
  jq -r '.[].keyName' "$WORK/all.json" | sort -u > "$WORK/have.txt"
  jq -r 'keys[]' "$INDEX" | sort -u > "$WORK/known.txt"

  ORPHANS="$(comm -12 "$WORK/expected.txt" "$WORK/known.txt" | comm -23 - "$WORK/have.txt")"
  if [[ -n "$ORPHANS" ]]; then
    warn "issued previously but no secret on record (unrecoverable - re-mint these):"
    printf '%s\n' "$ORPHANS" | while IFS= read -r o; do
      [[ -n "$o" ]] || continue
      info "    ${o}"
    done
    # Map key names back to usernames via the generated pairs; the subscription
    # segment contains hyphens, so the name cannot be split apart reliably.
    ORPHAN_USERS="$(awk -F'\t' 'NR==FNR {o[$0]=1; next} ($1 in o) {print $2}' \
      <(printf '%s\n' "$ORPHANS") "$WORK/expected_pairs.txt" | sort -u | paste -sd, -)"
    info "    fix: ./provision-maas-keys.sh --rotate --users ${ORPHAN_USERS}"
  fi
  fi
fi

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------

step "Summary"
info "groups configured : ${N_GROUPS}"
info "users configured  : ${N_USERS}"
info "keys minted       : ${MINT_OK}"
if (( MINT_FAIL > 0 )); then
  warn "keys failed       : ${MINT_FAIL}"
  info "failure reasons:"
  sort "$FAILED" | awk -F'\t' '{c[$1]++} END {for (r in c) printf "      %-22s %d\n", r, c[r]}'
fi

if [[ "$DRY_RUN" != true ]] && (( MINT_OK > 0 )); then
  cat <<EOF

    ${C_BOLD}Hand a user their key and they can call the model directly:${C_RESET}

      curl -sk ${MAAS_BASE}/vllm-project/llama-32-1b-instruct-maas/v1/chat/completions \\
        -H "Authorization: Bearer sk-oai-..." \\
        -H 'Content-Type: application/json' \\
        -d '{"model":"llama-32-1b-instruct-maas","messages":[{"role":"user","content":"hi"}]}'

    ${C_BOLD}${C_YELLOW}${OUT_DIR} contains live credentials - do not commit it.${C_RESET}
EOF
fi

printf '\n'
