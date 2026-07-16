// deck.js — Strategic Capacity Planning & Forecasting for OpenShift at Scale
//
// Build:  export NODE_PATH=$(npm root -g) && node deck.js

"use strict";

const H = require("./deck-helpers.js");
const {
  COLOR, FONT, W, ASSETS,
  newDeck, addFooter, addContentTitle, addBullets, addTwoColBullets,
  addStatusTable, addCaption, addPerfCallout, addDiagramSlide, addSectionDivider, addNotes,
} = H;

const OUT = "capacity-planning-workshop-r01.0.pptx";
const REV = "r01.0";

const pres = newDeck();
pres.title = "Strategic Capacity Planning & Forecasting for OpenShift at Scale";
pres.author = "Tosin Akinosho";
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
  s.addText("STRATEGIC WORKSHOP", { x: 6.00, y: 1.98, w: 6.90, h: 0.34,
    fontFace: FONT.title, fontSize: 14, bold: true, color: COLOR.red, charSpacing: 6, align: "left", valign: "middle" });
  s.addText([
    { text: "Strategic Capacity", options: { breakLine: true } },
    { text: "Planning & Forecasting" },
  ], {
    x: 5.95, y: 2.30, w: 6.95, h: 1.80, fontFace: FONT.title, fontSize: 38, bold: true, color: COLOR.ink, align: "left", valign: "top" });
  s.addText("for OpenShift at Scale", { x: 6.00, y: 4.10, w: 6.70, h: 0.50,
    fontFace: FONT.body, fontSize: 18, italic: true, color: COLOR.caption, align: "left", valign: "top" });
  s.addText("Tosin Akinosho  |  Red Hat", { x: 6.00, y: 4.70, w: 6.70, h: 0.40,
    fontFace: FONT.body, fontSize: 14, color: COLOR.caption, align: "left", valign: "middle" });
  s.addText(REV, { x: 11.85, y: 5.85, w: 0.95, h: 0.30, fontFace: FONT.mono, fontSize: 11, color: COLOR.caption, align: "right", valign: "middle" });
  try { s.addImage({ path: `${ASSETS}/logo-candidate-2.png`, x: 11.10, y: 6.80, w: 1.55, h: 0.37 }); } catch (e) {}
  addNotes(s, "Welcome to the Strategic Capacity Planning and Forecasting workshop. Today we transition from reactive firefighting to predictive, data-driven capacity management using OpenShift and Red Hat Advanced Cluster Management. This is a full-day, hands-on session — every module produces a concrete deliverable you can take back to your organization. My name is Tosin Akinosho and I will be your guide for the day.");
}

// ============================================================================
// SLIDE 2 — The Problem
// ============================================================================
{
  const s = S();
  addContentTitle(s, "THE CHALLENGE", "Why Reactive Capacity Management Fails");
  addBullets(s, [
    "Teams overprovision \"just in case\" — locking up 30–40% of infrastructure spend on unused capacity.",
    "New service deployments spike unpredictably — linear CPU trending misses the real growth driver.",
    "Developers and platform engineers speak different languages — requests vs utilization, QoS vs cost.",
    "Without baselines, every scaling decision is a guess — and guesses get expensive at scale.",
  ], { fontSize: 17 });
  addNotes(s, "Most organizations approach capacity planning reactively. A deployment fails, nodes run out of memory, or an executive asks 'why is our cloud bill so high?' The root cause is always the same: teams lack baselines, forecasting models, and shared dashboards that bridge the gap between ops and dev. We overprovision because we cannot predict, and we cannot predict because we do not measure. Today we fix that.");
}

// ============================================================================
// SLIDE 3 — The Waste Gap
// ============================================================================
{
  const s = S();
  addContentTitle(s, "THE COST OF IGNORANCE", "The Allocation-vs-Consumption Gap");
  addStatusTable(s, [
    { code: "42% CPU",  name: "Allocated",     purpose: "What Kubernetes reserves based on developer requests." },
    { code: "7.6% CPU", name: "Actually Used",  purpose: "What the hardware physically consumes under load." },
    { code: "34% gap",  name: "Wasted",         purpose: "Idle capacity that blocks scheduling but does no work." },
    { code: "$50K/mo",  name: "Monthly Spend",   purpose: "Total infrastructure cost across 3 clusters, 24 nodes." },
    { code: "$18K/mo",  name: "Waste Cost",      purpose: "83.7 unused cores at $206/core/month — money on fire." },
  ], { colW: [3.00, 3.00, 6.09], withCallout: true });
  addPerfCallout(s, "If your clusters show similar ratios, this workshop pays for itself in the first quarter.");
  addNotes(s, "Here is a real baseline from a 3-cluster OpenShift environment: 24 worker nodes, 243 allocatable cores. Developers requested 42% of capacity but the hardware only consumed 7.6%. That gap — 83.7 cores of reserved-but-unused CPU — costs roughly $18,000 every month. Multiply by a year and you are burning over $200,000 on capacity that does nothing. The first step to fixing this is knowing it exists. Module 1 teaches you how to run this audit on your own clusters.");
}

// ============================================================================
// SLIDE 4 — Who Is This For
// ============================================================================
{
  const s = S();
  addContentTitle(s, "AUDIENCE TRACKS", "Who Will Benefit Most");
  addBullets(s, [
    { text: "Platform Engineers & SREs", options: { bullet: false, bold: true } },
    { text: "Fleet-wide forecasting, node density optimization, and custom RHACM observability dashboards.", sub: true },
    { text: "Application Developers & Architects", options: { bullet: false, bold: true } },
    { text: "The Kubernetes scheduler, QoS classes, and why accurate resource requests matter for stability.", sub: true },
    { text: "FinOps & Product Owners", options: { bullet: false, bold: true } },
    { text: "Cloud spend visibility, chargeback modeling, and the financial impact of commitment strategies.", sub: true },
  ], { fontSize: 16 });
  addNotes(s, "This workshop serves three audiences deliberately. Platform engineers and SREs will learn fleet-wide forecasting using Pod Velocity models, node density mathematics, and how to build custom RHACM dashboards. Application developers will understand why resource requests are essential for stability — not just administrative overhead. FinOps and product owners gain visibility into the financial impact of capacity decisions. The Grafana dashboard becomes the shared language that bridges all three perspectives.");
}

// ============================================================================
// SLIDE 5 — Learning Objectives
// ============================================================================
{
  const s = S();
  addContentTitle(s, "OUTCOMES", "What You Will Be Able to Do");
  addBullets(s, [
    "Establish a capacity baseline using a 90-day audit of allocation vs consumption.",
    "Forecast quarterly node requirements using the Pod Velocity model.",
    "Right-size workloads by diagnosing QoS classes, CPU throttling, and OOMKill events.",
    "Build centralized multi-cluster dashboards with RHACM Observability and Thanos.",
    "Make real-time capacity decisions under pressure in a simulated Black Friday scenario.",
    "Present a 12-month capacity roadmap to executive leadership.",
  ], { fontSize: 16 });
  addNotes(s, "By end of day, you will have performed a baseline audit, used Pod Velocity to forecast growth, right-sized a misconfigured deployment, built fleet-wide dashboards, survived a simulated Black Friday, and prepared a strategic capacity roadmap. These are not theoretical exercises — each module produces a concrete deliverable you take home and apply to your production clusters starting next week.");
}

// ============================================================================
// SLIDE 6 — Technology Stack
// ============================================================================
{
  const s = S();
  addContentTitle(s, "TECHNOLOGY", "The Platform Stack");
  addStatusTable(s, [
    { code: "OCP 4.21+",   name: "OpenShift",            purpose: "Container platform with scheduler, kubelet, etcd." },
    { code: "RHACM 2.16+", name: "Advanced Cluster Mgmt", purpose: "Multi-cluster lifecycle, policy, and import." },
    { code: "Prometheus",   name: "Metrics Collection",    purpose: "Per-cluster scraping of pod and node metrics." },
    { code: "Thanos",       name: "Long-term Storage",     purpose: "Hub-side metric aggregation and cross-cluster query." },
    { code: "Grafana",      name: "Dashboards",            purpose: "Capacity visualization across the fleet." },
    { code: "Alertmanager", name: "Alerting",              purpose: "Threshold-based capacity and runway alerts." },
    { code: "ArgoCD",       name: "GitOps Delivery",       purpose: "Sample workload deployment via OpenShift GitOps." },
    { code: "Lightspeed",   name: "AI Assistant",          purpose: "Optional: AI-assisted PromQL and capacity queries." },
  ], { colW: [2.80, 3.40, 5.89], rowH: 0.42 });
  addNotes(s, "Our stack is OpenShift 4.21 with RHACM 2.16 for multi-cluster management. Prometheus scrapes metrics on every managed cluster. The RHACM metrics-collector forwards selected metrics to Thanos on the hub, where Grafana renders capacity dashboards across the entire fleet. Alertmanager provides threshold-based alerts for capacity warnings. ArgoCD deploys the sample workloads we use in labs. Module 9 optionally introduces OpenShift Lightspeed with IBM Granite and Qwen3 models for AI-assisted PromQL authoring and capacity reasoning.");
}

// ============================================================================
// SLIDE 7 — Section Divider: Architecture
// ============================================================================
divider("01", "Architecture & Environment",
  "Hub-student topology and the observability pipeline.",
  "Let us look at the workshop environment. Every student gets a dedicated 3-node compact OpenShift cluster. A central hub cluster runs RHACM with Observability, which pulls metrics from all student clusters into Thanos for centralized Grafana dashboards. This is the same architecture pattern used in production multi-cluster environments.");

// ============================================================================
// SLIDE 8 — Diagram: Hub-Student Architecture
// ============================================================================
{
  const s = S();
  addDiagramSlide(s, "ARCHITECTURE", "Hub-Student Workshop Topology",
    "r01-hub-student-architecture",
    "Each student cluster is a 3-node compact OCP 4.21 managed by RHACM on the hub.");
  addNotes(s, "The hub cluster hosts RHACM with Observability — Thanos for long-term metric storage and Grafana for dashboards. Each student gets a dedicated 3-node compact cluster with full cluster-admin access running on AWS m7a.2xlarge instances: 8 vCPU and 32 GB memory per node. The metrics-collector on each managed cluster pushes selected Prometheus metrics to Thanos on the hub. In Module 6, you will import your student cluster into RHACM and watch metrics flow into the hub dashboards in real time.");
}

// ============================================================================
// SLIDE 9 — Diagram: Observability Data Flow
// ============================================================================
{
  const s = S();
  addDiagramSlide(s, "OBSERVABILITY", "Metrics Pipeline: Cluster to Dashboard",
    "r02-observability-data-flow",
    "Prometheus scrapes locally; metrics-collector pushes to Thanos on the hub; Grafana queries Thanos.");
  addNotes(s, "Here is the data flow in detail. Prometheus on each managed cluster scrapes pod and node metrics at the standard 30-second interval. The metrics-collector sidecar filters these to a configurable allowlist — reducing forwarded data by up to 95% — and pushes them over HTTPS to the Thanos receive endpoint on the hub. Thanos stores the data in S3-compatible object storage with configurable retention. Grafana on the hub queries Thanos using PromQL, giving you a single pane of glass across the entire fleet. Alertmanager watches the same Thanos data for capacity threshold breaches.");
}

// ============================================================================
// SLIDE 10 — Section Divider: Agenda
// ============================================================================
divider("02", "Workshop Agenda",
  "Full-day schedule with hands-on labs in every module.",
  "Here is our full-day agenda. We have nine modules covering foundations through strategy, with hands-on labs in every one. The modules build on each other: baselines first, then forecasting, then right-sizing, then fleet architecture, then observability, then the integration challenge that tests everything, and finally the strategic roadmap. Module 9 on AI-assisted ops is optional and depends on Lightspeed availability.");

// ============================================================================
// SLIDE 11 — Schedule Table
// ============================================================================
{
  const s = S();
  addContentTitle(s, "SCHEDULE", "Full-Day Workshop Timeline");
  addStatusTable(s, [
    { code: "09:00", name: "Module 1: Planning Horizons",    purpose: "90-day audit, allocation vs consumption gap. (60 min)" },
    { code: "10:00", name: "Module 2: Forecasting Math",     purpose: "Pod Velocity model, PromQL, ACM dashboards. (60 min)" },
    { code: "11:15", name: "Module 3: Developer Track",      purpose: "QoS classes, CPU throttling, right-sizing, HPA. (90 min)" },
    { code: "12:45", name: "Lunch Break",                    purpose: "(60 min)" },
    { code: "13:45", name: "Module 4: Right-Sizing Activity", purpose: "Ops-meets-dev role-play, dashboard diagnosis. (60 min)" },
    { code: "14:45", name: "Module 5: Fleet Architecture",    purpose: "Node density, etcd limits, split vs grow. (90 min)" },
    { code: "16:15", name: "Module 6: Fleet Observability",   purpose: "Multi-cluster dashboards, metric allowlists. (60 min)" },
    { code: "17:30", name: "Module 7: Integration Challenge", purpose: "Black Friday chaos game, 4-wave simulation. (60 min)" },
    { code: "18:30", name: "Module 8: Strategic Roadmap",     purpose: "12-month capacity plan, executive pitch. (30 min)" },
  ], { colW: [1.80, 4.20, 6.09], rowH: 0.42 });
  addCaption(s, "Module 9 (AI-Assisted Ops, 90 min) is optional and scheduled based on Lightspeed availability.");
  addNotes(s, "This is an 8-hour workshop with a lunch break and two short breaks. Modules build on each other: baselines first, then forecasting, then right-sizing, then fleet architecture, then observability, then the integration challenge that tests everything under simulated production pressure, and finally the strategic roadmap. We close with a 3-minute executive pitch exercise. Module 9 on AI-assisted ops with OpenShift Lightspeed is optional and runs after the main agenda if time and Lightspeed availability permit.");
}

// ============================================================================
// SLIDE 12 — Section Divider: Module Overview
// ============================================================================
divider("03", "Module Overview",
  "Key concepts and hands-on labs from each module.",
  "Let me preview what each module covers. Each one has a concept section followed by a hands-on lab that produces a concrete deliverable. I will highlight the key insight and the lab outcome for each module so you know what to expect.");

// ============================================================================
// SLIDE 13 — Module 1: Planning Horizons
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 1 · 60 MINUTES", "The Planning Horizon & Baselines");
  addBullets(s, [
    { text: "Three Planning Horizons", options: { bullet: false, bold: true } },
    { text: "Tactical (0–3 months): Can we handle tomorrow’s deployment?", sub: true },
    { text: "Operational (3–12 months): Quarterly budget cycles and predictable growth.", sub: true },
    { text: "Strategic (1–3 years): Commitment purchases, architectural decisions.", sub: true },
    { text: "Lab: The 90-Day Audit", options: { bullet: false, bold: true } },
    { text: "Audit node capacity, CPU/memory allocation vs actual consumption, and quantify the waste gap in dollars.", sub: true },
  ], { fontSize: 16 });
  addNotes(s, "Module 1 establishes the foundation: you cannot plan capacity without knowing where you stand today. Students learn to differentiate between tactical, operational, and strategic planning horizons — each with different data needs and decision cadences. The lab walks through a 90-day audit using oc adm top nodes and PromQL queries to measure actual allocation versus consumption on their student cluster. The key finding is always surprising: clusters typically show 42% CPU requested but only 7.6% actually consumed. We quantify this gap in dollar terms to make the business case for capacity planning.");
}

// ============================================================================
// SLIDE 14 — Module 2: Forecasting Math
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 2 · 60 MINUTES", "The Mathematics of Forecasting");
  addBullets(s, [
    "Linear CPU trending fails for microservices — deployments arrive in bursts, not straight lines.",
    "Pod Velocity counts new services deployed per period, not raw CPU percentage.",
    { text: "The Pod Velocity Formula", options: { bullet: false, bold: true } },
    { text: "Quarterly Nodes = (Pod Velocity × Avg Replicas × Avg CPU Request) / Node Allocatable CPU", sub: true },
    { text: "Example: (50 svc × 3 replicas × 0.2 cores) / 8 cores = 4 new nodes per quarter.", sub: true },
    "Lab: Build a Pod Velocity calculator and push a custom ACM forecasting dashboard to Grafana.",
  ], { fontSize: 16 });
  addNotes(s, "Module 2 introduces Pod Velocity — the rate of new service deployments over time. Unlike linear CPU trending, which extrapolates current usage into the future, Pod Velocity captures the burst pattern of microservices growth. The formula multiplies new services by average replicas by average CPU request, then divides by node allocatable CPU to get quarterly node requirements. In the lab, students run a PromQL-based calculator script against their cluster and push a custom forecasting dashboard to the hub Grafana using a ConfigMap. This dashboard becomes a permanent capacity planning tool.");
}

// ============================================================================
// SLIDE 15 — Module 3: Developer Track
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 3 · 90 MINUTES", "Developer Track: The “Zero Request” Myth");
  addStatusTable(s, [
    { code: "Guaranteed", name: "requests == limits", purpose: "Protected from eviction. Use for critical production workloads." },
    { code: "Burstable",  name: "requests < limits", purpose: "Medium eviction priority. Most production applications." },
    { code: "BestEffort", name: "No requests/limits", purpose: "First to be killed under pressure. Dev/test only." },
  ], { colW: [2.40, 3.00, 6.69], h: 2.30 });
  addBullets(s, [
    "Deploying without resource requests means your pod is first in line for termination under memory pressure.",
    "Lab: Debug OOMKill events, measure CPU throttling with Prometheus, and configure HPA with right-sized metrics.",
  ], { y: 4.30, fontSize: 16 });
  addNotes(s, "Module 3 is the developer track. Many developers see resource requests as administrative overhead — a checkbox to satisfy the platform team. This module proves why zero-request pods are dangerous: Kubernetes assigns them BestEffort QoS, making them the first to be evicted under memory pressure. Students observe three QoS classes side-by-side, debug a real OOMKill event, measure CPU throttling in Prometheus dashboards, and then configure a Horizontal Pod Autoscaler using P95-based resource recommendations from the right-sizer script. The key insight: resource requests are a contract with the scheduler, not a restriction.");
}

// ============================================================================
// SLIDE 16 — Module 4: Right-Sizing Activity
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 4 · 60 MINUTES", "The Right-Sizing Activity: Ops Meets Dev");
  addBullets(s, [
    "A checkout-api service requests 500m CPU but idles at 30m — wasting 940m across 2 replicas.",
    "Ops sees “cluster is full”; Dev says “we are barely using anything.” Both are right.",
    { text: "Role-Play Lab", options: { bullet: false, bold: true } },
    { text: "Ops Hat: diagnose the problem using Grafana dashboards and Prometheus queries.", sub: true },
    { text: "Dev Hat: interpret the data, determine correct resource values, apply the fix.", sub: true },
    "The dashboard is the shared language that bridges operations and development teams.",
  ], { fontSize: 16 });
  addNotes(s, "Module 4 bridges the ops-dev divide using a role-play lab. A checkout-api deployment requests 500m CPU per replica but actually consumes only 10-30m, and its memory limit of 64Mi is dangerously low for a process that actually needs 80-120Mi. Students swap between ops and dev perspectives: ops diagnoses the problem using an 8-panel Grafana dashboard showing utilization gauges, restart counts, and throttling rates; dev interprets the data and applies the fix. The key insight is that Grafana dashboards serve as the shared language — when ops and dev look at the same data, they stop arguing and start collaborating.");
}

// ============================================================================
// SLIDE 17 — Module 5: Fleet Architecture
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 5 · 90 MINUTES", "Fleet Architecture & Node Density");
  addBullets(s, [
    "Default maxPods is 250 per node — microservices architectures hit this faster than you expect.",
    { text: "Minimum Nodes = ceil(Total Pods / maxPods) × Redundancy Factor", sub: true },
    "Each pod consumes 5–15 KB of node memory overhead for cgroup tracking and kubelet bookkeeping.",
    "The etcd database limit is 8 GB — at 3.8 GB you are at 48% and should plan a cluster split.",
    { text: "The Decision", options: { bullet: false, bold: true } },
    { text: "Split into multiple clusters (RHACM federation) or grow the existing one? The etcd size and API server latency decide.", sub: true },
    "Lab: Tune KubeletConfig from 250 to 500+ maxPods and measure the impact on memory and API latency.",
  ], { fontSize: 15 });
  addNotes(s, "Module 5 covers infrastructure sizing at fleet scale. The default maxPods of 250 per node is surprisingly easy to exhaust with microservices architectures. Students learn the pod density formula, understand the 5-15 KB memory overhead per pod for cgroup tracking and kubelet bookkeeping, and observe how the etcd database size constrains cluster growth — the hard limit is 8 GB, and at 48% you should already be planning a cluster split. The lab lets students tune KubeletConfig to increase maxPods from 250 to 500, trigger a Machine Config Operator rollout, then run a 400-pod mass-scheduling event to measure the trade-offs in node memory usage and API server response time.");
}

// ============================================================================
// SLIDE 18 — Module 6: Fleet Observability
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 6 · 60 MINUTES", "Fleet Observability with RHACM");
  addBullets(s, [
    "RHACM Observability aggregates Prometheus metrics from every managed cluster into Thanos on the hub.",
    "Custom metric allowlists control what gets forwarded — reducing storage costs by up to 95%.",
    "Grafana on the hub queries Thanos for cross-cluster capacity dashboards.",
    { text: "Lab: The God’s-Eye Dashboard", options: { bullet: false, bold: true } },
    { text: "Build a 7-panel multi-cluster dashboard: total pods, CPU/memory utilization, capacity runway, pod density, etcd size, and namespace showback.", sub: true },
    { text: "Simulate capacity growth with kube-burner and watch the runway panel respond in real time.", sub: true },
  ], { fontSize: 16 });
  addNotes(s, "Module 6 connects everything into a centralized view. RHACM Observability pulls metrics from every managed cluster into Thanos on the hub, where Grafana renders fleet-wide capacity dashboards. Students configure custom metric allowlists to balance cost and coverage — the default forwards everything, which at 500 GB per cluster per month is expensive; a well-tuned allowlist reduces this to about 25 GB. The lab builds a God's-Eye dashboard with 7 panels showing fleet capacity from every angle, then uses kube-burner to simulate workload growth and watch the capacity runway panel count down in real time.");
}

// ============================================================================
// SLIDE 19 — Module 7: Integration Challenge
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 7 · 60 MINUTES", "The Integration Challenge: Black Friday");
  addBullets(s, [
    "Scenario: Black Friday traffic spike meets a partial AWS region outage.",
    { text: "Wave 1: Traffic surges — kube-burner deploys load pods, HPA fires, pods go Pending.", sub: true },
    { text: "Wave 2: Node failure — cordon and drain a node, simulating an AZ outage.", sub: true },
    { text: "Wave 3: etcd pressure — 20 zero-replica Deployments stress the API server.", sub: true },
    { text: "Wave 4: Recovery — uncordon, scale down, restore baseline.", sub: true },
    { text: "Game Rules", options: { bullet: false, bold: true } },
    { text: "Maintain >95% success rate for 60 minutes. Spend less than $5,000 emergency budget. No complete outages.", sub: true },
  ], { fontSize: 15 });
  addNotes(s, "Module 7 is the chaos game — four waves of escalating production pressure. Wave 1 spikes traffic and triggers HPA scaling that may push pods to Pending. Wave 2 simulates an AZ outage by cordoning and draining a node. Wave 3 adds etcd pressure with 20 zero-replica Deployments that stress the API server. Wave 4 is recovery. At each wave, teams face decision points with real cost trade-offs: scaling up costs $200 per node per hour, throttling saves money but loses revenue, failover risks overloading another region. The goal is to apply everything learned in Modules 1–6 under realistic production pressure while staying within a $5,000 emergency budget.");
}

// ============================================================================
// SLIDE 20 — Module 8: Strategic Roadmapping
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 8 · 30 MINUTES", "Strategic Roadmapping: The Executive Pitch");
  addBullets(s, [
    "Translate technical metrics into executive language: cost, risk, growth, commitments.",
    { text: "Pod Velocity +50/quarter → “Can our platform scale with the product roadmap?”", sub: true },
    { text: "42% allocated, 7.6% used → “$18K/month waste — where can we cut without risk?”", sub: true },
    { text: "etcd at 3.8 GB / 8 GB → “When do we need to split the cluster? What will it cost?”", sub: true },
    "Build a 12-month capacity roadmap with quarterly milestones and budget projections.",
    "Lab: Prepare and deliver a 3-minute executive pitch based on your workshop data.",
  ], { fontSize: 16 });
  addNotes(s, "Module 8 is the capstone. Students translate their technical findings into executive-level recommendations. The 42% allocation versus 7.6% utilization becomes 'we are wasting $18,000 per month on unused capacity — here is how we reclaim it.' The etcd size at 48% becomes 'we need to plan a cluster split by Q3 — here is the timeline and cost.' Each student uses the capacity-roadmap-generator script to build a 12-month roadmap with quarterly milestones, then delivers a 3-minute executive pitch to their peers. The rubric evaluates whether they led with business impact, quantified the ask, and proposed a specific timeline.");
}

// ============================================================================
// SLIDE 21 — Module 9: AI-Assisted Ops
// ============================================================================
{
  const s = S();
  addContentTitle(s, "MODULE 9 · 90 MINUTES · OPTIONAL", "AI-Assisted Capacity Operations");
  addBullets(s, [
    "OpenShift Lightspeed: an AI assistant embedded in the OpenShift console with documentation-grounded answers.",
    { text: "Developer queries: debug OOMKill events, write resource specs, author HPA configurations.", sub: true },
    { text: "Infrastructure queries: reason about maxPods safety, etcd monitoring, fleet architecture trade-offs.", sub: true },
    { text: "Forecasting co-pilot: author PromQL, estimate capacity runway, translate metrics to budget language.", sub: true },
    "Compare model responses: IBM Granite 3.2 8B vs Qwen3 14B on the same capacity planning questions.",
    "Live cluster queries via Model Context Protocol (MCP) for real-time Kubernetes API data.",
  ], { fontSize: 15 });
  addNotes(s, "Module 9 introduces OpenShift Lightspeed as a capacity planning co-pilot. Students query it from three perspectives: as a developer debugging resource sizing and OOMKill events, as an infrastructure engineer reasoning about node density and fleet architecture, and as a forecasting assistant authoring PromQL queries and translating metrics into executive budget language. The lab includes a model comparison between IBM Granite 3.2 8B — which is trained on Red Hat documentation — and Qwen3 14B, evaluating accuracy, completeness, and actionability. The final lab uses Model Context Protocol for live cluster queries, letting the AI reason about actual cluster state rather than training data alone.");
}

// ============================================================================
// SLIDE 22 — Section Divider: Outcomes
// ============================================================================
divider("04", "Outcomes & Next Steps",
  "What you take home and where you go from here.",
  "Let us summarize what you will build today and map out what comes next. Every module produces a deliverable — a script, a dashboard, a roadmap, a decision log. The question now is: how do you apply this in your organization starting Monday?");

// ============================================================================
// SLIDE 23 — Deliverables
// ============================================================================
{
  const s = S();
  addContentTitle(s, "DELIVERABLES", "Concrete Takeaways from Each Module");
  addTwoColBullets(s, [
    { text: "Modules 1–4", options: { bullet: false, bold: true } },
    "90-day capacity baseline audit",
    "Pod Velocity calculator and PromQL queries",
    "Right-sized deployment manifests",
    "Ops-dev collaboration playbook",
  ], [
    { text: "Modules 5–8", options: { bullet: false, bold: true } },
    "Node density tuning results",
    "Multi-cluster Grafana dashboard",
    "Incident decision log from the chaos game",
    "12-month strategic capacity roadmap",
  ], { fontSize: 16 });
  addNotes(s, "Each module produces a concrete deliverable. From Module 1, you have a cluster baseline with the waste gap quantified in dollars. From Module 2, a Pod Velocity forecasting model and a custom Grafana dashboard. From Modules 3 and 4, right-sized deployment manifests and a collaboration playbook for bridging ops and dev. From Module 5, density tuning data. From Module 6, fleet-wide Grafana dashboards. From Module 7, an incident decision log showing how your team handled production pressure. From Module 8, a 12-month strategic roadmap ready for executive presentation. These are not slide-ware — they are artifacts you can present to your leadership team next week.");
}

// ============================================================================
// SLIDE 24 — Diagram: Maturity Model
// ============================================================================
{
  const s = S();
  addDiagramSlide(s, "MATURITY", "Capacity Planning Maturity Progression",
    "r04-maturity-model",
    "This workshop targets Level 1 (Reactive) to Level 3 (Operational). Level 4 requires organizational adoption.");
  addNotes(s, "Here is the maturity model. Level 1 is reactive: no baselines, ad-hoc firefighting, surprise outages. Level 2 is tactical: basic monitoring and manual forecasts are in place. Level 3 is operational: Pod Velocity models, multi-cluster dashboards, and quarterly roadmaps drive capacity decisions. Level 4 is strategic: AI-assisted ops, FinOps integration, and multi-year commitment planning. This workshop takes you from wherever you are today to Level 3. Module 9 gives you a preview of Level 4, but reaching it fully requires organizational adoption beyond a single workshop — executive buy-in, FinOps integration, and continuous improvement cycles.");
}

// ============================================================================
// SLIDE 25 — 90-Day Action Plan
// ============================================================================
{
  const s = S();
  addContentTitle(s, "NEXT STEPS", "Your 90-Day Action Plan");
  addStatusTable(s, [
    { code: "Week 1",    name: "Baseline Audit",    purpose: "Run the Module 1 audit on production clusters. Share the waste numbers with leadership." },
    { code: "Week 2–3", name: "Pod Velocity",       purpose: "Calculate your organization’s pod velocity. Set up PromQL recording rules." },
    { code: "Month 1",   name: "Right-Size Top 10",  purpose: "Identify the top 10 over-provisioned workloads. Apply fixes. Measure savings." },
    { code: "Month 2",   name: "Fleet Dashboards",   purpose: "Deploy RHACM Observability. Build multi-cluster capacity dashboards." },
    { code: "Month 3",   name: "Executive Roadmap",  purpose: "Present your 12-month capacity plan to executive sponsors." },
  ], { colW: [1.80, 3.00, 7.29], rowH: 0.55 });
  addNotes(s, "Here is your 90-day action plan. Week 1: run the baseline audit from Module 1 on your production clusters and share the waste numbers with leadership — the dollar figure always gets attention. Weeks 2 and 3: set up Pod Velocity tracking with PromQL recording rules. Month 1: identify and right-size your top 10 over-provisioned workloads using the P95 methodology from Module 3 and measure the dollar savings. Month 2: deploy RHACM Observability and build fleet-wide capacity dashboards using the patterns from Module 6. Month 3: present your 12-month capacity roadmap to executive sponsors using the framework from Module 8. By day 90, you will have moved from reactive to operational.");
}

// ============================================================================
// SLIDE 26 — Resources
// ============================================================================
{
  const s = S();
  addContentTitle(s, "RESOURCES", "Where to Go Deeper");
  addBullets(s, [
    "Workshop lab guide — available in Showroom after the session for continued practice.",
    "Red Hat Advanced Cluster Management documentation — multi-cluster observability setup and configuration.",
    "OpenShift documentation — kubelet configuration, resource management, and autoscaling reference.",
    "Prometheus and Thanos documentation — PromQL reference and long-term storage architecture.",
    "FinOps Foundation — cloud financial management best practices and the FinOps maturity model.",
    "OpenShift Lightspeed documentation — AI assistant configuration, model support, and MCP integration.",
  ], { fontSize: 16 });
  addNotes(s, "These are your key references for continued learning. The workshop lab guide remains accessible in Showroom for practice after today. The RHACM documentation covers the production deployment of observability with custom metric allowlists and Thanos configuration. The OpenShift documentation has the KubeletConfig and resource management reference. The FinOps Foundation site provides the broader cloud financial management framework that capacity planning plugs into. And the OpenShift Lightspeed documentation covers AI assistant setup for organizations ready to explore Level 4 maturity.");
}

// ============================================================================
// SLIDE 27 — Questions / Closing
// ============================================================================
{
  const s = S();
  addContentTitle(s, "CLOSING", "Questions & Discussion");
  addBullets(s, [
    "Thank you for investing a full day in capacity planning.",
    "The gap between “allocated” and “consumed” is where your savings live.",
    "Start with the baseline. Everything else follows.",
  ], { fontSize: 18 });
  addCaption(s, "Tosin Akinosho  |  Red Hat");
  addNotes(s, "Thank you for your time and engagement today. Remember: the single most important thing you can do Monday morning is run that 90-day audit from Module 1. Once you know where you stand — how much you have allocated versus how much you actually consume — everything else builds naturally: forecasting, right-sizing, fleet dashboards, the executive roadmap. The waste gap is where your savings live, and now you know how to find it, measure it, and fix it. I am happy to take questions now or follow up afterward.");
}

// ============================================================================
// Write the deck
// ============================================================================
pres.writeFile({ fileName: OUT })
  .then(p => console.log("WROTE", p))
  .catch(e => { console.error(e); process.exit(1); });
