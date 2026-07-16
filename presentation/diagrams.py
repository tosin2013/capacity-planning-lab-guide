"""
diagrams.py — Capacity Planning Workshop diagrams.

Each scene builds a Scene and calls .write().
Register every scene in the SCENES list at the bottom.
"""
from dgen import Scene, PALETTE


def rhacm_observability_architecture():
    s = Scene("r01-rhacm-observability-architecture", width=1300, height=600,
              title="RHACM Multi-Cluster Observability",
              subtitle="Prometheus per cluster, Thanos on the hub, Grafana for fleet-wide visibility")

    # Hub cluster panel
    s.panel(580, 100, 660, 300)
    s.label(910, 130, "Hub Cluster", size=13, weight="bold", color=PALETTE["svc"], anchor="middle")

    # Managed clusters (left side)
    for i, name in enumerate(["Cluster A", "Cluster B", "Cluster C"]):
        cy = 140 + i * 140
        s.box(60, cy, 220, 90, name, ["Prometheus", "metrics-collector"], kind="platform")
        s.arrow(280, cy + 45, 610, 250, kind="platform", dashed=False,
                label="metrics" if i == 0 else None)

    # Thanos
    s.box(610, 200, 200, 100, "Thanos", ["long-term storage", "cross-cluster query"], kind="data")

    # Alertmanager
    s.box(610, 330, 200, 60, "Alertmanager", kind="data")
    s.arrow(710, 300, 710, 330, kind="data")

    # Grafana
    s.box(900, 200, 200, 100, "Grafana", ["capacity dashboards", "fleet-wide view"], kind="svc")
    s.arrow(810, 250, 900, 250, kind="svc")

    # Callout panel at bottom
    s.panel(60, 490, 1180, 70)
    s.label(650, 525, "A curated metric allowlist reduces forwarded volume by 95%,",
            size=14, weight="bold", color=PALETTE["govern"], anchor="middle")
    s.label(650, 548, "cutting terabytes of Thanos storage per month across the fleet.",
            size=12, color=PALETTE["muted"], anchor="middle")

    s.write()


def hub_student_topology():
    s = Scene("r02-hub-student-topology", width=1300, height=650,
              title="Workshop Lab Topology",
              subtitle="Hub-student architecture: each student gets a dedicated OpenShift cluster")

    # Hub cluster
    s.panel(300, 90, 700, 130)
    s.label(650, 115, "Hub Cluster", size=14, weight="bold", color=PALETTE["svc"], anchor="middle")
    s.box(320, 140, 180, 60, "RHACM", ["cluster management"], kind="svc")
    s.box(560, 140, 180, 60, "Grafana", ["fleet dashboards"], kind="svc")
    s.box(800, 140, 180, 60, "Showroom", ["lab guide UI"], kind="svc")

    # Student clusters
    s.panel(60, 340, 1180, 180)
    s.label(650, 368, "Student Clusters (one per participant)", size=13, weight="bold",
            color=PALETTE["platform"], anchor="middle")

    for i in range(3):
        cx = 120 + i * 400
        name = f"Student {i+1}"
        s.box(cx, 390, 280, 100, name,
              ["3-node compact OCP", "sample apps + Prometheus", "ArgoCD workloads"],
              kind="platform")

    # RHACM import arrows (dashed)
    for i in range(3):
        tx = 260 + i * 400
        s.arrow(410, 200, tx, 390, kind="govern", dashed=True,
                label="RHACM import" if i == 0 else None)

    # SSH arrows from Showroom
    for i in range(3):
        tx = 260 + i * 400
        s.arrow(890, 200, tx, 390, kind="neutral", dashed=True,
                label="SSH" if i == 2 else None)

    # Callout
    s.label(650, 560, "Each student cluster: m7a.2xlarge (8 vCPU, 32 GB RAM) x 3 nodes",
            size=12, color=PALETTE["muted"], anchor="middle")

    s.write()


def workshop_journey():
    s = Scene("r03-workshop-journey", width=1300, height=500,
              title="Workshop Journey",
              subtitle="Progressive skill building across 9 modules")

    groups = [
        ("Foundations", "Modules 1-2", "svc",      60),
        ("Developer",   "Modules 3-4", "rest",     320),
        ("Infrastructure", "Modules 5-6", "platform", 580),
        ("Integration", "Modules 7-8", "govern",   840),
        ("AI Ops",      "Module 9",    "data",     1080),
    ]

    for name, sub, kind, x in groups:
        s.box(x, 160, 200, 120, name, [sub], kind=kind)

    # Arrows between groups
    for i in range(len(groups) - 1):
        x1 = groups[i][3] + 200
        x2 = groups[i+1][3]
        dashed = (i == 3)
        s.arrow(x1, 220, x2, 220, kind="neutral", dashed=dashed)

    # Detail labels below each group
    details = [
        (160,  ["Baseline audit", "Pod Velocity model"]),
        (420,  ["QoS classes / OOMKill", "Right-sizing activity"]),
        (680,  ["maxPods / etcd limits", "RHACM observability"]),
        (940,  ["Black Friday chaos", "12-month roadmap"]),
        (1180, ["OpenShift Lightspeed", "(optional)"]),
    ]

    for cx, lines in details:
        for j, line in enumerate(lines):
            s.label(cx, 320 + j * 22, line, size=12, color=PALETTE["muted"], anchor="middle")

    # Bottom callout
    s.panel(200, 400, 900, 60)
    s.label(650, 435, "8 hours  |  40+ code blocks  |  6 scripts  |  14 YAML manifests  |  live OpenShift clusters",
            size=13, weight="bold", color=PALETTE["neutral"], anchor="middle")

    s.write()


SCENES = [
    rhacm_observability_architecture,
    hub_student_topology,
    workshop_journey,
]

if __name__ == "__main__":
    for fn in SCENES:
        fn()
        print(f"  built {fn.__name__}")
