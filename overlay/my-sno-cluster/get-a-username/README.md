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

3. **Workshop user password** — `secret.yaml` holds `LAB_USER_ACCESS_TOKEN`, `LAB_USER_PASS`,
   and `LAB_ADMIN_PASS` (all the same value). This must match whatever password the workshop
   `userN` accounts actually have on the cluster (e.g. via HTPasswd IDP) — it is **not**
   validated against anything by this tool itself, it's just what the tool tells attendees to
   log in with. Rotate it per workshop run if desired.

## How it works

- `bases/get-a-username/` — Redis (Deployment + Service + PVC + Secret) and the
  `get-a-username` Deployment/Service, generic across clusters.
- `configmap.yaml` / `secret.yaml` here — cluster- and workshop-run-specific env vars, injected
  into the `get-a-username` container via `envFrom`.
- `route.yaml` — exposes the tool on the default cluster wildcard domain (empty `host`).

## Verifying

```bash
oc get pods -n guides
oc get route get-a-username -n guides -o jsonpath='{.spec.host}{"\n"}'
```
