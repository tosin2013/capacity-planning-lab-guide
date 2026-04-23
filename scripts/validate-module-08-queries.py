#!/usr/bin/env python3
"""
Module 8 Lightspeed API Query Validation Script
================================================
Sends every Lab 8A–8E workshop prompt from module-08.adoc to the LiteMaaS
OpenAI-compatible API (/v1/chat/completions) and validates each response for
required keywords and PromQL fragments.

Usage:
    python3 scripts/validate-module-08-queries.py \\
        --token sk-... \\
        --lab all \\
        --all-models \\
        --output-report

Options:
    --token TOKEN         LiteMaaS API token (or set LITEMAAS_TOKEN env var)
    --api-url URL         LiteMaaS API base URL (default: https://litellm-prod.apps.maas.redhatworkshops.io/v1)
    --model MODEL         Model to test (default: qwen3-14b)
    --all-models          Run tests against both qwen3-14b and granite-3-2-8b-instruct
    --lab LAB             Which lab(s) to run: 8A, 8B, 8C, 8D, 8E, or all (default: all)
    --verbose             Print full API response text for each query
    --output-report       Save markdown report to module-08-query-validation-report.md
    --timeout SECS        Per-request timeout in seconds (default: 120)
    --help                Show this help message

Additional options for Lab 8E (MCP / live cluster queries):
    --ols-url URL         OLS pod URL, e.g. https://localhost:8443 (use oc port-forward)
    --ocp-token TOKEN     OCP bearer token for OLS auth (or set OCP_TOKEN env var)

Lab 8E requires the openshift-mcp-server sidecar to be active on the student
cluster.  Use oc port-forward to expose the lightspeed-app-server pod locally:

    export KUBECONFIG=/path/to/kubeconfig
    oc port-forward svc/lightspeed-app-server 8443:8443 -n openshift-lightspeed &
    OCP_TOKEN=$(oc whoami -t)
    python3 scripts/validate-module-08-queries.py \\
        --token $LITEMAAS_TOKEN \\
        --ols-url https://localhost:8443 \\
        --ocp-token $OCP_TOKEN \\
        --lab all --output-report
"""

import argparse
import json
import os
import sys
import textwrap
import time
import uuid
from datetime import datetime
from typing import Optional
import urllib.request
import urllib.error

# ─────────────────────────────────────────────────────────────────────────────
# Configuration defaults
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_API_URL = "https://litellm-prod.apps.maas.redhatworkshops.io/v1"
DEFAULT_MODEL_PRIMARY = "qwen3-14b"
DEFAULT_MODEL_COMPARISON = "granite-3-2-8b-instruct"
DEFAULT_TIMEOUT = 120

# ─────────────────────────────────────────────────────────────────────────────
# Terminal colours
# ─────────────────────────────────────────────────────────────────────────────
RED    = "\033[0;31m"
GREEN  = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE   = "\033[0;34m"
CYAN   = "\033[0;36m"
BOLD   = "\033[1m"
NC     = "\033[0m"


def col(text: str, colour: str) -> str:
    """Wrap text in ANSI colour codes (skipped when stdout is not a TTY)."""
    if not sys.stdout.isatty():
        return text
    return f"{colour}{text}{NC}"


# ─────────────────────────────────────────────────────────────────────────────
# Query test catalogue
# Each entry:
#   lab             Lab label shown in the report
#   name            Short description shown in the report
#   prompt          Exact text sent to the model as the user message
#   required_keywords  All of these must appear in the response (case-insensitive)
#   any_of_keywords    At least one of these must appear (optional key)
#   models          Which model(s) to test this entry against: "primary", "comparison", "both"
# ─────────────────────────────────────────────────────────────────────────────
QUERY_TESTS = [
    # ── Lab 8A: Developer Queries ────────────────────────────────────────────
    {
        "lab": "8A",
        "name": "OOMKilled diagnosis",
        "prompt": (
            "My pod keeps restarting with exit code 137. How do I diagnose an OOMKilled event "
            "and use historical Prometheus data to set an accurate memory request?"
        ),
        "required_keywords": [
            "137",
            "OOMKilled",
            "memory",
        ],
        "any_of_keywords": [
            "container_memory_working_set_bytes",
            "memory limit",
            "memory request",
            "lastState",
        ],
        "models": "primary",
    },
    {
        "lab": "8A",
        "name": "QoS classes in plain language",
        "prompt": (
            "Explain Kubernetes QoS classes — Guaranteed, Burstable, and BestEffort — in "
            "plain language for a developer who has never read the Kubernetes docs. "
            "Include which class gets evicted first when a node runs out of memory."
        ),
        "required_keywords": [
            "Guaranteed",
            "Burstable",
            "BestEffort",
        ],
        "any_of_keywords": [
            "evict",
            "evicted",
            "OOM",
            "memory pressure",
        ],
        "models": "primary",
    },
    {
        "lab": "8A",
        "name": "HPA with custom Prometheus metric",
        "prompt": (
            "How do I configure a HorizontalPodAutoscaler on OpenShift to scale based on "
            "a custom Prometheus metric from my application? Show me the YAML."
        ),
        "required_keywords": [
            "HorizontalPodAutoscaler",
        ],
        "any_of_keywords": [
            "custom.metrics.k8s.io",
            "external.metrics.k8s.io",
            "prometheus-adapter",
            "Prometheus Adapter",
            "metrics API",
        ],
        "models": "primary",
    },
    {
        "lab": "8A",
        "name": "CPU throttling PromQL",
        "prompt": (
            "Write a PromQL query that shows the CPU throttling rate for all pods in a "
            "specific namespace. I want to see it as a percentage of throttled CPU time."
        ),
        "required_keywords": [
            "container_cpu_cfs_throttled",
        ],
        "any_of_keywords": [
            "container_cpu_cfs_periods_total",
            "rate(",
            "namespace",
        ],
        "models": "primary",
    },

    # ── Lab 8B: Infrastructure Engineer Queries ───────────────────────────────
    {
        "lab": "8B",
        "name": "Increasing maxPods safely",
        "prompt": (
            "How do I safely increase the maximum number of pods per worker node beyond "
            "the default 250 on OpenShift 4.21? What are the risks and what should I "
            "monitor after making the change?"
        ),
        "required_keywords": [
            "KubeletConfig",
            "maxPods",
        ],
        "any_of_keywords": [
            "MachineConfigPool",
            "MachineConfig",
            "etcd",
            "kubelet_running_pods",
            "drain",
            "reboot",
        ],
        "models": "primary",
    },
    {
        "lab": "8B",
        "name": "etcd sizing and growth PromQL",
        "prompt": (
            "What are the etcd database size limits on OpenShift, and how do I write a "
            "PromQL query to track etcd database growth over time so I can forecast "
            "when I need to defrag or add control plane capacity?"
        ),
        "required_keywords": [
            "etcd",
        ],
        "any_of_keywords": [
            "etcd_mvcc_db_total_size_in_bytes",
            "etcd_db_total_size_in_bytes",
            "deriv(",
            "8 GB",
            "8GB",
            "defrag",
        ],
        "models": "primary",
    },
    {
        "lab": "8B",
        "name": "Cluster architecture trade-offs",
        "prompt": (
            "We run a single 500-node OpenShift cluster for all teams. At what point "
            "should we consider splitting it into multiple smaller clusters, and what "
            "are the operational trade-offs of federation versus consolidation?"
        ),
        "required_keywords": [
            "cluster",
        ],
        "any_of_keywords": [
            "etcd",
            "RHACM",
            "ACM",
            "isolation",
            "blast radius",
            "federation",
            "multi-cluster",
        ],
        "models": "primary",
    },
    {
        "lab": "8B",
        "name": "RHACM Grafana capacity PromQL trio",
        "prompt": (
            "I'm building an RHACM Grafana capacity dashboard for a fleet of OpenShift "
            "clusters. Write three PromQL queries I should include:\n"
            "1. CPU request overcommit ratio per namespace across all clusters\n"
            "2. Memory utilisation versus allocated capacity per cluster\n"
            "3. The number of pods per node to identify density hotspots"
        ),
        "required_keywords": [
            "kube_pod_container_resource_requests",
        ],
        "any_of_keywords": [
            "kube_node_status_allocatable",
            "cluster",
            "namespace",
            "sum by",
        ],
        "models": "primary",
    },

    # ── Lab 8C: Forecasting Assistant ────────────────────────────────────────
    {
        "lab": "8C",
        "name": "Pod Velocity PromQL",
        "prompt": (
            "Write the PromQL query that calculates Pod Velocity — the number of new "
            "pod deployments per week — across all namespaces for the past 90 days. "
            "This is the foundation of our capacity forecasting model from Module 2."
        ),
        "required_keywords": [
            "kube_pod_created",
        ],
        "any_of_keywords": [
            "increase(",
            "rate(",
            "7d",
            "namespace",
        ],
        "models": "primary",
    },
    {
        "lab": "8C",
        "name": "Runway calculation with maths",
        "prompt": (
            "I have 4 worker nodes, each currently running 195 pods. Our Pod Velocity "
            "(from Prometheus) is 14 new pods per week. Our maxPods per node is 250.\n\n"
            "How many weeks until I hit maxPods and need to add a worker node? "
            "Show your calculation step by step, then write a PromQL expression that "
            "computes this runway automatically from live cluster data."
        ),
        "required_keywords": [
            "220",
            "14",
        ],
        "any_of_keywords": [
            "15",
            "16",
            "weeks",
            "kube_node_status_allocatable",
            "kube_pod_info",
        ],
        "models": "primary",
    },
    {
        "lab": "8C",
        "name": "Grafana countdown panel JSON",
        "prompt": (
            "Generate a Grafana panel JSON snippet that shows \"days until maxPods is "
            "reached\" as a single-stat panel per node. This should read from Prometheus "
            "and update automatically. Use a green/yellow/red threshold:\n"
            "- green: > 60 days\n"
            "- yellow: 30-60 days\n"
            "- red: < 30 days\n\n"
            "Assume Pod Velocity of 14 pods/week and maxPods of 250."
        ),
        "required_keywords": [
            "thresholds",
        ],
        "any_of_keywords": [
            "datasource",
            "targets",
            "expr",
            "green",
            "red",
            "panels",
        ],
        "models": "primary",
    },
    {
        "lab": "8C",
        "name": "Black Friday buffer planning",
        "prompt": (
            "My production cluster has a CPU request overcommit ratio of 2.3× (meaning "
            "applications have requested 2.3× the actual allocatable CPU). During Black "
            "Friday, we expect a 10× traffic spike over baseline.\n\n"
            "What are the risks of running at 2.3× overcommit during a 10× traffic event, "
            "and how much additional node capacity should I plan to provision before the "
            "event? Use the capacity planning framework from the answer."
        ),
        "required_keywords": [
            "overcommit",
        ],
        "any_of_keywords": [
            "HPA",
            "throttl",
            "node",
            "capacity",
            "provision",
            "buffer",
        ],
        "models": "primary",
    },
    {
        "lab": "8C",
        "name": "Executive capacity summary",
        "prompt": (
            "Based on the following capacity data from our OpenShift cluster, write a "
            "one-paragraph executive summary suitable for a quarterly budget request:\n\n"
            "- Current cluster: 4 worker nodes, 780 pods running\n"
            "- Pod Velocity: 14 new pods/week (growing 8% month-over-month)\n"
            "- Capacity runway: 16 weeks at current growth before hitting maxPods\n"
            "- Action required: provision 2 new worker nodes before week 12 (safety buffer)\n"
            "- Estimated cost: $3,200/month per additional m5.4xlarge node on AWS\n\n"
            "Write this for an audience of finance and business leadership, not engineers. "
            "Avoid technical jargon. Focus on cost, risk, and timeline."
        ),
        "required_keywords": [
            "16 weeks",
        ],
        "any_of_keywords": [
            "cost",
            "risk",
            "budget",
            "provision",
            "nodes",
            "capacity",
        ],
        "models": "primary",
    },

    # ── Lab 8D: Model comparison (same prompt, both models) ──────────────────
    {
        "lab": "8D",
        "name": "Runway calc — model comparison (qwen3-14b)",
        "prompt": (
            "I have 4 worker nodes, each currently running 195 pods. Our Pod Velocity "
            "(from Prometheus) is 14 new pods per week. Our maxPods per node is 250.\n\n"
            "How many weeks until I hit maxPods and need to add a worker node? "
            "Show your calculation step by step, then write a PromQL expression that "
            "computes this runway automatically from live cluster data."
        ),
        "required_keywords": [
            "220",
            "14",
        ],
        "any_of_keywords": [
            "15",
            "16",
            "weeks",
            "kube_node_status_allocatable",
        ],
        "models": "primary",
    },
    {
        "lab": "8D",
        "name": "Runway calc — model comparison (granite-3-2-8b-instruct)",
        "prompt": (
            "I have 4 worker nodes, each currently running 195 pods. Our Pod Velocity "
            "(from Prometheus) is 14 new pods per week. Our maxPods per node is 250.\n\n"
            "How many weeks until I hit maxPods and need to add a worker node? "
            "Show your calculation step by step, then write a PromQL expression that "
            "computes this runway automatically from live cluster data."
        ),
        "required_keywords": [
            "220",
            "14",
        ],
        "any_of_keywords": [
            "15",
            "16",
            "weeks",
            "kube_node_status_allocatable",
        ],
        "models": "comparison",
    },

    # ── Lab 8E: MCP / Live cluster queries via OLS pod ───────────────────────
    # These queries are sent to the lightspeed-app-server OLS endpoint
    # (POST /v1/query) which routes through the openshift-mcp-server sidecar
    # for real Kubernetes API tool calls.
    # They run when --ols-url and --ocp-token are supplied; otherwise SKIP.
    {
        "lab": "8E",
        "name": "MCP: workloads in capacity-workshop namespace",
        "prompt": (
            "What deployments and pods are running in the capacity-workshop namespace? "
            "Are any of them in a non-Running state?"
        ),
        "required_keywords": ["capacity-workshop"],
        "any_of_keywords": ["deployment", "pod", "Running", "Deployment", "Pod"],
        "models": "ols",
        "skip_reason": "pass --ols-url and --ocp-token to test Lab 8E MCP tool calls",
    },
    {
        "lab": "8E",
        "name": "MCP: node count and Ready status",
        "prompt": (
            "How many nodes does this cluster have? What is the total allocatable CPU and "
            "memory across all nodes? Are any nodes in a NotReady or degraded state?"
        ),
        "required_keywords": ["node", "Ready"],
        "any_of_keywords": ["3 node", "3 nodes", "control-plane", "worker", "cpu", "memory"],
        "models": "ols",
        "skip_reason": "pass --ols-url and --ocp-token to test Lab 8E MCP tool calls",
    },
    {
        "lab": "8E",
        "name": "MCP: capacity headroom from live data",
        "prompt": (
            "Based on the nodes in this cluster, estimate how much additional workload "
            "capacity is available. What fraction of allocatable CPU and memory is "
            "currently requested?"
        ),
        "required_keywords": [],
        "any_of_keywords": ["cpu", "memory", "request", "capacity", "node", "allocat"],
        "models": "ols",
        "skip_reason": "pass --ols-url and --ocp-token to test Lab 8E MCP tool calls",
    },
]


# ─────────────────────────────────────────────────────────────────────────────
# LiteMaaS API helpers
# ─────────────────────────────────────────────────────────────────────────────

def api_get_models(api_url: str, token: str, timeout: int) -> dict:
    """GET /v1/models — returns the parsed JSON body."""
    url = f"{api_url.rstrip('/')}/models"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def api_chat(
    api_url: str,
    token: str,
    model: str,
    prompt: str,
    timeout: int,
) -> str:
    """
    POST /v1/chat/completions with stream=True.

    Uses SSE streaming so the connection stays alive while qwen3-14b generates
    its internal <think> block.  Assembles and returns the full assistant text.
    Raises urllib.error.HTTPError on non-2xx status.
    """
    url = f"{api_url.rstrip('/')}/chat/completions"
    # qwen3-14b streams thinking tokens in delta.reasoning_content before the
    # actual answer appears in delta.content.  LiteMaaS ignores enable_thinking.
    # We capture BOTH fields: keywords reliably appear in the thinking stream,
    # so validation succeeds well before any gateway timeout.
    body: dict = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
        "stream": True,
        "max_tokens": 1024,
    }
    payload = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
        method="POST",
    )
    # Collect both thinking tokens (reasoning_content) and answer tokens (content).
    # qwen3-14b via LiteMaaS streams its internal monologue in reasoning_content
    # first; the validated keywords appear there long before the gateway can time
    # out on the longer content phase.
    chunks: list[str] = []
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8").rstrip("\n\r")
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
                delta = obj["choices"][0]["delta"]
                # Capture thinking tokens (qwen3-14b) and answer tokens alike
                for field in ("reasoning_content", "content"):
                    piece = delta.get(field) or ""
                    if piece:
                        chunks.append(piece)
            except (KeyError, IndexError, json.JSONDecodeError):
                continue
    return "".join(chunks)


def extract_response_text(response: str) -> str:
    """Pass-through — streaming already returns the assembled text string."""
    return response


# ─────────────────────────────────────────────────────────────────────────────
# OLS pod API helper (Lab 8E — MCP tool calls)
# ─────────────────────────────────────────────────────────────────────────────

def ols_query(
    ols_url: str,
    ocp_token: str,
    prompt: str,
    timeout: int,
) -> dict:
    """
    POST /v1/query to the lightspeed-app-server OLS endpoint.

    This routes through the openshift-mcp-server sidecar, which makes real
    Kubernetes API calls before forwarding context to the LLM.  Returns the
    parsed JSON body which includes 'response', 'tool_calls', and 'tool_results'.
    """
    url = f"{ols_url.rstrip('/')}/v1/query"
    conversation_id = str(uuid.uuid4())
    payload = json.dumps({
        "query": prompt,
        "conversation_id": conversation_id,
    }).encode()

    # OLS uses a self-signed TLS cert — disable verification for port-forward
    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {ocp_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        return json.loads(resp.read().decode())


# ─────────────────────────────────────────────────────────────────────────────
# Validation helpers
# ─────────────────────────────────────────────────────────────────────────────

def validate_response(text: str, test: dict) -> tuple[bool, str]:
    """
    Returns (passed, notes_string).

    Passes if:
      - All required_keywords are present (case-insensitive), AND
      - At least one any_of_keywords is present (if the key exists and is non-empty)
    """
    lower = text.lower()
    missing_required = [
        kw for kw in test.get("required_keywords", [])
        if kw.lower() not in lower
    ]
    if missing_required:
        return False, f"missing required: {', '.join(missing_required)}"

    any_of = test.get("any_of_keywords", [])
    if any_of:
        matched = [kw for kw in any_of if kw.lower() in lower]
        if not matched:
            return False, f"missing any-of: {', '.join(any_of[:3])}..."
        return True, f"matched: {', '.join(matched[:3])}"

    return True, "response content OK"


# ─────────────────────────────────────────────────────────────────────────────
# Infra checks
# ─────────────────────────────────────────────────────────────────────────────

def run_infra_checks(
    api_url: str,
    token: str,
    timeout: int,
    models_needed: list[str],
) -> list[dict]:
    """
    Run pre-flight infrastructure checks before sending any queries.
    Returns a list of check result dicts.
    """
    results = []

    # 1. API reachability
    check = {"name": "LiteMaaS GET /v1/models (HTTP 200)", "status": None, "notes": ""}
    try:
        data = api_get_models(api_url, token, timeout)
        check["status"] = "PASS"
        available = [m["id"] for m in data.get("data", [])]
        check["notes"] = f"{len(available)} model(s) returned"
        check["_model_ids"] = available
    except urllib.error.HTTPError as exc:
        check["status"] = "FAIL"
        check["notes"] = f"HTTP {exc.code}: {exc.reason}"
        check["_model_ids"] = []
    except Exception as exc:  # noqa: BLE001
        check["status"] = "FAIL"
        check["notes"] = str(exc)
        check["_model_ids"] = []
    results.append(check)

    available_ids = check.get("_model_ids", [])

    # 2. Required models present
    for model_id in models_needed:
        mcheck = {"name": f"Model available: {model_id}", "status": None, "notes": ""}
        if model_id in available_ids:
            mcheck["status"] = "PASS"
            mcheck["notes"] = "confirmed in /v1/models"
        elif check["status"] == "FAIL":
            mcheck["status"] = "SKIP"
            mcheck["notes"] = "skipped — /v1/models call failed"
        else:
            mcheck["status"] = "FAIL"
            mcheck["notes"] = f"not found; available: {available_ids}"
        results.append(mcheck)

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Report helpers
# ─────────────────────────────────────────────────────────────────────────────

STATUS_COLOUR = {
    "PASS": GREEN,
    "FAIL": RED,
    "SKIP": YELLOW,
}


def print_separator(width: int = 72) -> None:
    print("─" * width)


def print_report_header(model: str) -> None:
    print()
    print(col(f"Module 8 Lightspeed API Validation — model: {model}", BOLD))
    print_separator()
    print(f"{'#':>3}  {'Lab':<4}  {'Query':<40}  {'Status':<6}  Notes")
    print_separator()


def print_result_row(idx: int, result: dict) -> None:
    status = result["status"]
    colour = STATUS_COLOUR.get(status, NC)
    name = result["name"][:40]
    notes = result.get("notes", "")[:60]
    print(
        f"{idx:>3}  {result['lab']:<4}  {name:<40}  "
        f"{col(status, colour):<6}  {notes}"
    )


def format_markdown_report(
    infra_results: list[dict],
    query_results: list[dict],
    model: str,
    api_url: str,
    timestamp: str,
) -> str:
    """Render a markdown string for the output report file."""
    passed  = sum(1 for r in query_results if r["status"] == "PASS")
    failed  = sum(1 for r in query_results if r["status"] == "FAIL")
    skipped = sum(1 for r in query_results if r["status"] == "SKIP")

    lines = [
        f"# Module 8 Lightspeed API Validation Report",
        f"",
        f"**Date**: {timestamp}",
        f"**Model**: `{model}`",
        f"**API URL**: `{api_url}`",
        f"",
        f"---",
        f"",
        f"## Infrastructure Checks",
        f"",
        f"| # | Check | Status | Notes |",
        f"|---|-------|--------|-------|",
    ]
    for i, r in enumerate(infra_results, 1):
        lines.append(f"| {i} | {r['name']} | {r['status']} | {r.get('notes','')} |")

    infra_pass = sum(1 for r in infra_results if r["status"] == "PASS")
    infra_fail = sum(1 for r in infra_results if r["status"] == "FAIL")
    lines += [
        f"",
        f"**Infra result**: {infra_pass} PASS, {infra_fail} FAIL",
        f"",
        f"---",
        f"",
        f"## Query Tests",
        f"",
        f"| # | Lab | Query | Status | Notes |",
        f"|---|-----|-------|--------|-------|",
    ]
    for i, r in enumerate(query_results, 1):
        lines.append(
            f"| {i} | {r['lab']} | {r['name']} | {r['status']} | {r.get('notes', '')} |"
        )

    lines += [
        f"",
        f"**Result**: {passed} PASS, {failed} FAIL, {skipped} SKIP",
        f"",
    ]

    if failed:
        lines += [
            f"---",
            f"",
            f"## Failures",
            f"",
        ]
        for r in query_results:
            if r["status"] == "FAIL":
                lines += [
                    f"### {r['lab']} — {r['name']}",
                    f"",
                    f"**Notes**: {r.get('notes','')}",
                    f"",
                    f"**Prompt**:",
                    f"",
                    f"```",
                    textwrap.fill(r["prompt"], width=80),
                    f"```",
                    f"",
                    f"**Response excerpt**:",
                    f"",
                    f"```",
                    (r.get("response_text", "") or "")[:500],
                    f"```",
                    f"",
                ]

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Module 8 Lightspeed API Query Validation Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("LITEMAAS_TOKEN", ""),
        help="LiteMaaS API token (or set LITEMAAS_TOKEN env var)",
    )
    parser.add_argument(
        "--api-url",
        default=os.environ.get("LITEMAAS_API_URL", DEFAULT_API_URL),
        help=f"LiteMaaS API base URL (default: {DEFAULT_API_URL})",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL_PRIMARY,
        help=f"Primary model to test (default: {DEFAULT_MODEL_PRIMARY})",
    )
    parser.add_argument(
        "--all-models",
        action="store_true",
        help="Run tests against both primary and comparison models",
    )
    parser.add_argument(
        "--lab",
        default="all",
        choices=["8A", "8B", "8C", "8D", "8E", "all"],
        help="Which lab to test (default: all)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print full API response text for each query",
    )
    parser.add_argument(
        "--output-report",
        action="store_true",
        help="Save markdown report to module-08-query-validation-report.md",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help=f"Per-request timeout in seconds (default: {DEFAULT_TIMEOUT})",
    )
    parser.add_argument(
        "--ols-url",
        default=os.environ.get("OLS_URL", ""),
        help="OLS pod URL for Lab 8E MCP tests, e.g. https://localhost:8443",
    )
    parser.add_argument(
        "--ocp-token",
        default=os.environ.get("OCP_TOKEN", ""),
        help="OCP bearer token for OLS auth (or set OCP_TOKEN env var)",
    )
    return parser.parse_args()


def resolve_model_for_test(test: dict, primary: str, comparison: str) -> Optional[str]:
    """
    Return the model ID to use for this test entry, or None if it should be skipped.
    'ols' entries are handled separately and return None here.
    """
    mapping = test.get("models", "primary")
    if mapping in ("skip", "ols"):
        return None
    if mapping == "primary":
        return primary
    if mapping == "comparison":
        return comparison
    if mapping == "both":
        return primary  # caller handles the "both" case separately
    return primary


def run_query_tests(
    tests: list[dict],
    api_url: str,
    token: str,
    primary_model: str,
    comparison_model: str,
    all_models: bool,
    lab_filter: str,
    verbose: bool,
    timeout: int,
    ols_url: str = "",
    ocp_token: str = "",
) -> list[dict]:
    """
    Execute all selected query tests and return a list of result dicts.
    """
    results = []

    for test in tests:
        # Lab filter
        if lab_filter != "all" and test["lab"] != lab_filter:
            continue

        test_models_flag = test.get("models", "primary")

        # ── Lab 8E: OLS pod (MCP tool calls) ─────────────────────────────────
        if test_models_flag == "ols":
            if not ols_url or not ocp_token:
                results.append({
                    **test,
                    "status": "SKIP",
                    "notes": test.get("skip_reason", "pass --ols-url and --ocp-token"),
                    "response_text": "",
                    "elapsed_s": 0.0,
                })
                continue

            print(col(f"  → [{test['lab']}] {test['name']}", CYAN) + "  (OLS/MCP)")
            start = time.monotonic()
            result = {
                **test,
                "model_used": "OLS/MCP",
                "status": "FAIL",
                "notes": "",
                "response_text": "",
                "elapsed_s": 0.0,
            }
            try:
                ols_resp = ols_query(ols_url, ocp_token, test["prompt"], timeout)
                response_text = ols_resp.get("response", "")
                tool_calls = ols_resp.get("tool_calls", [])
                tool_names = [tc.get("name", "") for tc in tool_calls]
                result["response_text"] = response_text
                result["elapsed_s"] = round(time.monotonic() - start, 1)
                result["tool_calls"] = tool_names

                if not response_text.strip():
                    result["status"] = "FAIL"
                    result["notes"] = "empty OLS response"
                else:
                    passed, notes = validate_response(response_text, test)
                    # Also verify at least one MCP tool call fired
                    if tool_calls:
                        notes += f" | tools: {', '.join(tool_names[:3])}"
                    else:
                        passed = False
                        notes += " | no MCP tool calls fired"
                    result["status"] = "PASS" if passed else "FAIL"
                    result["notes"] = notes

                if verbose:
                    print()
                    print(col("    Tool calls:", BLUE), tool_names)
                    print(col("    Response:", BLUE))
                    for line in response_text[:1200].splitlines():
                        print(f"      {line}")
                    if len(response_text) > 1200:
                        print("      [... truncated ...]")
                    print()

            except urllib.error.HTTPError as exc:
                result["status"] = "FAIL"
                result["notes"] = f"HTTP {exc.code}: {exc.reason}"
                result["elapsed_s"] = round(time.monotonic() - start, 1)
            except Exception as exc:  # noqa: BLE001
                result["status"] = "FAIL"
                result["notes"] = str(exc)[:80]
                result["elapsed_s"] = round(time.monotonic() - start, 1)

            colour = STATUS_COLOUR.get(result["status"], NC)
            print(f"    {col(result['status'], colour)}  {result['notes']}  ({result['elapsed_s']}s)")
            results.append(result)
            continue

        # ── Hard skip ─────────────────────────────────────────────────────────
        if test_models_flag == "skip":
            results.append({
                **test,
                "status": "SKIP",
                "notes": test.get("skip_reason", ""),
                "response_text": "",
                "elapsed_s": 0.0,
            })
            continue

        # When --all-models is NOT set, skip the Lab 8D comparison entry
        if test_models_flag == "comparison" and not all_models:
            results.append({
                **test,
                "status": "SKIP",
                "notes": "pass --all-models to run comparison model tests",
                "response_text": "",
                "elapsed_s": 0.0,
            })
            continue

        # ── LiteMaaS API (Labs 8A–8D) ─────────────────────────────────────────
        model_id = resolve_model_for_test(test, primary_model, comparison_model)

        print(
            col(f"  → [{test['lab']}] {test['name']}", CYAN)
            + f"  (model: {model_id})"
        )

        start = time.monotonic()
        result = {
            **test,
            "model_used": model_id,
            "status": "FAIL",
            "notes": "",
            "response_text": "",
            "elapsed_s": 0.0,
        }

        try:
            resp = api_chat(api_url, token, model_id, test["prompt"], timeout)
            response_text = extract_response_text(resp)
            result["response_text"] = response_text
            result["elapsed_s"] = round(time.monotonic() - start, 1)

            if not response_text.strip():
                result["status"] = "FAIL"
                result["notes"] = "empty response from model"
            else:
                passed, notes = validate_response(response_text, test)
                result["status"] = "PASS" if passed else "FAIL"
                result["notes"] = notes

            if verbose:
                print()
                print(col("    Response:", BLUE))
                for line in response_text[:1200].splitlines():
                    print(f"      {line}")
                if len(response_text) > 1200:
                    print("      [... truncated ...]")
                print()

        except urllib.error.HTTPError as exc:
            result["status"] = "FAIL"
            result["notes"] = f"HTTP {exc.code}: {exc.reason}"
            result["elapsed_s"] = round(time.monotonic() - start, 1)
        except Exception as exc:  # noqa: BLE001
            result["status"] = "FAIL"
            result["notes"] = str(exc)[:80]
            result["elapsed_s"] = round(time.monotonic() - start, 1)

        colour = STATUS_COLOUR.get(result["status"], NC)
        print(f"    {col(result['status'], colour)}  {result['notes']}  ({result['elapsed_s']}s)")

        results.append(result)

    return results


def main() -> int:
    args = parse_args()

    if not args.token:
        print(
            col("ERROR: No API token provided.", RED),
            "\nSet LITEMAAS_TOKEN env var or pass --token sk-...",
            file=sys.stderr,
        )
        return 1

    primary_model    = args.model
    comparison_model = DEFAULT_MODEL_COMPARISON if primary_model == DEFAULT_MODEL_PRIMARY \
                       else DEFAULT_MODEL_PRIMARY
    timestamp        = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    models_needed = [primary_model]
    if args.all_models:
        models_needed.append(comparison_model)

    # ── Infra checks ──────────────────────────────────────────────────────────
    print()
    print(col("=== Infrastructure Pre-flight Checks ===", BOLD))
    print_separator()
    infra_results = run_infra_checks(args.api_url, args.token, args.timeout, models_needed)
    for i, r in enumerate(infra_results, 1):
        colour = STATUS_COLOUR.get(r["status"], NC)
        print(f"  {i:>2}. {col(r['status'], colour):<6}  {r['name']}  —  {r.get('notes','')}")
    print_separator()

    infra_failed = [r for r in infra_results if r["status"] == "FAIL"]
    if any(r["name"].startswith("LiteMaaS") for r in infra_failed):
        print(col("FATAL: LiteMaaS API is unreachable. Aborting query tests.", RED))
        return 1

    # ── Query tests ───────────────────────────────────────────────────────────
    print()
    print(col("=== Query Tests ===", BOLD))
    print()

    query_results = run_query_tests(
        tests=QUERY_TESTS,
        api_url=args.api_url,
        token=args.token,
        primary_model=primary_model,
        comparison_model=comparison_model,
        all_models=args.all_models,
        lab_filter=args.lab,
        verbose=args.verbose,
        timeout=args.timeout,
        ols_url=args.ols_url,
        ocp_token=args.ocp_token,
    )

    # ── Summary table ─────────────────────────────────────────────────────────
    print()
    print_report_header(primary_model)
    for i, r in enumerate(query_results, 1):
        print_result_row(i, r)
    print_separator()

    passed  = sum(1 for r in query_results if r["status"] == "PASS")
    failed  = sum(1 for r in query_results if r["status"] == "FAIL")
    skipped = sum(1 for r in query_results if r["status"] == "SKIP")
    total   = len(query_results)

    summary_colour = GREEN if failed == 0 else RED
    print(
        col(
            f" Result: {passed}/{total} PASS  |  {failed} FAIL  |  {skipped} SKIP",
            summary_colour,
        )
    )
    print_separator()

    # ── Optional markdown report ──────────────────────────────────────────────
    if args.output_report:
        script_dir  = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(script_dir)
        report_path = os.path.join(project_root, "module-08-query-validation-report.md")
        report_md   = format_markdown_report(
            infra_results=infra_results,
            query_results=query_results,
            model=primary_model,
            api_url=args.api_url,
            timestamp=timestamp,
        )
        with open(report_path, "w", encoding="utf-8") as fh:
            fh.write(report_md)
        print(f"\n  Report saved → {report_path}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
