# Module 8 Lightspeed API Validation Report

**Date**: 2026-04-23 16:45 UTC
**Model**: `qwen3-14b`
**API URL**: `https://litellm-prod.apps.maas.redhatworkshops.io/v1`

---

## Infrastructure Checks

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | LiteMaaS GET /v1/models (HTTP 200) | PASS | 1 model(s) returned |
| 2 | Model available: qwen3-14b | PASS | confirmed in /v1/models |

**Infra result**: 2 PASS, 0 FAIL

---

## Query Tests

| # | Lab | Query | Status | Notes |
|---|-----|-------|--------|-------|
| 1 | 8E | MCP: workloads in capacity-workshop namespace | PASS | matched: deployment, pod, Running | tools: pods_list_in_namespace, resources_list |
| 2 | 8E | MCP: node count and Ready status | PASS | matched: 3 node, 3 nodes, cpu | tools: resources_list |
| 3 | 8E | MCP: capacity headroom from live data | PASS | matched: cpu, memory, request | tools: nodes_top |

**Result**: 3 PASS, 0 FAIL, 0 SKIP
