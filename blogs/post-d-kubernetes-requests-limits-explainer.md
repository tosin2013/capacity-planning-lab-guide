# Kubernetes requests and limits: why both teams are right

**Target audience**: Application developers AND platform engineers  
**Template**: Explainer  
**Word count target**: 800–1,300 words  

---

## Why this argument keeps happening

If you have ever heard one teammate say **resource requests feel hacky** while another insists **you must set requests**, both reactions make sense. Developer pain and platform pain rarely show up in the same dashboard at the same time, so it is easy to talk past each other.

Developers feel **mysterious slowdowns**: the application logs look fine, but latency climbs because the kernel is holding the workload back in ways the app never records. Platform engineers live with a different set of alarms: **evictions**, **over-scheduling**, and cluster-wide strain that capacity tools make obvious.

**ResourceQuota** policies often amplify the frustration. On many production clusters, admission rejects pods that omit requests entirely. Teams then guess, paste defaults, or type the smallest numbers they can get away with. **The real fight is not whether requests are inherently wrong — it is that the consequences of getting them wrong stay invisible to whoever typed the YAML.**

## What requests and limits actually control

**Resource requests** and **resource limits** are two different knobs for two different jobs.

**Requests** are what the Kubernetes scheduler uses to place pods. They also determine **Quality of Service (QoS)** class and eviction priority. Think of a request as a promise to the scheduler about baseline needs.

**Limits** are hard caps. On CPU, the Linux **Completely Fair Scheduler (CFS)** throttles a container that tries to exceed its own CPU ceiling. On memory, exceeding the limit triggers an out-of-memory (OOM) kill.

**CPU throttling from a limit is not "noisy neighbor" behavior.** It fires against the container's own CPU ceiling, regardless of what any other pod is doing.

A lot of cross-team friction comes from conflating requests with limits. Developers sometimes hear "limit" and imagine the node slowing them down because someone else is busy. Platform engineers sometimes hear "requests" and picture steady-state CPU usage. Neither picture matches how Kubernetes actually applies those fields.

## QoS classes, eviction order, and why "almost BestEffort" is a trap

Kubernetes assigns every pod to one of three **Quality of Service (QoS)** classes based on how requests and limits are configured.

**Guaranteed** means CPU and memory requests equal limits for every container in the pod. These pods have the lowest eviction priority — the scheduler protects them until the node is in real trouble.

**Burstable** means requests are lower than limits on at least one resource. This is medium eviction priority and the recommended default for most production applications.

**BestEffort** means no requests and no limits. Those pods have the highest eviction priority and are first targeted under memory pressure. This profile belongs in development and test only.

Eviction order under memory pressure: BestEffort pods first, then Burstable pods using more than their memory request, then Guaranteed pods only if the node is critically low.

Here is the ResourceQuota trap. Quota often requires requests, so true BestEffort is not achievable in those environments. Some teams work around quota with deliberately tiny requests. The workshop uses a concrete example: **10m CPU and 16Mi memory requests**. That pod is Burstable, not BestEffort. Because the declared baseline is so small, it sits near the bottom of the eviction stack — among the first Burstable pods eliminated when memory pressure hits.

**Trading a quota admission pass for placeholder requests buys eviction risk and broken autoscaling.**

## How it goes wrong — two failure modes with real numbers

**Failure mode 1: too low or missing**

In the workshop lab, a **load-generator** pod runs at about **102m CPU**. A **noisy-neighbor** pod with no CPU limit takes roughly **980m CPU** on the same node. The load-generator's CPU falls from **102m to about 45m** — about **56% worse**. If that load-generator were a production API, response times could jump from roughly **50 ms to 500 ms or more**, causing a user-visible outage that looks fine in application logs.

Separately, CPU throttling is a distinct mechanism. A pod with a **200m CPU limit** that tries to use **1000m** gets throttled by CFS at a rate of **0.81** — meaning about **81% of its CPU time is paused**. Developers rarely see this unless they are monitoring kernel-level metrics. On the throttle scale the lab uses: **0.0 is healthy**, **0.5 is severe**, and **1.0 means the container is effectively frozen**.

**Failure mode 2: too high**

Over-requested CPU breaks the **Horizontal Pod Autoscaler (HPA)** (covered in the next section). It also shrinks how many pods the scheduler can place per node, which appears in capacity dashboards as under-utilization — what platform engineers sometimes call **"ghosts"**.

## How to get it right — P95 right-sizing with Prometheus data

The workshop drives right-sizing with a script that reads historical metrics from **Prometheus** and targets the **95th percentile (P95)**.

Why not P99? P99 chases rare spikes and **over-provisions** the cluster. Why not P50? P50 is too aggressive and invites **frequent throttling** under normal load variation. **P95 covers 95% of real workload patterns** while ignoring true outliers.

Concrete rules from the lab:

- **CPU request** = P95 CPU usage; **CPU limit** = 2× the CPU request (burst headroom without unlimited access)
- **Memory request** = P95 memory usage + 20% buffer; **memory limit** = P95 + 50% buffer (memory does not burst like CPU, and OOM recovery is painful)

One script output from the workshop: P95 CPU of **200m** → request **200m**, limit **400m**. P95 memory of **2Mi** → request **8Mi**, limit **8Mi**. The memory buffer math rounds up to a practical minimum floor for small values so the pod is not rejected by quota; the ratio logic holds at larger footprints.

**Right-sizing is not guesswork.** It is reading what the workload actually used over a representative window and giving the scheduler a baseline it can trust.

## The HPA connection — right-sized requests make autoscaling meaningful

HPA scales using the ratio of actual CPU consumption to the **CPU request**. The formula from the lab:

```
Desired Replicas = ceil( Current Replicas × (Current CPU / CPU Request) / Target% )
```

Because CPU request is the denominator, it controls how "busy" HPA thinks you are.

Three outcomes from the lab:

- **Request far too low (example: 2m CPU):** utilization percentages explode. The lab shows **cpu 333% / target 75%**, replicas pinned at **maximum 5**, flapping as load shifts.
- **Request far too high (example: 500m CPU):** utilization sits near **0%**, HPA ignores real load, **replicas stay at minimum 1** under stress.
- **Right-sized request:** the percentage tracks real load and HPA fires at the right moment. As the workshop puts it: **"Right-sizing makes the HPA formula meaningful."**

Developers need HPA to scale at the right time. Platform engineers need HPA to avoid idle replica sprawl. **Both outcomes depend on an honest CPU request.**

## Guaranteed vs Burstable — when to pay for "no burst"

For most production services, **Burstable** is the right QoS class: requests give the scheduler an honest baseline, limits allow CPU to burst when the node has headroom, and HPA can react to measured utilization.

**Guaranteed QoS** — requests equal limits on CPU and memory for every container — fits **latency-critical workloads** that cannot tolerate throttle-induced stalls or early eviction. You give up CPU burst headroom in exchange for predictable, protected behavior.

Most applications do not need Guaranteed. Right-sized Burstable is the practical default.

## What both teams actually want

Developers want **predictable performance**, **HPA that fires when it should**, and **visibility** into slowdowns that never appear in application logs.

Platform engineers want **scheduling that mirrors reality**, **fair eviction under pressure**, and quotas that enforce real baselines instead of 10m placeholder games.

The shared playbook: treat CPU and memory requests as service-level inputs to the scheduler and HPA; treat limits as observable budgets with kernel meaning; use **P95 Prometheus data** to set both; and use ResourceQuota as governance, not an arbitrary gate.

When both sides anchor on the same time series, the conversation stops being **"you are blocking my deploy"** versus **"you are lying to the scheduler"** and becomes **"we are both reading the same Prometheus data."**

## Wrap up

Requests schedule pods, determine QoS class, and shape eviction priority. Limits enforce CPU via CFS and cap memory before OOM. The two failure modes — too low and too high — affect developers and platform engineers simultaneously even when only one team feels the pain. P95 right-sizing, with the 2× CPU limit rule and memory buffers, is the shared contract that makes both scheduling and autoscaling predictable. **HPA is the tie-breaker: accurate requests make autoscaling trustworthy; wrong requests make both teams pay at once.**

## Try it in the lab

**Module 3 — "The Zero Request Myth"** in the workshop includes a hands-on **throttling simulator** and a **right-sizer script** that queries Prometheus for P95 data.

Workshop operators can clone the guide at [https://github.com/tosin2013/capacity-planning-lab-guide](https://github.com/tosin2013/capacity-planning-lab-guide) and work through Module 3.

Anyone who wants a hosted environment can use **Red Hat Demo Platform (RHDP)** at [https://rhdp.redhat.com](https://rhdp.redhat.com), where the full workshop runs on real OpenShift clusters with pre-deployed sample apps. You can reproduce the **56% CPU degradation** and the **HPA flapping scenarios** hands-on.

## Learn more

- [Kubernetes resource management for pods and containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [OpenShift resource quotas documentation](https://docs.openshift.com/container-platform/latest/nodes/clusters/nodes-cluster-resource-quotas.html)
- [Horizontal Pod Autoscaling — Kubernetes documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Prometheus querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

## SEO metadata

| Field | Value |
|-------|-------|
| **Meta title** (52 chars) | Kubernetes requests & limits: why both teams are right |
| **Meta description** (152 chars) | Requests schedule pods and drive HPA; limits throttle CPU and trigger OOM. Learn QoS, P95 right-sizing, and hands-on OpenShift lab exercises. |
| **URL slug** | `kubernetes-requests-limits-openshift-right-sizing` |
| **Primary keywords** | Kubernetes requests limits, OpenShift resource requests, container resource management |
| **Secondary keywords** | QoS classes Kubernetes, CPU throttling OpenShift, right-sizing Kubernetes pods, HPA resource requests |

## Pre-submission checklist

- [x] Headline is clear and includes primary keywords (Kubernetes, requests, limits)
- [x] Introduction answers "what's in it for me?" for both audiences (developer slowdowns + platform evictions)
- [x] All headings use sentence case
- [x] Code formatted as fenced code block (HPA formula)
- [x] Product names correct: Kubernetes, OpenShift, Prometheus, HPA (spelled out on first use), QoS (spelled out), CFS (spelled out), RHDP (spelled out), ResourceQuota (correct capitalization)
- [x] No marketing jargon
- [x] Active voice throughout
- [x] Clear call to action with full https:// URLs (GitHub + rhdp.redhat.com)
- [x] Empathetic to both developer and platform engineer perspectives
- [x] Memory formula footnoted: small-value minimum floor explained inline
- [x] Three HPA scenarios concrete with real numbers from lab
- [x] Word count appropriate for explainer type (800–1,300 words)
- [x] SEO elements present
- [ ] SME or peer review: pending
- [ ] All links verified as live: pending (editor to confirm before publish)
- [ ] On-page H1 title to be confirmed in CMS (matches meta title)
