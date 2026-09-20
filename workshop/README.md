# OpenShift Workshop — Scheduling & Health Probes

Cluster: 3 masters, 3 workers, `sched-demo` namespace. No Routes required.

`00-setup.sh` discovers the three workers by role and sorts them, so node
replacement before the workshop doesn't break anything. It prints the mapping
and writes it to `.demo-nodes`:

| Slot | Workshop role |
|---|---|
| WORKER_A (ip-10-0-16-177) | `hardware=gpu`, `node-tier=premium`, tainted `dedicated=gpu:NoSchedule` |
| WORKER_B (ip-10-0-33-190) | `hardware=cpu`, plain |
| WORKER_C (ip-10-0-54-75) | `hardware=cpu`, `demo-role=evictme` — NoExecute victim in Demo 3 |
| 3 masters | default control-plane taint, untouched |

## Prep

```bash
chmod +x 00-setup.sh 99-cleanup.sh
./00-setup.sh
source .demo-nodes      # gives you $WORKER_A/$WORKER_B/$WORKER_C in your shell
```

All scheduling is driven by **labels**, never by hostname, so nothing in the
YAML needs editing if the cluster changes under you.

## Terminal layout

Left pane, keep it running all session:

```bash
watch -n2 'oc get pods -n sched-demo -o wide'
```

Right pane, the one-liner you will use over and over:

```bash
oc get pod <name> -n sched-demo -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].message}{"\n"}'
oc describe pod <name> -n sched-demo | tail -20
oc get events -n sched-demo --sort-by=.lastTimestamp | tail -15
```

**On the event text below:** the scheduler aggregates *every* failing predicate
across all 6 nodes, so a real message is usually longer than the one quoted —
e.g. a pod that fails on selector will also report `3 node(s) had untolerated
taint {node-role.kubernetes.io/master: }` for the control plane. Quote the
clause that matters and tell the class to read the whole line. That habit is
the actual takeaway of this section.

---

## Part 1 — nodeSelector

```bash
oc apply -f 01-nodeselector.yaml
oc get pods -n sched-demo -o wide -l demo=nodeselector
```

| Pod | Expected | Why |
|---|---|---|
| p01-baseline | Running on a worker | no constraints |
| p02-nodeselector-missing-label | **Pending** | `6 node(s) didn't match Pod's node affinity/selector` |
| p03-nodeselector-no-toleration | **Pending** | `1 node(s) had untolerated taint {dedicated: gpu}` + 5 don't match |
| p04-nodeselector-with-toleration | Running on the gpu node | selector **and** toleration |

Live fix for p02 — label a node and watch it schedule with no pod edit:

```bash
oc label node "$WORKER_B" hardware=fpga --overwrite
# p02 goes Pending -> Running within a few seconds
oc label node "$WORKER_B" hardware=cpu --overwrite   # revert
```

Then make the second half of the point: `p02` is now Running, and it **stays**
Running after you revert the label. Node labels are evaluated at scheduling
time only — that is literally what `IgnoredDuringExecution` means. Nothing
re-evaluates placement once a pod is bound.

Key line: **a nodeSelector is an AND of every label listed, and it is a hard filter — there is no "close enough".**

---

## Part 2 — Taints & tolerations

```bash
oc apply -f 02-taints-tolerations.yaml
oc get pods -n sched-demo -o wide -l demo=taints
```

| Pod | Expected | Point |
|---|---|---|
| p05-toleration-only | Running on a **plain** worker | toleration is permission, not attraction |
| p06-toleration-wrong-value | **Pending** | `Equal` matches key+value+effect; `ml != gpu` |
| p07-toleration-exists | Running on the gpu node | `Exists` ignores value; omitted `effect` tolerates all effects |
| p10-runs-on-master | Running on a master | this is exactly how monitoring/CNI operators get there |

Cheat sheet:

| Effect | New pods | Already-running pods |
|---|---|---|
| `NoSchedule` | blocked | untouched |
| `PreferNoSchedule` | discouraged | untouched |
| `NoExecute` | blocked | **evicted** |

### Demo 3 — NoExecute live eviction

Both victims are pinned to `$WORKER_C` via `demo-role=evictme`, with a 5s grace
period so the teardown is instant on screen. In a second pane:

```bash
oc get pods -n sched-demo -l demo=noexecute -w
```

Then drop the taint:

```bash
oc adm taint node "$WORKER_C" maintenance=true:NoExecute
```

- `p08-noexecute-victim` → terminated immediately (no toleration).
- `p09-noexecute-grace60` → survives, dies at ~60s (`tolerationSeconds: 60`).

Bare pods do not reschedule — that is the lesson. Mention that `node.kubernetes.io/not-ready` and `unreachable` are NoExecute taints the kubelet applies automatically, with a default 300s toleration injected into every pod:

```bash
oc get pod p01-baseline -n sched-demo -o jsonpath='{.spec.tolerations}' | python3 -m json.tool
```

Remove the taint, then re-apply the two pods (they are gone for good):

```bash
oc adm taint node "$WORKER_C" maintenance:NoExecute-
oc apply -f 02-taints-tolerations.yaml
```

---

## Part 3 — Affinity, anti-affinity, DaemonSets

```bash
oc apply -f 03-affinity-daemonsets.yaml
oc get pods -n sched-demo -o wide
```

| Object | Expected |
|---|---|
| p11-affinity-required-fail | **Pending** — required nodeAffinity, gpu node tainted |
| p12-affinity-preferred-ok | Running — preferred never blocks, it only scores |
| d13-antiaffinity (4 replicas) | **2 Running / 2 Pending** — only 2 untainted workers, 1 pod per host |
| d14-podaffinity | Running, co-located with `spread-me` pods |
| d15-topologyspread | 4 Running, balanced across AZs |
| p16-insufficient-cpu | **Pending** — `Insufficient cpu` on the workers; nothing to do with taints |
| ds17-no-tolerations | DESIRED **2** — skips 3 masters and the gpu node |
| ds18-tolerate-all | DESIRED **6** — `tolerations: [{operator: Exists}]` |

```bash
oc get ds -n sched-demo
oc get pods -n sched-demo -l demo=daemonset -o wide
oc describe pod -n sched-demo -l app=spread-me | grep -A2 "FailedScheduling"
```

Fix the anti-affinity Pendings live, two ways:

```bash
oc scale deploy/d13-antiaffinity -n sched-demo --replicas=2     # shrink to fit
# or widen the pool by removing the gpu taint — a Pending pod schedules within seconds:
oc adm taint node "$WORKER_A" dedicated:NoSchedule-
oc adm taint node "$WORKER_A" dedicated=gpu:NoSchedule --overwrite   # put it back
```

Removing the taint is the better demo: it shows the scheduler retrying Pending
pods continuously, with no action from you. Note the 4th replica stays Pending
either way — 3 workers, 1 pod per host.

To force a **topology spread** failure, flip `whenUnsatisfiable` to `DoNotSchedule` in `d15`, then:

```bash
oc cordon "$WORKER_B"
oc scale deploy/d15-topologyspread -n sched-demo --replicas=6
oc uncordon "$WORKER_B"
```

Closing summary for Part 3:

| Mechanism | Granularity | Fails how |
|---|---|---|
| nodeSelector | node labels, equality only | Pending |
| nodeAffinity required | node labels, operators (In/NotIn/Exists/Gt/Lt) | Pending |
| nodeAffinity preferred | scoring | never |
| podAffinity / anti-affinity | other pods, per topologyKey | Pending |
| topologySpread | even distribution | Pending only if `DoNotSchedule` |
| Taints/tolerations | node repels pods | Pending, or eviction on NoExecute |

---

## Part 4 — Readiness, liveness, startup probes

```bash
oc apply -f 04-probes.yaml
watch -n2 'oc get pods -n sched-demo -l demo=probes'
```

| Pod | Expected after ~2 min | Lesson |
|---|---|---|
| h01-probes-healthy | `1/1 Running`, 0 restarts | all three probes, correctly tuned |
| h02-readiness-fail | `0/1 Running`, **0 restarts**, forever | readiness removes traffic, never restarts |
| h03-liveness-fail | restarts climbing → `CrashLoopBackOff` | liveness kills the container |
| h04-liveness-exec-flapping | healthy 45s → restart → repeat | exec probe, non-zero exit = failure |
| h05-slowstart-no-startupprobe | permanent `CrashLoopBackOff` | liveness fired during boot |
| h06-slowstart-with-startupprobe | `0/1` until ~90s, then `1/1` | startupProbe gates the other probes |
| h07-tcp-probe-fail | `0/1 Running` | `connection refused` on the TCP dial |

Endpoint proof (this is the readiness payoff):

```bash
oc get endpointslices -n sched-demo -l kubernetes.io/service-name=svc-web \
  -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{" ready="}{.conditions.ready}{"\n"}{end}'
```

`h01` is ready, `h02` is not — same Service, same selector, only the probe differs.

Probe events, verbatim:

```bash
oc describe pod h03-liveness-fail -n sched-demo | grep -A5 Events
oc get events -n sched-demo --field-selector reason=Unhealthy --sort-by=.lastTimestamp | tail
```

Live repair of `h05` (edit, don't recreate):

```bash
oc patch pod h05-slowstart-no-startupprobe -n sched-demo --type=json \
  -p='[{"op":"replace","path":"/spec/containers/0/livenessProbe/initialDelaySeconds","value":120}]'
# -> rejected: pod probes are immutable. Use a Deployment in real life.
```

That rejection is worth showing: **probe tuning requires a new pod spec**, which is why probes belong in a Deployment, not a bare Pod.

Closing table:

| Probe | Failure result | Gates Service traffic | Typical mistake |
|---|---|---|---|
| startup | container killed after budget | no | omitted on slow JVM/DB apps |
| readiness | pod removed from endpoints | **yes** | same endpoint as liveness |
| liveness | container restarted | no | too aggressive, restarts a healthy-but-busy app |

Rules of thumb to leave them with:
- Liveness should test "is this process wedged", not "are my dependencies up". A liveness probe that checks the database restarts your app during every DB blip.
- Readiness is the one that should check dependencies.
- `failureThreshold × periodSeconds` is the real budget. Say it out loud for each probe.
- No liveness probe at all is better than a bad one.

---

## Cleanup

```bash
./99-cleanup.sh
```

## Notes

- Images: `registry.access.redhat.com/ubi9/ubi-minimal` and `ubi9/httpd-24`. Pre-pull or mirror if the workshop cluster is disconnected.
- Every pod carries the restricted-v2 securityContext, so nothing trips Pod Security Admission.
- Requests are tiny (10–20m CPU) so the whole lab fits on two workers — except `p16`, which is meant to fail.
