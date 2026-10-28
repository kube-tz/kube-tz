# kube-tz — Kubernetes Timezone Injector (Helm Chart)

**kube-tz** makes every Pod in your cluster run in the timezone you choose — automatically.

Containers normally run in **UTC**. That makes logs, `date` output, cron jobs and many apps show the "wrong" time.
kube-tz fixes this without you touching any Deployment or image: it uses a built-in Kubernetes feature called a
**MutatingAdmissionPolicy** to add the timezone to Pods as they are created.

- ✅ No webhook server, no certificates, no extra Pods to run or keep healthy
- ✅ One default timezone for the whole cluster, with an easy per-Pod override
- ✅ Choose which namespaces are included or skipped
- ✅ Secure defaults (the helper init container is compatible with the Pod Security `restricted` profile)

---

## Table of contents

1. [How it works](#how-it-works)
2. [Prerequisites](#prerequisites)
3. [Quick start (TL;DR)](#quick-start-tldr)
4. [Step-by-step installation](#step-by-step-installation)
5. [Check that it works](#check-that-it-works)
6. [Choosing the timezone](#choosing-the-timezone)
7. [Skipping or targeting Pods and namespaces](#skipping-or-targeting-pods-and-namespaces)
8. [The container image](#the-container-image)
9. [Values reference](#values-reference)
10. [Common examples](#common-examples)
11. [hostPath mode](#hostpath-mode)
12. [Upgrade](#upgrade)
13. [Uninstall](#uninstall)
14. [Troubleshooting](#troubleshooting)
15. [FAQ](#faq)
16. [Contributing and license](#contributing-and-license)

---

## How it works

When a Pod is created, the Kubernetes API server runs the kube-tz policy and changes the Pod **before** it is saved:

```
 you create a Pod
        │
        ▼
 ┌────────────────────────────── API server ──────────────────────────────┐
 │  kube-tz policy (runs inside the API server, nothing to deploy)        │
 │                                                                        │
 │  1. adds an init container "kube-tz" that copies the tz database       │
 │     into a small shared volume (emptyDir)                              │
 │  2. adds env var  TZ=<timezone>  to every container                    │
 │  3. mounts the tz database at  /usr/share/zoneinfo                     │
 │  4. mounts the chosen zone file at  /etc/localtime                     │
 │  5. adds annotations so you can see what happened                      │
 └────────────────────────────────────────────────────────────────────────┘
        │
        ▼
 Pod starts → `date` shows your timezone
```

Things worth knowing:

- It only changes Pods **when they are created**. Pods that are already running are not touched.
- It never overwrites anything you set yourself. If a container already has a `TZ` variable, or already mounts
  something at `/etc/localtime` or `/usr/share/zoneinfo`, kube-tz leaves that alone.
- It changes the timezone *inside the Pod*. It does **not** change a CronJob's schedule timezone
  (use `spec.timeZone` on the CronJob for that).

---

## Prerequisites

| Requirement | Details |
|---|---|
| Kubernetes | **1.36 or newer** (`MutatingAdmissionPolicy` is GA as `admissionregistration.k8s.io/v1` from 1.36) |
| Helm | Helm 3 |
| Permissions | Cluster-admin (the policy and binding are cluster-scoped objects) |
| Volumes | Pods must be allowed to use `emptyDir` (default). `hostPath` is only needed for [hostPath mode](#hostpath-mode) |
| Image | A container image with the tz database — see [The container image](#the-container-image) |

Not sure about your cluster version or the API? Check with:

```bash
kubectl version
kubectl api-resources --api-group=admissionregistration.k8s.io
```

You should see `mutatingadmissionpolicies` and `mutatingadmissionpolicybindings` in the list.

> **On Kubernetes 1.34 / 1.35?** The feature is beta there and disabled by default. You must enable the
> `MutatingAdmissionPolicy` feature gate and the beta API on the API server, then install with
> `--set policy.apiVersion=admissionregistration.k8s.io/v1beta1`. You will also need to relax the chart's
> `kubeVersion` constraint in `Chart.yaml`.

---

## Quick start (TL;DR)

```bash
helm install kube-tz ./kube-tz \
  --namespace kube-tz --create-namespace \
  --set timezone=Asia/Kolkata
```

Then create any Pod and run `date` in it. That's it.

---

## Step-by-step installation

### 1. Get the chart

From a clone of this repository:

```bash
git clone <your-repo-url>
cd kube-tz
```

(Once the chart is published to a Helm repository or an OCI registry you will be able to install it from there
instead — replace the placeholders below with your real location.)

```bash
# Helm repository
helm repo add kube-tz <your-helm-repo-url>
helm repo update

# or OCI
helm install kube-tz oci://<your-registry>/charts/kube-tz --version 0.1.0
```

### 2. Make sure the image is available

The chart needs an image that contains the timezone database. Build and push it once
(details in [The container image](#the-container-image)):

```bash
docker build -t <your-registry>/kube-tz:2026e .
docker push <your-registry>/kube-tz:2026e
```

### 3. Install

```bash
helm install kube-tz ./kube-tz \
  --namespace kube-tz --create-namespace \
  --set timezone=Asia/Kolkata 
```

Or put your settings in a file, which is easier to keep in Git:

```yaml
# my-values.yaml
timezone: Asia/Kolkata
image:
  repository: <your-registry>/kube-tz
  tag: "2026e"
namespaces:
  exclude:
    - kube-system
    - monitoring
```

```bash
helm install kube-tz ./kube-tz -n kube-tz --create-namespace -f my-values.yaml
```

### 4. Confirm the objects exist

```bash
kubectl get mutatingadmissionpolicy,mutatingadmissionpolicybinding
```

```
NAME                                                           MUTATIONS   PARAMKIND   AGE
mutatingadmissionpolicy.admissionregistration.k8s.io/kube-tz   2           <unset>     10s

NAME                                                                          POLICYNAME   PARAMREF   AGE
mutatingadmissionpolicybinding.admissionregistration.k8s.io/kube-tz-binding   kube-tz      <unset>    10s
```

> The policy and binding are **cluster-wide**. The `kube-tz` namespace created by `--create-namespace` only holds
> the Helm release record — no Pods run there.

---

## Check that it works

Create a test Pod (this Pod is created **after** the install, so it gets injected):

```bash
kubectl run tz-test --image=busybox:1.37 --restart=Never -- sleep 3600
```

Look at the time inside the Pod:

```bash
kubectl exec tz-test -- date
```

See what kube-tz added:

```bash
# Status annotations
kubectl get pod tz-test -o jsonpath='{.metadata.annotations}{"\n"}'

# The TZ variable
kubectl get pod tz-test -o jsonpath='{.spec.containers[0].env}{"\n"}'

# The helper init container
kubectl get pod tz-test -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
```

Expected annotations:

| Annotation | Meaning |
|---|---|
| `kube-tz.io/status: injected` | The timezone was added |
| `kube-tz.io/status: skipped-invalid-timezone` | The requested name was not a valid timezone name, so nothing was added |
| `kube-tz.io/injected-timezone: <name>` | The timezone that was requested / used |

Clean up:

```bash
kubectl delete pod tz-test
```

---

## Choosing the timezone

### Cluster-wide default

Set it at install time:

```bash
helm upgrade --install kube-tz ./kube-tz -n kube-tz --set timezone=America/New_York
```

Use an [IANA timezone name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) such as
`UTC`, `Europe/Paris`, `America/Argentina/Buenos_Aires` or `Asia/Tokyo`.

### One Pod (or one Deployment) different from the default

Add the annotation `kube-tz.io/name` to the **Pod**. For a Deployment, put it in the **Pod template**, not on the
Deployment itself:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  selector:
    matchLabels: { app: my-app }
  template:
    metadata:
      labels: { app: my-app }
      annotations:
        kube-tz.io/name: Asia/Tokyo      # <- this Pod runs in Tokyo time
    spec:
      containers:
        - name: app
          image: nginx:alpine
```

Rules for timezone names:

- Letters, digits, `_`, `+` and `-`, separated by `/` — for example `Etc/GMT+5`, `EST5EDT`, `UTC`.
- **No dots** (`.`), so path tricks like `../` can never work.
- At most 64 characters.
- A name that looks valid but doesn't exist (for example `Asia/Kolkatta`) makes the init container fail with a clear
  message and the Pod shows `Init:Error`. See [Troubleshooting](#troubleshooting).

---

## Skipping or targeting Pods and namespaces

### Skip one Pod

```yaml
metadata:
  annotations:
    kube-tz.io/inject: "disabled"
```

### Skip namespaces (default: `kube-system`)

```yaml
namespaces:
  exclude:
    - kube-system
    - cert-manager
```

### Only inject into some namespaces

```yaml
namespaces:
  include:
    - my-app
    - staging
```

`include` and `exclude` can be combined — a namespace must be in `include` (if the list is not empty) and must not
be in `exclude`.

### Use labels instead of names

Inject only into namespaces that carry a label:

```yaml
namespaces:
  selector:
    matchLabels:
      kube-tz.io/inject: "enabled"
```

```bash
kubectl label namespace my-app kube-tz.io/inject=enabled
```

> When `namespaces.selector` is set it **replaces** `include` and `exclude`.

---

## The container image

The init container needs two things: the **tz database** and a tiny **shell + `cp`** to copy it. This repository
includes a `Dockerfile` that builds exactly that on top of `scratch` (no OS, no package manager, tiny attack surface):

```bash
docker build -t <your-registry>/kube-tz:2026e .
docker push <your-registry>/kube-tz:2026e
```

Useful build options:

| Build arg | Default | What it does |
|---|---|---|
| `tzdbversion` | `2026e` | IANA tz database release to download |
| `tzdbsha256` | *(empty)* | If set, the downloaded tarball is verified against this SHA-256 |
| `REDO` | `posix_only` | `posix_only` ships only the standard tree (smaller). Use `posix_right` to include leap-second `right/` data |

```bash
docker build --build-arg tzdbversion=2026e -t <your-registry>/kube-tz:2026e .
```

Keep the image tag equal to the tz database version, and update it when IANA publishes a new release.

If your registry is private, create an image pull secret in **every namespace** where Pods will be injected and list
it in `image.pullSecrets`:

```yaml
image:
  pullSecrets:
    - my-registry-secret
```

---

## Values reference

All values are optional unless stated. Defaults are in [`values.yaml`](./values.yaml).

### General

| Parameter | Description | Default |
|---|---|---|
| `timezone` | Default timezone injected into every matching Pod (IANA name) | `Asia/Kolkata` |
| `nameOverride` | Override the chart name | `""` |
| `fullnameOverride` | Override the full resource name | `""` |
| `commonLabels` | Extra labels added to the policy and binding | `{}` |
| `injectIntoInitContainers` | Also add `TZ` and the mounts to init containers declared by your workloads (the kube-tz init container is always excluded) | `false` |

### Policy (`policy.*`)

| Parameter | Description | Default |
|---|---|---|
| `policy.apiVersion` | API version of the policy and binding. Use `admissionregistration.k8s.io/v1beta1` only on 1.34/1.35 clusters with the feature enabled | `admissionregistration.k8s.io/v1` |
| `policy.policyName` | Name of the `MutatingAdmissionPolicy`. Empty = derived from the release name | `""` |
| `policy.bindingName` | Name of the `MutatingAdmissionPolicyBinding`. Empty = `<name>-binding` | `""` |
| `policy.injectAnnotationKey` | Pod annotation key; set its value to `disabled` to skip a Pod | `kube-tz.io/inject` |
| `policy.timezoneAnnotationKey` | Pod annotation key for a per-Pod timezone | `kube-tz.io/name` |
| `policy.statusAnnotationKey` | Annotation written by the policy: `injected` or `skipped-invalid-timezone` | `kube-tz.io/status` |
| `policy.injectedTimezoneAnnotationKey` | Annotation written by the policy with the timezone used | `kube-tz.io/injected-timezone` |
| `policy.failurePolicy` | `Fail` = if the policy itself errors, the Pod is rejected. `Ignore` = the Pod is created without injection | `Fail` |
| `policy.reinvocationPolicy` | `IfNeeded` = run the policy again if another mutator changed the Pod afterwards. `Never` = run once | `IfNeeded` |
| `policy.operations` | API operations to act on. Pod specs can't be changed after creation, so keep this as `CREATE` | `["CREATE"]` |
| `policy.allowedOSNames` | Only Pods for these operating systems are changed | `["linux"]` |
| `policy.validateTimezone` | Skip injection (and set the status annotation) when the timezone name looks invalid. **Keep this on** | `true` |
| `policy.timezonePattern` | RE2 pattern a timezone name must match. Dots are intentionally not allowed | `^[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)*$` |

### Image (`image.*`)

| Parameter | Description | Default |
|---|---|---|
| `image.repository` | **Required.** Image that contains the tz database and `sh` + `cp` | `quay.io/kube-tz/kube-tz` |
| `image.tag` | Image tag. Empty = chart `appVersion` | `2026e` |
| `image.pullPolicy` | Image pull policy of the init container | `IfNotPresent` |
| `image.pullSecrets` | Pull secrets added to injected Pods. Plain names or `{name: ...}` objects. The Secrets must exist in every target namespace | `[]` |
| `image.zoneInfoPath` | Where the zoneinfo directory lives inside the image | `/opt/tzdata/usr/share/zoneinfo` |

### Init container (`init.*`)

| Parameter | Description | Default |
|---|---|---|
| `init.name` | Name of the injected init container | `kube-tz` |
| `init.command` | Replace the default copy script. It can use `TIMEZONE`, `ZONEINFO_SRC` and must write the tree into `/work` | `[]` (built-in script) |
| `init.resources.requests.cpu` | CPU request | `5m` |
| `init.resources.requests.memory` | Memory request | `8Mi` |
| `init.resources.limits.cpu` | CPU limit | `50m` |
| `init.resources.limits.memory` | Memory limit | `32Mi` |
| `init.securityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |
| `init.securityContext.readOnlyRootFilesystem` | Read-only root filesystem | `true` |
| `init.securityContext.runAsNonRoot` | Refuse to run as root | `true` |
| `init.securityContext.runAsUser` | User ID | `65532` |
| `init.securityContext.runAsGroup` | Group ID | `65532` |
| `init.securityContext.capabilities.drop` | Linux capabilities to drop | `["ALL"]` |
| `init.securityContext.seccompProfile.type` | Seccomp profile | `RuntimeDefault` |

### Volumes and mount paths (`volume.*`)

| Parameter | Description | Default |
|---|---|---|
| `volume.name` | Name of the shared `emptyDir` volume added to Pods | `kube-tz` |
| `volume.zoneInfoMountPath` | Where the full tz database is mounted in every container | `/usr/share/zoneinfo` |
| `volume.localtimeMountPath` | Where the selected zone file is mounted in every container | `/etc/localtime` |
| `volume.sizeLimit` | Size limit of the `emptyDir` | `32Mi` |

### hostPath mode (`hostPath.*`)

| Parameter | Description | Default |
|---|---|---|
| `hostPath.enabled` | Copy the tz database from the **node** instead of from the image | `false` |
| `hostPath.path` | Directory on the node | `/usr/share/zoneinfo` |
| `hostPath.type` | Kubernetes `hostPath` type | `Directory` |

### Namespace targeting (`namespaces.*`)

| Parameter | Description | Default |
|---|---|---|
| `namespaces.include` | Only inject into these namespaces. Empty = all (minus `exclude`) | `[]` |
| `namespaces.exclude` | Never inject into these namespaces | `["kube-system"]` |
| `namespaces.nameLabelKey` | Namespace label that holds the namespace name | `kubernetes.io/metadata.name` |
| `namespaces.selector` | Full label selector; **replaces** `include` / `exclude` when set | `{}` |

---

## Common examples

**Everything in UTC, but skip a few namespaces**

```yaml
timezone: UTC
namespaces:
  exclude: [kube-system, kube-public, monitoring]
```

**Only a single namespace**

```yaml
timezone: Europe/Berlin
namespaces:
  include: [payments]
```

**Opt-in only (label the namespaces you want)**

```yaml
namespaces:
  selector:
    matchLabels:
      kube-tz.io/inject: "enabled"
```

**Private registry**

```yaml
image:
  repository: registry.example.com/platform/kube-tz
  tag: "2026e"
  pullSecrets: [regcred]
```

**Be gentle while rolling out (never block Pods if the policy has a problem)**

```yaml
policy:
  failurePolicy: Ignore
```

**Rename the annotations to your own domain**

```yaml
policy:
  timezoneAnnotationKey: "example.com/timezone"
  injectAnnotationKey: "example.com/tz-inject"
```

---

## hostPath mode

By default the tz database is copied from the **image**. With `hostPath.enabled=true` it is copied from the
**node's** `/usr/share/zoneinfo` instead, so the node's own (for example, OS-patched) data is used.

```bash
helm upgrade --install kube-tz ./kube-tz -n kube-tz --set hostPath.enabled=true
```

Be aware:

- `hostPath` volumes are **blocked** by the Pod Security `baseline` and `restricted` profiles. Injected Pods in
  namespaces enforcing those profiles will be rejected. Only use this in namespaces that enforce `privileged`
  (or no Pod Security enforcement).
- The node's tz directory must exist on **every** node where Pods can run.
- Some nodes ship links that point outside the directory (for example `localtime -> /etc/localtime` on Debian and
  Ubuntu). Those can't be resolved inside the container, so the built-in script skips entries it cannot copy and
  prints a warning such as `kube-tz: warning: skipped '/zoneinfo/localtime'`. This is harmless — the init container
  only fails if your **selected timezone** could not be copied.

---

## Upgrade

```bash
helm upgrade kube-tz ./kube-tz -n kube-tz --reuse-values
```

Upgrading only affects Pods created **afterwards**. To apply a new timezone to existing workloads, restart them:

```bash
kubectl rollout restart deployment/my-app -n my-namespace
```

---

## Uninstall

```bash
helm uninstall kube-tz -n kube-tz
```

This removes the policy and the binding, so new Pods are no longer changed. Pods that were already injected keep
their timezone settings until they are recreated.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `helm install` fails with an unknown kind `MutatingAdmissionPolicy` | Cluster is older than 1.36 | Upgrade the cluster, or see the 1.34/1.35 note under [Prerequisites](#prerequisites) |
| `helm install` fails with `compilation failed` and a CEL error | A template/CEL type problem | Run `helm template ... \| kubectl apply --dry-run=server -f -` and open an issue with the full error |
| Pod still shows the old timezone | The Pod was created **before** the install/upgrade | Delete the Pod, or `kubectl rollout restart` its Deployment |
| Pod is in `Init:Error` and logs say `unknown timezone` | The name is well-formed but doesn't exist (typo) | `kubectl logs <pod> -c kube-tz`; fix the name in `timezone` or in the `kube-tz.io/name` annotation |
| Pod is in `Init:ImagePullBackOff` | Image can't be pulled | Check `image.repository`/`image.tag`, and add `image.pullSecrets` for private registries (secret must exist in the Pod's namespace) |
| Annotation says `skipped-invalid-timezone` | The requested name has characters that aren't allowed (for example `..`, spaces, dots) | Use a plain IANA name |
| Pod is rejected with a `hostPath` / Pod Security error | `hostPath.enabled=true` in a `baseline`/`restricted` namespace | Turn off hostPath mode, or use a namespace that allows it |
| Pods can't be created at all after install | A policy error with `failurePolicy: Fail` | Temporarily set `policy.failurePolicy=Ignore`, then investigate with `kubectl describe` / API server logs |
| `date` is right but your app still shows UTC | The app ignores `TZ` / `/etc/localtime` | Check the app's own timezone setting (for example, the JVM flag `-Duser.timezone`) |
| Nothing changes for one specific Pod | It has `kube-tz.io/inject: disabled`, it is in an excluded namespace, or it is a Windows Pod | Check the annotation, `namespaces.*` values and the Pod's `spec.os` |

Useful commands:

```bash
# What did the policy decide for this Pod?
kubectl get pod <pod> -o jsonpath='{.metadata.annotations}{"\n"}'

# Init container output
kubectl logs <pod> -c kube-tz

# What does the live policy contain?
kubectl get mutatingadmissionpolicy kube-tz -o yaml

# See what the chart renders without installing
helm template kube-tz ./kube-tz --kube-version 1.36.0 -f my-values.yaml
```

---

## FAQ

**Does this restart or change my running Pods?**
No. Only new Pods are changed.

**Do I need to change my Deployments or images?**
No. The policy works on any image, including images that have no timezone data.

**What if my container already sets `TZ` or mounts `/etc/localtime`?**
kube-tz leaves your settings alone and only adds what is missing.

**Does it work for Pods created by Jobs, CronJobs, DaemonSets and StatefulSets?**
Yes — all of them create Pods, and Pods are what kube-tz changes. It does not change the CronJob *schedule*
timezone (`spec.timeZone`).

**Does it add a webhook, certificates or a controller Pod?**
No. The policy is evaluated inside the Kubernetes API server.

**What does it cost per Pod?**
One short init container (requests `5m` CPU / `8Mi` memory by default) and a small `emptyDir` (a few MB of the
`32Mi` limit) that holds the tz database.

**Windows nodes?**
Not supported. Pods that declare a non-Linux `spec.os.name` are skipped.

---

## Contributing and license

Issues and pull requests are welcome. Before opening a PR, please run:

```bash
helm lint ./kube-tz --kube-version 1.36.0
helm template kube-tz ./kube-tz --kube-version 1.36.0 | kubectl apply --dry-run=server -f -
```

License: This project is licensed under the [Apache License 2.0](LICENSE) - see the [LICENSE](LICENSE) file for details.
