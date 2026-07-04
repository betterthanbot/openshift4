# get-a-username Overlay

Deploys the [username-distribution](https://quay.io/openshiftlabs/username-distribution) tool
(`get-a-username`) plus its Redis backend into the `guides` namespace. This replaces the old
Ansible playbook that ran `oc process redis-persistent` + `oc new-app --as-deployment-config`
by hand — it's now just another GitOps-managed workload.

## Before deploying

1. **Cluster FQDN** — `configmap.yaml` has the placeholder domain `apps.cluster.example.com` in
   `LAB_MODULE_URLS` and `LAB_EXTRA_URLS`. Update it for your cluster:

   ```bash
   sed -i 's/apps.cluster.example.com/apps.<NEW-CLUSTER-DOMAIN>/g' \
     overlay/my-sno-cluster/get-a-username/configmap.yaml
   ```

2. **User count / title / duration** — edit `LAB_USER_COUNT`, `LAB_TITLE`, and
   `LAB_DURATION_HOURS` in `configmap.yaml` as needed per workshop run.
   Currently set to 100 users / "Keycloak Workshop" / 8h.

3. **Workshop user password — never committed to git.** `secret.yaml` only holds placeholder
   values (`<set-me-oc-edit>`). ArgoCD creates it once with those placeholders and then never
   touches its data again (`Prune=false` annotation + `ignoreDifferences` on `/data` in
   `argocd/appset-workloads.yaml`). Set the real value directly on the cluster:

   ```bash
   oc edit secret get-a-username-secret -n guides
   # set LAB_USER_ACCESS_TOKEN, LAB_USER_PASS, LAB_ADMIN_PASS to the same real value
   ```

   This must match the password baked into the `workshop-htpasswd` identity provider (see
   below) — it's just what this tool tells attendees to log in with, not a credential it
   enforces itself.

## Authentication — letting attendees actually log in

Creating `User` objects (e.g. via `bases/get-a-username/label-ns.sh`) is not enough — OpenShift
needs an identity provider before anyone can authenticate as `user1`..`userN`. This repo manages
one via `operators/layer2-operands/templates/workshop-htpasswd.yaml` (an `HTPasswd` entry on
`OAuth/cluster`), backed by a Secret (`workshop-htpasswd`, in `openshift-config`) that — same as
above — is committed only as an empty placeholder and never holds real password hashes in git.

Set the real hashes directly on the cluster after first sync:

```bash
PASS='<workshop-password>'          # must match secret.yaml above
> htpasswd.txt
for i in $(seq 1 100); do htpasswd -Bbn "user${i}" "$PASS" >> htpasswd.txt; done

oc create secret generic workshop-htpasswd -n openshift-config \
  --from-file=htpasswd=htpasswd.txt \
  --dry-run=client -o yaml | oc apply -f -

rm htpasswd.txt   # don't leave the real hashes lying around locally either
```

The `authentication` cluster operator briefly rolls (~30-60s) after this — expect a short
disruption to *all* console logins, not just workshop users.

## How it works

- `bases/get-a-username/` — Redis (Deployment + Service + PVC + Secret) and the
  `get-a-username` Deployment/Service, generic across clusters.
- `configmap.yaml` here — cluster- and workshop-run-specific env vars, injected into the
  `get-a-username` container via `envFrom`. Non-sensitive, safe to commit.
- `secret.yaml` here — placeholder only; see "Workshop user password" above.
- `route.yaml` — exposes the tool on the default cluster wildcard domain (empty `host`).

## Verifying

```bash
oc get pods -n guides
oc get route get-a-username -n guides -o jsonpath='{.spec.host}{"\n"}'
```
