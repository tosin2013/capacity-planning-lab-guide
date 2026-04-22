#!/usr/bin/env bash
# capacity-roadmap-generator.sh
# Module 7 — Strategic Roadmapping: The 12-Month Plan
#
# Queries the student cluster Prometheus API to collect live capacity metrics
# (pod count, worker nodes, CPU allocation/usage, etcd size, pod velocity),
# then generates a filled-in 12-month capacity roadmap markdown file.
#
# Usage:
#   ./capacity-roadmap-generator.sh
#   NAMESPACE=my-namespace ./capacity-roadmap-generator.sh
#   MONTHLY_COST_PER_NODE=300 NODE_CPU=16 ./capacity-roadmap-generator.sh
#
# Environment variables (all optional):
#   NAMESPACE              Namespace for pod-velocity calculation (default: capacity-workshop)
#   WINDOW_DAYS            Lookback window for pod velocity       (default: 30)
#   NODE_CPU               Allocatable cores per worker node      (default: 8)
#   MONTHLY_COST_PER_NODE  On-demand $/node/month for budget math (default: 200)

set -euo pipefail

NAMESPACE="${NAMESPACE:-capacity-workshop}"
WINDOW_DAYS="${WINDOW_DAYS:-30}"
NODE_CPU="${NODE_CPU:-8}"
MONTHLY_COST_PER_NODE="${MONTHLY_COST_PER_NODE:-200}"
OUTPUT_FILE="${HOME}/12-month-capacity-roadmap.md"
DATA_FILE="${HOME}/capacity-roadmap-data.txt"

# ── colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; }

# ── pre-flight ────────────────────────────────────────────────────────────────
command -v oc     &>/dev/null || error "'oc' not found. Run this script on your student bastion."
command -v curl   &>/dev/null || error "'curl' not found."
command -v python3 &>/dev/null || error "'python3' not found."

header "Module 7 — Capacity Roadmap Generator"
info "Namespace  : ${NAMESPACE}"
info "Window     : ${WINDOW_DAYS} days"
info "Node CPU   : ${NODE_CPU} cores (allocatable)"
info "Node cost  : \$${MONTHLY_COST_PER_NODE}/month"
info "Output     : ${OUTPUT_FILE}"

# ── Step 1: Discover Prometheus ───────────────────────────────────────────────
echo ""
info "Step 1/7 — Locating Prometheus route …"
PROM_HOST=$(oc get route -n openshift-monitoring prometheus-k8s \
  -o jsonpath='{.spec.host}' 2>/dev/null) || error "Could not find prometheus-k8s route in openshift-monitoring."
PROM_URL="https://${PROM_HOST}"
success "Prometheus : ${PROM_URL}"

# ── Step 2: Mint a short-lived token ─────────────────────────────────────────
info "Step 2/7 — Minting Prometheus service-account token …"
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring 2>/dev/null) \
  || error "Could not create token for prometheus-k8s service account."
success "Token acquired (${#TOKEN} chars)"

# ── helper: run a PromQL instant query ───────────────────────────────────────
promql() {
  local query="$1"
  curl -sk -H "Authorization: Bearer ${TOKEN}" \
    --data-urlencode "query=${query}" \
    "${PROM_URL}/api/v1/query"
}

scalar_result() {
  python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('status') != 'success':
    print('ERROR:' + d.get('error','unknown'))
    sys.exit(1)
rt = d['data']['resultType']
r  = d['data']['result']
if rt == 'scalar':
    print(d['data']['result'][1])
elif r:
    print(r[0]['value'][1])
else:
    print('0')
"
}

# ── Step 3: Cluster Baseline (Module 1 data) ──────────────────────────────────
echo ""
info "Step 3/7 — Gathering cluster baseline …"

TOTAL_PODS=$(oc get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
WORKER_NODES=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | wc -l | tr -d ' ')

# CPU allocated (sum of all pod CPU requests across cluster, in cores)
CPU_ALLOCATED=$(promql "sum(kube_pod_container_resource_requests{resource=\"cpu\"})" \
  | scalar_result 2>/dev/null || echo "0")

# CPU actually used (5m average)
CPU_USED=$(promql "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m]))" \
  | scalar_result 2>/dev/null || echo "0")

# Total allocatable CPU across all worker nodes
CPU_ALLOCATABLE=$(promql "sum(kube_node_status_allocatable{resource=\"cpu\",node=~\".*\"})" \
  | scalar_result 2>/dev/null || echo "0")

success "Total pods           : ${TOTAL_PODS}"
success "Worker nodes         : ${WORKER_NODES}"

python3 - <<PYEOF
alloc     = float("${CPU_ALLOCATED}")
used      = float("${CPU_USED}")
total     = float("${CPU_ALLOCATABLE}")
alloc_pct = (alloc / total * 100) if total > 0 else 0
used_pct  = (used  / total * 100) if total > 0 else 0
waste     = alloc - used
waste_pct = (waste / total * 100) if total > 0 else 0
green = "\033[0;32m"; reset = "\033[0m"
print(f"{green}[OK]{reset}    Allocatable CPU      : {total:.1f} cores")
print(f"{green}[OK]{reset}    CPU allocated (req)  : {alloc:.1f} cores  ({alloc_pct:.1f}% of allocatable)")
print(f"{green}[OK]{reset}    CPU used (actual)    : {used:.1f} cores  ({used_pct:.1f}% of allocatable)")
print(f"{green}[OK]{reset}    Waste (alloc - used) : {waste:.1f} cores  ({waste_pct:.1f}%)")
PYEOF

# ── Step 4: Pod Velocity (Module 2 data) ─────────────────────────────────────
echo ""
info "Step 4/7 — Calculating pod velocity (${WINDOW_DAYS}-day window) …"

WINDOW_SECS=$(( WINDOW_DAYS * 86400 ))

PODS_STARTED=$(promql "count(kube_pod_start_time{namespace=\"${NAMESPACE}\"} > (time() - ${WINDOW_SECS}))" \
  | scalar_result 2>/dev/null || echo "0")

if [[ "${PODS_STARTED}" == "0" ]]; then
  warn "No pods in '${NAMESPACE}' within ${WINDOW_DAYS}d — using cluster-wide pod count."
  PODS_STARTED=$(promql "count(kube_pod_info)" | scalar_result 2>/dev/null || echo "${TOTAL_PODS}")
fi

POD_VELOCITY=$(python3 -c "print(round(float('${PODS_STARTED}') / ${WINDOW_DAYS}, 2))")
PODS_STARTED_INT=$(python3 -c "print(round(float('${PODS_STARTED}')))")
success "Pods started (${WINDOW_DAYS}d)  : ${PODS_STARTED_INT}"
success "Pod velocity         : ${POD_VELOCITY} pods/day"

# ── Step 5: etcd DB Size (Module 4 data) ──────────────────────────────────────
echo ""
info "Step 5/7 — Checking etcd database size …"

ETCD_GB=$(promql "max(etcd_mvcc_db_total_size_in_bytes) / 1024 / 1024 / 1024" \
  | scalar_result 2>/dev/null || echo "0")
ETCD_LIMIT_GB=8

python3 - <<PYEOF
etcd_gb    = float("${ETCD_GB}")
limit_gb   = float("${ETCD_LIMIT_GB}")
pct        = (etcd_gb / limit_gb * 100) if limit_gb > 0 else 0
green = "\033[0;32m"; yellow = "\033[1;33m"; red = "\033[0;31m"; reset = "\033[0m"
color = green if pct < 50 else (yellow if pct < 75 else red)
print(f"{color}[{'OK' if pct < 50 else 'WARN'}]{reset}   etcd DB size         : {etcd_gb:.2f} GB  ({pct:.1f}% of {limit_gb}GB limit)")
if pct >= 75:
    print(f"{red}[WARN]{reset}  etcd above 75%! Plan cluster split soon.")
PYEOF

# ── Step 6: RHACM Managed Clusters (Module 5 data) ───────────────────────────
echo ""
info "Step 6/7 — Checking RHACM managed clusters …"

# Check separately: first test if the CRD exists, then count
MANAGED_CLUSTERS="N/A"
if oc api-resources 2>/dev/null | grep -q 'managedclusters'; then
  MANAGED_CLUSTERS=$(oc get managedclusters --no-headers 2>/dev/null | wc -l | tr -d ' ')
  success "Managed clusters     : ${MANAGED_CLUSTERS}"
else
  warn "ManagedCluster CRD not found — RHACM is not installed on this cluster."
fi

# ── Step 7: Generate the Roadmap ──────────────────────────────────────────────
echo ""
info "Step 7/7 — Generating 12-month capacity roadmap …"

TODAY=$(date '+%B %d, %Y')
YEAR=$(date '+%Y')
NEXT_YEAR=$(( YEAR + 1 ))

python3 - <<PYEOF
import math, datetime, os

# ── inputs from bash ─────────────────────────────────────────────────────────
total_pods        = int("${TOTAL_PODS}")
worker_nodes      = int("${WORKER_NODES}")
cpu_allocated     = float("${CPU_ALLOCATED}")
cpu_used          = float("${CPU_USED}")
cpu_allocatable   = float("${CPU_ALLOCATABLE}")
etcd_gb           = float("${ETCD_GB}")
pod_velocity_day  = float("${POD_VELOCITY}")   # pods/day cluster-wide
node_cpu          = float("${NODE_CPU}")
monthly_per_node  = float("${MONTHLY_COST_PER_NODE}")
managed_clusters  = "${MANAGED_CLUSTERS}"
today             = "${TODAY}"
year              = int("${YEAR}")
next_year         = int("${NEXT_YEAR}")
output_file       = "${OUTPUT_FILE}"
data_file         = "${DATA_FILE}"
namespace         = "${NAMESPACE}"
window_days       = int("${WINDOW_DAYS}")

# ── derived metrics ───────────────────────────────────────────────────────────
alloc_pct       = (cpu_allocated / cpu_allocatable * 100) if cpu_allocatable > 0 else 0
used_pct        = (cpu_used / cpu_allocatable * 100) if cpu_allocatable > 0 else 0
waste_cores     = max(cpu_allocated - cpu_used, 0)
waste_pct       = (waste_cores / cpu_allocatable * 100) if cpu_allocatable > 0 else 0

monthly_cost    = worker_nodes * monthly_per_node
annual_baseline = monthly_cost * 12
cost_per_core   = (monthly_cost / cpu_allocatable) if cpu_allocatable > 0 else monthly_per_node / node_cpu
waste_cost_mo   = waste_cores * cost_per_core

# pod velocity quarterly projection (pods/day → cores/quarter)
pod_vel_quarter = pod_velocity_day * 90
# estimate: average 0.2 cores per pod (workshop default)
avg_cpu_per_pod = 0.2
cpu_growth_q    = pod_vel_quarter * avg_cpu_per_pod
cpu_growth_year = cpu_growth_q * 3   # 3 remaining quarters
cpu_year_end    = cpu_allocated + cpu_growth_year
growth_pct      = (cpu_growth_year / cpu_allocated * 100) if cpu_allocated > 0 else 0

# etcd status
etcd_pct        = (etcd_gb / 8 * 100) if etcd_gb > 0 else 0
etcd_str        = f"{etcd_gb:.2f} GB ({etcd_pct:.0f}% of 8GB limit)"
etcd_action     = "Monitor monthly" if etcd_pct < 50 else ("Plan cluster split in next 2 quarters" if etcd_pct < 75 else "URGENT: plan cluster split immediately")

# RI commitment strategy (60-80% of current nodes)
ri_nodes        = math.floor(worker_nodes * 0.67)
od_nodes        = worker_nodes - ri_nodes
ri_discount     = 0.33
ri_monthly_save = ri_nodes * monthly_per_node * ri_discount
ri_annual_save  = ri_monthly_save * 12

# budget forecast
q_optimize_save  = monthly_cost * 0.10 * 3      # 10% waste reduction over Q2 (3 months)
q_scale_nodes    = max(math.ceil(cpu_growth_q / node_cpu), 1)
q_scale_cost     = q_scale_nodes * monthly_per_node * 3
q4_temp_nodes    = max(q_scale_nodes, 2)
q4_temp_cost     = q4_temp_nodes * monthly_per_node * 8 / 730 * 8   # hourly rate × 8 hours
subtotal         = annual_baseline - q_optimize_save + q_scale_cost + q4_temp_cost
contingency      = subtotal * 0.10
total_budget     = subtotal + contingency
yoy_pct          = ((total_budget - annual_baseline) / annual_baseline * 100) if annual_baseline > 0 else 0

# ── data report ──────────────────────────────────────────────────────────────
data_lines = f"""=== Module 1: Baseline ===
Total Pods: {total_pods}
Worker Nodes: {worker_nodes}
CPU Allocatable: {cpu_allocatable:.1f} cores
CPU Allocated (requests): {cpu_allocated:.1f} cores ({alloc_pct:.1f}%)
CPU Used (actual): {cpu_used:.1f} cores ({used_pct:.1f}%)
Waste: {waste_cores:.1f} cores ({waste_pct:.1f}%)
Monthly Cost: \${monthly_cost:,.0f}  (est. at \${monthly_per_node}/node)
Waste Cost: \${waste_cost_mo:,.0f}/month

=== Module 2: Pod Velocity ===
Pod Velocity ({window_days}d window): {pod_velocity_day:.2f} pods/day
Quarterly projection: {pod_vel_quarter:.0f} new pods → {cpu_growth_q:.1f} cores
Year-end CPU needed: {cpu_year_end:.1f} cores (+{growth_pct:.0f}% growth)

=== Module 3: Right-Sizing ===
[Run: oc adm top nodes -l node-role.kubernetes.io/worker]

=== Module 4: etcd Size ===
etcd DB Size: {etcd_str}
Recommendation: {etcd_action}

=== Module 5: Fleet View ===
Managed Clusters: {managed_clusters}
"""
with open(data_file, 'w') as f:
    f.write(data_lines)

print(data_lines)

# ── roadmap markdown ─────────────────────────────────────────────────────────
roadmap = f"""# 12-Month Strategic Capacity Roadmap
**Prepared by**: [Your Name]
**Date**: {today}
**Planning Horizon**: Q2 {year} - Q1 {next_year}
**Generated by**: capacity-roadmap-generator.sh (live cluster data)

---

## Executive Summary

**Recommendation**: Approve \${total_budget:,.0f} infrastructure budget for {year} ({'+' if yoy_pct >= 0 else ''}{yoy_pct:.1f}% vs prior year)

**Key Actions**:
- Q2: Optimize existing workloads — target \${q_optimize_save/3:,.0f}/month savings through right-sizing
- Q3: Add {q_scale_nodes} worker node(s) as CPU allocation approaches 80% capacity
- Q4: {'Plan cluster split (etcd at ' + etcd_str + ')' if etcd_pct > 40 else 'Monitor etcd (' + etcd_str + '); plan ahead if growth continues'}; pre-provision for peak traffic
- Q1 {next_year}: Scale down temporary capacity; implement Cluster Autoscaler

**Commitment Strategy**: Purchase 1-Year RIs for {ri_nodes} nodes (save \${ri_annual_save:,.0f}/year)

**Risks**: Pod velocity at {pod_velocity_day:.1f} pods/day. At this pace we will need {q_scale_nodes} additional node(s) per quarter. If velocity increases >20%, emergency capacity may be required.

---

## 1. Current State (Baseline)

| Metric | Value | Notes |
|--------|-------|-------|
| Worker Nodes | {worker_nodes} | on-demand at \${monthly_per_node}/node/month |
| Total Pods | {total_pods} | cluster-wide |
| CPU Allocatable | {cpu_allocatable:.1f} cores | across all worker nodes |
| CPU Allocated (requests) | {cpu_allocated:.1f} cores ({alloc_pct:.0f}%) | sum of container resource requests |
| CPU Used (actual) | {cpu_used:.1f} cores ({used_pct:.0f}%) | 5-minute average from Prometheus |
| CPU Waste | {waste_cores:.1f} cores ({waste_pct:.0f}%) | allocated but not used |
| Monthly Cost | \${monthly_cost:,.0f} | \${monthly_per_node}/node × {worker_nodes} nodes |
| Waste Cost | \${waste_cost_mo:,.0f}/month | unused allocated CPU |
| etcd DB Size | {etcd_str} | |
| Managed Clusters | {managed_clusters} | RHACM fleet |

**Finding**: {'We are wasting $' + f'{waste_cost_mo:,.0f}' + '/month on unused allocated CPU (' + f'{waste_pct:.0f}' + '% of allocatable). Right-sizing is the highest-ROI Q2 action.' if waste_pct > 10 else 'CPU waste is within acceptable range (<10%). Focus on growth planning rather than optimization.'}

---

## 2. Growth Forecast (Pod Velocity Model)

**{window_days}-Day Observation**:
- Pod velocity: {pod_velocity_day:.2f} pods/day ({pod_velocity_day*30:.0f} pods/month)
- Avg CPU request assumed: {avg_cpu_per_pod*1000:.0f}m per pod

**Quarterly Projections**:
- Q2: +{pod_vel_quarter:.0f} pods → +{cpu_growth_q:.1f} cores needed
- Q3: +{pod_vel_quarter:.0f} pods → +{cpu_growth_q:.1f} cores needed
- Q4: +{pod_vel_quarter:.0f} pods → +{cpu_growth_q:.1f} cores needed

**Year-End Total**: {cpu_year_end:.1f} cores allocated ({'+' if growth_pct >= 0 else ''}{growth_pct:.0f}% growth from today)

> **Note**: Model assumes linear growth at current pod velocity. Adjust for known product launches, migrations, or seasonal peaks.

---

## 3. Quarterly Milestones

### Q2 {year} (Apr–Jun) — Optimization Phase
**Actions**:
- Right-size top over-provisioned workloads using \`resource-right-sizer.sh\` (Module 3)
- Deploy RHACM Observability for fleet-wide visibility (Module 5)
- Implement automated capacity dashboards in Grafana

**Capacity Change**: +0 nodes
**Cost Impact**: −\${q_optimize_save/3:,.0f}/month (target: eliminate {waste_pct:.0f}% waste)

---

### Q3 {year} (Jul–Sep) — Scale-Up
**Actions**:
- Add {q_scale_nodes} worker node(s) as CPU allocation approaches 80%
- {'Begin cluster split planning — etcd at ' + f'{etcd_gb:.2f}GB, approaching split threshold' if etcd_pct > 40 else 'Monitor etcd growth; establish split runbook'}
- Run Pod Velocity check monthly; alert if velocity >20% above forecast

**Capacity Change**: +{q_scale_nodes} node(s)
**Cost Impact**: +\${q_scale_nodes * monthly_per_node:,.0f}/month

---

### Q4 {year} (Oct–Dec) — Peak Traffic Preparation
**Actions**:
- Pre-provision {q4_temp_nodes} temporary nodes for peak traffic window
- Run load test in October to validate capacity headroom
- {'Execute cluster split plan' if etcd_pct > 40 else 'Re-evaluate cluster split need based on Q3 etcd growth'}

**Capacity Change**: +{q4_temp_nodes} temporary nodes
**Cost Impact**: +\${q4_temp_cost:,.0f} one-time (peak traffic window)

---

### Q1 {next_year} (Jan–Mar) — Stabilize
**Actions**:
- Scale down peak-traffic temporary capacity
- Implement Cluster Autoscaler for future spikes
- Review actual vs. forecasted pod velocity; update Q2 {next_year} plan

**Capacity Change**: 0 (back to Q3 baseline)
**Cost Impact**: +\$0 (net neutral)

---

## 4. Budget Forecast

| Line Item | Amount | Notes |
|-----------|--------|-------|
| Current Run-Rate (annualized) | \${annual_baseline:,.0f} | {worker_nodes} nodes × \${monthly_per_node}/node × 12 |
| Q2 Optimization Savings | −\${q_optimize_save:,.0f} | Right-sizing waste reduction |
| Q3 Scale-Up | +\${q_scale_cost:,.0f} | {q_scale_nodes} node(s) × 3 months |
| Q4 Peak Traffic | +\${q4_temp_cost:,.0f} | Temporary capacity |
| **Subtotal** | **\${subtotal:,.0f}** | |
| Contingency (10%) | +\${contingency:,.0f} | Buffer for unplanned growth |
| **Total {year} Budget** | **\${total_budget:,.0f}** | **{'+' if yoy_pct >= 0 else ''}{yoy_pct:.1f}% YoY** |

---

## 5. Commitment Strategy (Reserved Instances)

**Recommendation**: Purchase 1-Year Reserved Instances for {ri_nodes} of {worker_nodes} nodes ({ri_nodes*100//worker_nodes if worker_nodes > 0 else 0}% of baseline)

| Option | RI Nodes | On-Demand | Monthly Cost | Annual Savings |
|--------|----------|-----------|--------------|----------------|
| All On-Demand | 0 | {worker_nodes} | \${monthly_cost:,.0f} | \$0 (baseline) |
| **{ri_nodes} RIs + {od_nodes} On-Demand** | **{ri_nodes}** | **{od_nodes}** | **\${monthly_cost:,.0f}** | **\${ri_annual_save:,.0f}** |
| All RIs (risky) | {worker_nodes} | 0 | \${monthly_cost*(1-ri_discount):,.0f} | \${monthly_cost*ri_discount*12:,.0f} (only if fully used) |

**Rationale**: {ri_nodes}-node RI commitment = {ri_nodes*100//worker_nodes if worker_nodes > 0 else 0}% of baseline (safe under-commit strategy). Saves \${ri_annual_save:,.0f}/year. Remaining {od_nodes} on-demand nodes provide flexibility for growth spikes.

---

## 6. Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Growth >20% above forecast | Medium | High | Monitor pod velocity monthly; alert if >20% variance |
| etcd limit before cluster split | {'Medium' if etcd_pct > 50 else 'Low'} | Critical (potential outage) | {etcd_action} |
| Peak traffic capacity insufficient | Low | High | Pre-provision {q4_temp_nodes} temp nodes; load test in Oct |
| Platform engineer turnover | High | Medium | Document capacity playbooks; cross-train 2nd engineer |

---

## 7. Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Cluster Availability | >99.9% uptime | Prometheus uptime alert |
| CPU Waste | <15% unused | Monthly right-sizing review |
| Budget Variance | Within ±10% | Finance monthly report |
| Emergency Response | <1 hour to add capacity | Runbook automation |

---

## 8. Recommendation

**Approve the following for {year}**:

- **Budget**: \${total_budget:,.0f} ({'+' if yoy_pct >= 0 else ''}{yoy_pct:.1f}% vs prior year)
- **Commitment**: 1-Year RIs for {ri_nodes} nodes (saves \${ri_annual_save:,.0f}/year)
- **Timeline**: Begin Q2 right-sizing immediately (quick wins, no extra spend)

**Next Steps**:
1. Finance approval within 2 weeks
2. Begin RI purchase in month 2
3. Kick off right-sizing project in Q2 (use \`resource-right-sizer.sh\`)
4. Monthly 30-minute capacity reviews to track actuals vs. forecast

---

*Generated {today} from live cluster data by \`capacity-roadmap-generator.sh\`.*
*Pod velocity window: {window_days} days. Adjust WINDOW_DAYS env var to change the lookback period.*

**Questions?**
"""

with open(output_file, 'w') as f:
    f.write(roadmap)

print(f"\033[1m\033[32m  Roadmap written to {output_file}\033[0m")
print()
PYEOF

echo ""
success "capacity-roadmap-data.txt → ${DATA_FILE}"
success "12-month-capacity-roadmap.md → ${OUTPUT_FILE}"
echo ""
info "Run 'cat ${OUTPUT_FILE}' to review your roadmap."
info "Customize MONTHLY_COST_PER_NODE and NODE_CPU if your environment differs."
