// deck.js — Strategic Capacity Planning & Forecasting for OpenShift at Scale
// Red Hat-branded workshop overview deck (23 slides, 30-45 min talk)
//
// Build:  export NODE_PATH=$(npm root -g) && node deck.js

"use strict";

const H = require("./deck-helpers.js");
const {
  COLOR, FONT, W, ASSETS,
  newDeck, addFooter, addContentTitle, addBullets, addTwoColBullets,
  addStatusTable, addCaption, addCodeSlide, addDiagramSlide, addSectionDivider, addNotes,
} = H;

const OUT = "./capacity-planning-workshop-r01.0.pptx";
const REV = "r01.0";

const pres = newDeck();
let pageNum = 0;

function S() {
  const s = pres.addSlide(); pageNum += 1; addFooter(s, pageNum); return s;
}
function divider(code, title, subtitle, notes) {
  const s = pres.addSlide(); pageNum += 1; addSectionDivider(s, code, title, subtitle); addNotes(s, notes);
}


// ============================================================================
// SLIDE 1 — Cover
// ============================================================================
{
  const s = pres.addSlide();
  pageNum += 1;
  s.background = { color: COLOR.white };
  try { s.addImage({ path: `${ASSETS}/cover-panel.png`, x: 0, y: 0, w: W, h: 7.5 }); } catch (e) {}
  s.addText("WORKSHOP OVERVIEW", { x: 6.00, y: 1.98, w: 6.90, h: 0.34,
    fontFace: FONT.title, fontSize: 14, bold: true, color: COLOR.red, charSpacing: 6, align: "left", valign: "middle" });
  s.addText([
    { text: "Strategic Capacity Planning &", options: { breakLine: true } },
    { text: "Forecasting for OpenShift at Scale" }
  ], {
    x: 5.95, y: 2.42, w: 6.95, h: 2.00,
    fontFace: FONT.title, fontSize: 38, bold: true, color: COLOR.ink, align: "left", valign: "top" });
  s.addText("Tosin Akinosho — Red Hat", { x: 6.00, y: 5.10, w: 6.70, h: 0.90,
    fontFace: FONT.body, fontSize: 18, italic: true, color: COLOR.caption, align: "left", valign: "top" });
  s.addText(REV, { x: 11.85, y: 5.85, w: 0.95, h: 0.30,
    fontFace: FONT.mono, fontSize: 11, color: COLOR.caption, align: "right", valign: "middle" });
  try { s.addImage({ path: `${ASSETS}/logo-candidate-2.png`, x: 11.10, y: 6.80, w: 1.55, h: 0.37 }); } catch (e) {}
  addNotes(s, "Welcome everyone. I'm Tosin Akinosho from Red Hat, and today I'm walking you through a full-day, hands-on workshop on strategic capacity planning for OpenShift at scale. This workshop takes platform engineering and development teams from reactive firefighting to predictive, data-driven capacity management. Every exercise runs on live OpenShift clusters with real Prometheus data — not slides. By the end of this talk you'll understand what the workshop covers, why it matters, and what your team walks away with after one day.");
}


// ============================================================================
// SLIDE 2 — The Hook: The Cost of Not Planning
// ============================================================================
{
  const s = S();
  addContentTitle(s, "THE PROBLEM", "The Cost of Not Planning");
  addBullets(s, [
    "“Our cluster is at 90% capacity!” — but actual CPU usage is 7.6%",
    "$18,000/month wasted on a $50,000/month cluster from inaccurate resource requests",
    "80% of infrastructure spend disappears in the gap between allocated and consumed",
    "Black Friday: 10x traffic spike + AZ failure — and no capacity plan to fall back on",
    "Most platform teams are at Level 1-2 maturity: reactive firefighting, not data-driven forecasting",
  ]);
  addNotes(s, "Let me start with the pain. Most platform teams cannot answer a simple question: how much capacity do we actually need? They know their clusters feel full, but when you measure actual CPU consumption it is often under 10 percent. The gap between what developers request and what workloads actually consume is where millions of dollars disappear. That 18,000 dollar monthly figure comes from a real cluster audit exercise in the first module of this workshop. This is not theoretical — it is measured, reproducible waste. And the Black Friday scenario is not hypothetical either: we simulate it in Module 7 with real kube-burner load and real node failures. Without a capacity plan, when the incident happens, you are guessing.");
}


// ============================================================================
// SLIDE 3 — Workshop At a Glance (two-column)
// ============================================================================
{
  const s = S();
  addContentTitle(s, "WORKSHOP OVERVIEW", "Full-Day, Hands-On, Role-Based");
  addTwoColBullets(s,
    [
      "8 hours, 9 modules, progressive skill building",
      "40+ code blocks, 6 scripts, 14 YAML manifests",
      "Developer track + Infrastructure track",
      "Black Friday Chaos Game (live simulation)",
      "Executive pitch exercise (translate metrics to business)",
    ],
    [
      "OpenShift 4.14–4.21+ on live clusters",
      "RHACM 2.14+ multi-cluster observability",
      "Prometheus / Thanos / Grafana stack",
      "Each student gets a dedicated SNO cluster",
      "Optional: AI-assisted ops with OpenShift Lightspeed",
    ]);
  addNotes(s, "Let me frame the scope. This is not a lecture — it is a working lab. Every student gets their own OpenShift cluster and runs every command themselves. The workshop is structured in two tracks — developer and infrastructure — that converge in Module 4 when ops and dev sit together at the same dashboard. The Black Friday Chaos Game in Module 7 is the integration test: everything you learned in Modules 1 through 6 gets applied under simulated production pressure with a five thousand dollar budget constraint. Module 9 on AI-assisted ops with Lightspeed is optional and covers Granite versus Qwen3 model comparison. The key takeaway: this is 8 hours of practiced skill, not awareness training.");
}


// ============================================================================
// SLIDE 4 — Target Audience
// ============================================================================
{
  const s = S();
  addContentTitle(s, "WHO IS THIS FOR", "Five Roles, One Workshop");
  addBullets(s, [
    "Platform Engineers & SREs — fleet-wide forecasting, node density, custom RHACM dashboards",
    "Application Developers — Kubernetes scheduler, QoS classes, why accurate requests matter",
    "Architects — split-vs-grow decisions, etcd constraints, 10K pod ceiling",
    "FinOps Practitioners — cloud spend visibility, chargeback modeling, commitment strategies",
    "Engineering Managers — translating technical metrics into executive roadmaps and budget asks",
  ]);
  addNotes(s, "The workshop is explicitly multi-role. Platform engineers and SREs get the deepest technical value from Modules 5 and 6 on fleet architecture and RHACM observability. Developers benefit most from Modules 3 and 4 on the Zero Request Myth and the right-sizing activity. FinOps practitioners and managers get the most from Module 8 on the 12-month strategic roadmap and executive pitch. Everyone participates in Module 7, the Black Friday simulation, together. The design philosophy is that capacity planning is a team sport — ops cannot right-size without developer input, and developers cannot set accurate requests without understanding the scheduler.");
}


// ============================================================================
// SLIDE 5 — Section Divider: Foundations
// ============================================================================
divider("01", "Foundations",
  "Where are you today, and where are you going?",
  "The first two modules establish the analytical foundation. Module 1 teaches you to audit your current state — allocation versus consumption. Module 2 introduces Pod Velocity, a forecasting model that is more predictive than linear CPU trending for microservices architectures. Without these baselines, everything else is guesswork.");


// ============================================================================
// SLIDE 6 — Module 1: The 90-Day Audit
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 1 · THE PLANNING HORIZON", "The 90-Day Audit: Know Where You Are");
  addBullets(s, [
    "Three planning horizons: Tactical (0–3 mo), Operational (3–12 mo), Strategic (1–3 yr)",
    "Audit cluster capacity: allocatable vs requested vs consumed",
    "The “waste zone”: 43% allocated, 7.6% consumed — 36% zombie allocation",
    "Financial translation: $50K/month cluster, $18K/month wasted",
    "Maps to the FinOps lifecycle: Inform, Optimize, Operate",
    "Outcome: a quantified baseline that justifies every subsequent decision",
  ]);
  addNotes(s, "Module 1 is the know-thyself module. Students run oc adm top nodes and compare what the scheduler thinks is allocated against what is actually being consumed. The typical finding is dramatic: 40 to 45 percent of CPU is reserved by resource requests, but only 7 to 8 percent is actually used. The rest is zombie allocation — reserved but never consumed. On a 50,000 dollar per month cluster that translates to roughly 18,000 dollars per month in waste. This single number — the waste zone — is what gets executive attention and funds the rest of the capacity planning program. Students walk out of this module with a concrete, defensible baseline they can reproduce on any cluster in 30 minutes using the scripts we provide.");
}


// ============================================================================
// SLIDE 7 — Module 2: Pod Velocity
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 2 · MATHEMATICS OF FORECASTING", "Pod Velocity: A Better Forecasting Model");
  addBullets(s, [
    "Linear CPU trending fails for microservices — bursts, not gradual growth",
    "Pod Velocity = rate of pod creation over time (deployments/day, not CPU %)",
    "Formula: Quarterly Nodes = (Velocity × Avg Replicas × Avg CPU) / Node CPU",
    { text: "Example: 50 services/qtr × 3 replicas × 200m = 30 cores = 4 new nodes", options: { indentLevel: 1 } },
    "Students run a script that queries Prometheus API directly — no browser UI needed",
    "Build a centralized RHACM Grafana dashboard for fleet-wide forecasting",
  ]);
  addNotes(s, "This is where the workshop gets quantitative. Linear extrapolation — CPU grew 5 percent last month, so in 12 months we need 60 percent more — breaks completely for microservices because growth comes in bursts when new services deploy, not as gradual CPU creep. Pod Velocity tracks deployment cadence instead: how many new pods are being created per unit time. Combined with average replica count and average CPU request per container, this gives a much more accurate quarterly node forecast. Students run a shell script that discovers Prometheus automatically, mints an auth token, runs four PromQL queries for velocity, deployment count, average CPU and memory, and prints a forecasting table. Then they build a three-panel Grafana dashboard on RHACM that shows Pod Velocity, Projected Nodes, and Pod Count across the fleet.");
}


// ============================================================================
// SLIDE 8 — Section Divider: Developer Track
// ============================================================================
divider("02", "The Developer Track",
  "Why “zero requests” kills your production pods",
  "Modules 3 and 4 are developer-focused. They prove, through live debugging, why setting accurate resource requests is not bureaucratic overhead but a contract with the scheduler. Without it, pods get evicted first under memory pressure, CPU gets throttled silently, and autoscaling cannot function. These modules changed more minds about resource requests than any policy document ever did.");


// ============================================================================
// SLIDE 9 — Module 3: The Zero Request Myth (two-column)
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 3 · DEVELOPER TRACK", "The “Zero Request” Myth");
  addTwoColBullets(s,
    [
      { text: "What Developers Think", options: { bold: true, bullet: false } },
      "“Resource requests are just bureaucracy”",
      "“My app works fine without limits”",
      "“I’ll set them later when we go to prod”",
      "“Just give me a big node”",
    ],
    [
      { text: "What Actually Happens", options: { bold: true, bullet: false } },
      "BestEffort QoS — first pod killed under pressure",
      "OOMKilled (exit code 137) under load",
      "CPU throttled silently — P99 latency spikes",
      "HPA cannot scale without a CPU target",
    ]);
  addNotes(s, "This is the myth-busting module. Many developers genuinely believe that resource requests and limits are optional overhead imposed by the platform team. Module 3 proves them wrong through live debugging. Students deploy a pod without requests and watch it get OOMKilled under load. They observe CPU throttling with Prometheus metrics showing throttled_seconds climbing while the app appears fine from the outside. They learn the three QoS classes: Guaranteed where requests equal limits and the pod is last to be evicted, Burstable with requests lower than limits, and BestEffort with no requests at all, first to die. The key insight: Kubernetes uses resource requests for scheduling AND for eviction priority. Without them, your pod is invisible to the scheduler and first in line for termination.");
}


// ============================================================================
// SLIDE 10 — Module 4: Ops Meets Dev
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 4 · THE RIGHT-SIZING ACTIVITY", "Ops Meets Dev: Same Dashboard, Different Hats");
  addBullets(s, [
    "Role-play exercise: switch between Ops Hat and Dev Hat",
    "The checkout-api scenario: 500m CPU requested, 10–30m actually used (94–98% waste)",
    "Memory limit set at 64Mi but process needs 80–120Mi — OOMKill risk under load",
    "A single mis-sized deployment locks up 4% of cluster CPU capacity",
    "Fix verification through live Grafana dashboard feedback",
    "The dashboard is the shared language between ops and dev",
  ]);
  addNotes(s, "This module is where the developer and infrastructure tracks converge. It uses a deliberately broken deployment — the checkout-api in a right-sizing-lab namespace — that has two common mistakes: a CPU request that is 15 to 20 times higher than actual usage, and a memory limit that is too low for the actual process. Students wear the ops hat to find the problem using Grafana dashboards and Prometheus queries, then switch to the dev hat to understand the code, determine correct resource values using P95 historical data from the resource-right-sizer script, and apply the fix. The key pedagogical point: when ops says your service is wasting CPU and dev says my service is barely using anything, they are both right. The dashboard provides a shared factual basis for the conversation. Module 3 taught mechanics; Module 4 teaches workflow.");
}


// ============================================================================
// SLIDE 11 — Section Divider: Infrastructure Track
// ============================================================================
divider("03", "The Infrastructure Track",
  "Fleet architecture, density math, and multi-cluster observability",
  "Modules 5 and 6 are the infrastructure engineer depth modules. They cover the hard constraints that determine when you need more nodes, when you need to split clusters, and how to observe capacity across a multi-cluster fleet with RHACM. This is where platform engineers learn the math behind the decisions they make every quarter.");


// ============================================================================
// SLIDE 12 — Module 5: Fleet Architecture & Density Math
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 5 · FLEET ARCHITECTURE & SIZING", "The Hard Limits: maxPods, etcd, and the 10K Pod Ceiling");
  addBullets(s, [
    "Default maxPods: 250/node — surprisingly easy to hit (100 services × 3 replicas = 300 pods)",
    "Density formula: min workers = ceil((total pods / maxPods) × redundancy factor)",
    "Tunable to 500+ pods/node, but each pod adds ~10 MB of kubelet/CNI/cgroup overhead",
    "etcd database hard limit: 8 GB — beyond this, API latency goes from 300 ms to 3000 ms",
    "OpenShift supported maximums: 500 worker nodes, 10,000 total pods, 120K etcd objects",
    "The split-vs-grow decision: when do you add a cluster instead of adding nodes?",
  ]);
  addNotes(s, "This module tackles the physical constraints that are invisible at small scale but become dominating factors as clusters grow. The maxPods limit of 250 by default controls how many pods a single node can host. Each pod consumes memory beyond its container requests — kubelet tracking, CNI state, cgroup structures — roughly 10 megabytes overhead per pod. At 250 pods on a 32 GB node, that is 2.5 gigabytes of overhead; at 500 pods it is 5 gigabytes. Students tune kubeletConfig to increase density and measure the actual memory impact and API response time degradation. The etcd 8 gigabyte hard limit is critical: once the database reaches 8 GB, the cluster enters a degraded state. A single CrashLoopBackOff pod can generate over 8000 events per day. Students work through the split-versus-grow decision tree with real constraints.");
}


// ============================================================================
// SLIDE 13 — Observability Architecture Diagram
// ============================================================================
{
  const s = S();
  addDiagramSlide(s, "MODULE 6 · FLEET OBSERVABILITY",
    "RHACM Multi-Cluster Observability Architecture",
    "r01-rhacm-observability-architecture",
    "Prometheus (managed clusters) → metrics-collector → Thanos (hub) → Grafana (hub)");
  addNotes(s, "Module 6 builds fleet-wide observability using RHACM. The architecture is straightforward: each managed cluster runs Prometheus for local metric collection and a metrics-collector sidecar that forwards a configurable subset of metrics to the hub cluster’s Thanos instance. Thanos provides long-term storage — 30 plus days versus Prometheus’s 15-day default — and cross-cluster PromQL queries. Grafana on the hub cluster visualizes the aggregated data. The critical optimization is the metric allowlist: by default, RHACM forwards all metrics which can be 500,000 or more time series per cluster, but a properly configured allowlist reduces this by 95 percent, cutting Thanos storage costs dramatically while maintaining full capacity visibility. Students build a seven-panel custom Grafana dashboard that aggregates capacity metrics across all their student clusters.");
}


// ============================================================================
// SLIDE 14 — Code Slide: Metric Allowlist
// ============================================================================
{
  const s = S();
  addCodeSlide(s, "MODULE 6 · METRIC ALLOWLISTS",
    "Custom Metric Allowlist for Capacity Planning",
    "yaml · ConfigMap",
    [
      "# observability-metrics-custom-allowlist",
      "# Only forward capacity-relevant metrics to Thanos",
      "kind: ConfigMap",
      "apiVersion: v1",
      "metadata:",
      "  name: observability-metrics-custom-allowlist",
      "  namespace: open-cluster-management-observability",
      "data:",
      "  metrics_list.yaml: |",
      "    names:",
      "      - kube_pod_container_resource_requests",
      "      - kube_pod_container_resource_limits",
      "      - kube_node_status_allocatable",
      "      - node_memory_MemAvailable_bytes",
      "      - container_cpu_usage_seconds_total",
      "      - kube_pod_start_time",
    ],
    "A curated allowlist reduces metric forwarding by 95%, saving gigabytes of Thanos storage per cluster.");
  addNotes(s, "This is one of the most impactful operational optimizations in the workshop. By default, each managed cluster forwards hundreds of thousands of time series to the hub. For a fleet of 20 clusters, that is millions of time series and terabytes of Thanos storage per month. A curated allowlist that forwards only the metrics relevant to capacity planning — resource requests, limits, allocatable capacity, actual usage, and pod velocity — reduces forwarded volume by roughly 95 percent. Students create this ConfigMap and apply it to their cluster, then observe the reduction in Thanos. The six metrics listed here, plus a few more for etcd and node conditions, give you full capacity planning visibility across the fleet. This is the slide to screenshot if you only remember one thing from Module 6.");
}


// ============================================================================
// SLIDE 15 — Section Divider: Integration & Strategy
// ============================================================================
divider("04", "Integration & Strategy",
  "Apply everything under pressure, then build the 12-month plan",
  "The final section of the workshop is where everything comes together. Module 7 is a live simulation — the Black Friday Chaos Game — that tests capacity planning skills under realistic production pressure. Module 8 translates all the technical work into a 12-month strategic roadmap and an executive pitch. This is where the workshop goes from skills to strategy.");


// ============================================================================
// SLIDE 16 — Module 7: The Black Friday Chaos Game
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 7 · THE INTEGRATION CHALLENGE", "Black Friday + AZ Outage: 60 Minutes of Controlled Chaos");
  addBullets(s, [
    "Scenario: 10x traffic spike + AWS AZ failure, 30% worker nodes unreachable",
    "4 waves of escalating chaos: traffic ramp, node loss, etcd pressure, cascade",
    "$5,000 budget constraint — every node costs $200/hour",
    "Success criteria: >95% request success rate for 60 minutes",
    "Team-based: platform team vs application team perspectives",
    "Every decision has trade-offs: scale up vs throttle vs failover vs emergency nodes",
  ]);
  addNotes(s, "This is the workshop’s integration test, and it is the module students remember most. The scenario: it is Black Friday, traffic is about to jump from 10K to 100K requests per second, and then AWS reports degraded performance in your primary availability zone and 30 percent of worker nodes go unreachable. Students use kube-burner to generate realistic load, scripts to simulate node failures via cordon and drain, and they must make real-time decisions about scaling, throttling, and failover — all within a simulated 5,000 dollar budget. The facilitator injects chaos in 4 waves at 15-minute intervals. Wave 1 is traffic, Wave 2 is node failures, Wave 3 adds etcd pressure from rapid deployment churn, and Wave 4 is cascade recovery. This module proves that capacity planning is not academic: without a plan, when the incident happens you are guessing. With a plan, you have decision criteria already established.");
}


// ============================================================================
// SLIDE 17 — Module 8: From Metrics to Executive Strategy (two-column)
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 8 · STRATEGIC ROADMAPPING", "From Metrics to Executive Strategy");
  addTwoColBullets(s,
    [
      { text: "Technical Metrics", options: { bold: true, bullet: false } },
      "Pod Velocity: +50 services/quarter",
      "CPU: 42% allocated, 12% used",
      "etcd at 3.8 GB / 8 GB limit",
      "HPA scaled to max during Black Friday",
      "Avg CPU request: 200m per pod",
    ],
    [
      { text: "Executive Translation", options: { bold: true, bullet: false } },
      "150% service growth/year — can we scale?",
      "$18K/month waste — where to cut?",
      "Cluster at 48% max — when to split?",
      "Emergency capacity: $800/hour",
      "Unit economics: cost per service",
    ]);
  addNotes(s, "Module 8 is where platform engineers become strategic advisors. The translation framework is the core tool: every technical metric maps to a business question that executives care about. Pod Velocity becomes growth rate. CPU waste becomes cost savings opportunity. The etcd percentage becomes the timeline for when we need to split the cluster and what it costs. Students run a capacity-roadmap-generator script that queries live Prometheus data and produces a filled-in 12-month roadmap with five sections: current state baseline, growth forecast using Pod Velocity, risk analysis with dollar quantification, quarterly milestones with specific actions, and a budget forecast with Reserved Instance recommendations. Then they deliver a 3-minute executive pitch to their peers. The golden rule of executive communication: lead with the recommendation, then justify with data.");
}


// ============================================================================
// SLIDE 18 — Hub-Student Topology Diagram
// ============================================================================
{
  const s = S();
  addDiagramSlide(s, "LAB ENVIRONMENT",
    "Hub-Student Workshop Topology",
    "r02-hub-student-topology",
    "Each student gets a dedicated 3-node compact cluster; RHACM + Grafana + Showroom run on the hub.");
  addNotes(s, "The lab environment uses a hub-student topology deployed on AWS via AgnosticD. The hub cluster runs RHACM with multi-cluster observability, Grafana with the capacity dashboards students build during the workshop, and the Showroom lab guide interface. Each student gets a dedicated 3-node compact OpenShift cluster — m7a.2xlarge instances with 8 vCPU and 32 GB RAM each — with sample workloads pre-deployed via ArgoCD. Students SSH from the Showroom terminal on the hub to their student cluster bastion, and all oc commands throughout the workshop run on their own cluster. Module 6 brings it all together when student clusters are imported into RHACM and their metrics start flowing to the hub Grafana. The architecture supports up to 20 students with appropriate AWS quota increases.");
}


// ============================================================================
// SLIDE 19 — Module 9: AI-Assisted Operations
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 9 · AI-ASSISTED CAPACITY OPERATIONS", "OpenShift Lightspeed as a Capacity Planning Co-Pilot");
  addBullets(s, [
    "OpenShift Lightspeed: AI assistant embedded in the OCP web console",
    "RAG-powered: grounded in OCP documentation, not generic Kubernetes theory",
    "Developer queries: debug OOMKills, write HPA configs, explain QoS classes",
    "Infra queries: reason about node density, etcd limits, split-vs-grow decisions",
    "Forecasting: write PromQL queries, estimate capacity runway, translate to executive language",
    "Model comparison: IBM Granite 3.2 8B vs Qwen3 14B — same question, different strengths",
  ]);
  addCaption(s, "Optional module — requires OpenShift Lightspeed installed on the student cluster.");
  addNotes(s, "Module 9 is optional and requires OpenShift Lightspeed to be installed on the student cluster with the MCP server sidecar for live cluster introspection. It demonstrates how an AI assistant can operationalize everything from Modules 1 through 8. Students query Lightspeed as a developer to debug resource sizing issues, as an infrastructure engineer to reason about density constraints, and as a forecasting co-pilot to write the PromQL queries they learned to read in Module 2. The model comparison lab has students ask the same capacity planning question to both Granite 3.2 and Qwen3 14B and evaluate the differences in reasoning depth, accuracy, and practical utility. The key boundary: Lightspeed is a conversational assistant, not an autonomous agent. It advises but does not execute. Always validate its PromQL in Prometheus before using it in production dashboards.");
}


// ============================================================================
// SLIDE 20 — Maturity Model (table)
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MATURITY MODEL", "Where Are You on the Capacity Planning Curve?");
  addStatusTable(s, [
    { code: "Level 1", name: "Reactive (Firefighting)", purpose: "No forecasting; add nodes when cluster is full; emergency purchase orders" },
    { code: "Level 2", name: "Tactical (Short-Term)", purpose: "Quarterly reviews; linear extrapolation; budget exists but is often wrong" },
    { code: "Level 3", name: "Operational (Data-Driven)", purpose: "Pod Velocity tracking; right-sized workloads; 12-month roadmap; RHACM fleet visibility" },
    { code: "Level 4", name: "Strategic (Predictive)", purpose: "Automated forecasting; capacity drives architecture; FinOps partnership; self-service dashboards" },
  ], { colW: [1.60, 3.20, 7.29], rowH: 0.60 });
  addCaption(s, "This workshop moves teams from Level 1–2 to Level 3 in one day. Level 4 takes 6–12 months of practice.");
  addNotes(s, "Most platform teams are at Level 1 or Level 2. They react to outages and add nodes when clusters are already full, or they do quarterly reviews based on linear extrapolation that breaks for microservices. This workshop gets teams to Level 3: monthly capacity reviews using Pod Velocity, right-sized workloads based on P95 Prometheus data, a 12-month roadmap with quarterly milestones, and fleet-wide visibility through RHACM observability. Level 4 — strategic, predictive capacity planning with automated forecasting integrated into the CI/CD pipeline — takes another 6 to 12 months of practice with the tools and processes introduced here. The path: start with one cluster, run the baseline audit from Module 1, build the Pod Velocity model from Module 2. That gives you 80 percent of the value.");
}


// ============================================================================
// SLIDE 21 — Section Divider: Key Takeaways
// ============================================================================
divider("05", "Key Takeaways",
  "What your team walks away with",
  "Let me wrap up with the concrete outcomes. After a full day with this workshop, every team member walks away with specific, actionable capabilities — not just awareness but practiced skills they applied on real OpenShift clusters with real Prometheus data. Let me be specific about what changes.");


// ============================================================================
// SLIDE 22 — What You Walk Away With
// ============================================================================
{
  const s = S();
  addContentTitle(s, "OUTCOMES", "After One Day, Your Team Can…");
  addBullets(s, [
    "Audit any OpenShift cluster’s capacity baseline in 30 minutes (Module 1)",
    "Forecast quarterly node requirements using Pod Velocity, not gut feel (Module 2)",
    "Right-size workloads using P95 Prometheus data — eliminating 30–40% waste (Modules 3–4)",
    "Make split-vs-grow decisions based on maxPods math and etcd constraints (Module 5)",
    "Build fleet-wide capacity dashboards with RHACM + Grafana (Module 6)",
    "Handle a capacity incident with data-driven decision criteria (Module 7)",
    "Present a 12-month capacity roadmap to leadership with cost justification (Module 8)",
  ]);
  addNotes(s, "Each bullet maps to a specific module and a specific, measurable capability. The baseline audit can be done on any OpenShift cluster in 30 minutes using the scripts from Module 1. The Pod Velocity model replaces guesswork with a formula that has been validated against real deployment patterns. The right-sizing exercises typically identify 30 to 40 percent waste from over-requested CPU alone. The split-versus-grow decision tree uses etcd size, maxPods count, and API latency as objective criteria. The RHACM dashboards are reusable and customizable. The incident playbook from Module 7 becomes part of your team’s operational documentation. And the roadmap from Module 8 has been tested in live executive presentations. This is not theory — it is practiced skill.");
}


// ============================================================================
// SLIDE 23 — Call to Action
// ============================================================================
{
  const s = S();
  addContentTitle(s, "GET STARTED", "Your First 90 Days");
  addBullets(s, [
    "Week 1: Run the 90-day baseline audit on your production clusters",
    "Week 2–4: Build the Pod Velocity dashboard in your RHACM Grafana",
    "Month 2: Right-size your top 20 most over-provisioned workloads",
    "Month 3: Complete a 12-month capacity roadmap and present to leadership",
    { text: "“Start small: one cluster, one audit, one dashboard. That is 80% of the value.”", options: { italic: true, bullet: false } },
    "Workshop materials: github.com/tosin2013/capacity-planning-lab-guide",
  ]);
  addNotes(s, "I want to leave you with concrete next steps. The 90-day plan is directly from Module 8. The most important message: do not try to boil the ocean. Start with one cluster, run the Module 1 baseline audit, and build the Module 2 Pod Velocity dashboard. That gives you the data foundation to justify everything else. The workshop materials are open source on GitHub and include all scripts, YAML manifests, and the full lab guide deployed via Antora. If your organization wants to run this as a facilitated workshop with dedicated clusters for each participant, reach out. Thank you for your time, and I am happy to take questions.");
}


// ============================================================================
// Build
// ============================================================================
const notesCount = pres.slides.reduce((n, sl) => n + (sl._slideObjects.some(o => o._type === "notes") ? 1 : 0), 0);
console.log(`Slides: ${pageNum}  |  Notes check: ${notesCount} slides have notes`);

pres.writeFile({ fileName: OUT })
  .then(p => console.log("WROTE", p))
  .catch(e => { console.error(e); process.exit(1); });
