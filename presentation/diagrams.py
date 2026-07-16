"""
diagrams.py — capacity-planning workshop diagrams.

Each scene is a function that builds a Scene and calls .write().
Register every scene in the SCENES list at the bottom.
"""
from dgen import Scene, PALETTE


def hub_student_architecture():
    s = Scene("r01-hub-student-architecture", width=1300, height=640,
              title="Hub-Student Workshop Architecture",
              subtitle="One hub cluster manages N student clusters via RHACM Observability.")

    # Hub cluster (top center)
    s.box(370, 100, 560, 150, "Hub Cluster", [
        "RHACM 2.16 + Observability",
        "Thanos (long-term metric storage)",
        "Grafana (capacity dashboards)",
        "Showroom (lab guide)",
    ], kind="platform")

    # Student clusters (bottom row)
    s.box(60, 430, 310, 120, "Student Cluster 1", [
        "3-node compact OCP 4.21",
        "Prometheus + metrics-collector",
        "Sample workloads (ArgoCD)",
    ], kind="svc")

    s.box(495, 430, 310, 120, "Student Cluster 2", [
        "3-node compact OCP 4.21",
        "Prometheus + metrics-collector",
        "Sample workloads (ArgoCD)",
    ], kind="svc")

    s.box(930, 430, 310, 120, "Student Cluster N", [
        "3-node compact OCP 4.21",
        "Prometheus + metrics-collector",
        "Sample workloads (ArgoCD)",
    ], kind="svc")

    # Arrows from students up to hub (metrics flow)
    s.arrow(215, 430, 530, 250, kind="svc", label="metrics")
    s.arrow(650, 430, 650, 250, kind="svc", label="metrics")
    s.arrow(1085, 430, 770, 250, kind="svc", label="metrics")

    # RHACM import label
    s.label(650, 350, "RHACM Import + Observability Pipeline", size=13,
            anchor="middle", color=PALETTE["muted"])

    # Ellipsis between cluster 2 and N
    s.label(870, 490, "...", size=28, weight="bold", anchor="middle",
            color=PALETTE["muted"])

    s.write()


def observability_data_flow():
    s = Scene("r02-observability-data-flow", width=1300, height=580,
              title="RHACM Observability Data Flow",
              subtitle="Metrics pipeline from managed clusters to centralized dashboards.")

    # Managed-cluster panel (left)
    s.panel(40, 110, 370, 360)
    s.label(225, 138, "Managed Cluster", size=14, weight="bold",
            anchor="middle", color=PALETTE["svc"])

    s.box(80, 165, 290, 80, "Prometheus", [
        "scrapes pod / node metrics",
        "per-cluster retention",
    ], kind="svc")

    s.box(80, 290, 290, 80, "metrics-collector", [
        "filters via custom allowlist",
        "forwards selected metrics",
    ], kind="svc")

    s.arrow(225, 245, 225, 290, kind="neutral", label="all metrics")

    # Hub-cluster panel (right)
    s.panel(490, 110, 770, 360)
    s.label(875, 138, "Hub Cluster", size=14, weight="bold",
            anchor="middle", color=PALETTE["platform"])

    s.box(530, 175, 260, 90, "Thanos", [
        "Receive + Query + Store",
        "cross-cluster aggregation",
        "long-term retention",
    ], kind="platform")

    s.box(880, 165, 230, 80, "Grafana", [
        "capacity dashboards",
        "showback / chargeback",
    ], kind="platform")

    s.box(880, 290, 230, 80, "Alertmanager", [
        "threshold-based alerts",
        "capacity warnings",
    ], kind="danger")

    s.box(530, 385, 260, 65, "S3 Object Storage", [
        "compacted metric blocks",
    ], kind="data")

    # Data flow arrows
    s.arrow(370, 330, 530, 220, kind="svc", label="HTTPS push")
    s.arrow(790, 210, 880, 200, kind="neutral", label="query")
    s.arrow(790, 240, 880, 320, kind="neutral", label="alerts")
    s.arrow(660, 265, 660, 385, kind="data", label="compact")

    s.write()


def workshop_journey():
    s = Scene("r03-workshop-journey", width=1300, height=540,
              title="Workshop Journey: Reactive to Strategic",
              subtitle="Nine modules build capacity planning maturity across a full day.")

    bw, bh = 200, 80
    gap = 25
    y_top = 130

    # Top row: Modules 1-5
    modules_top = [
        ("M1", "Planning Horizons", "svc"),
        ("M2", "Forecasting Math", "svc"),
        ("M3", "Developer Track", "svc"),
        ("M4", "Right-Sizing", "platform"),
        ("M5", "Fleet Architecture", "platform"),
    ]

    x_start = 50
    for i, (code, label, kind) in enumerate(modules_top):
        x = x_start + i * (bw + gap)
        s.box(x, y_top, bw, bh, code, [label], kind=kind)

    # Arrows between top row
    for i in range(4):
        x1 = x_start + i * (bw + gap) + bw
        x2 = x_start + (i + 1) * (bw + gap)
        s.arrow(x1, y_top + bh // 2, x2, y_top + bh // 2, kind="neutral")

    # Bottom row: Modules 6-9
    y_bot = 310
    modules_bot = [
        ("M6", "Fleet Observability", "platform"),
        ("M7", "Black Friday", "danger"),
        ("M8", "Strategic Roadmap", "govern"),
        ("M9", "AI-Assisted Ops", "govern"),
    ]

    x_bot_start = 175
    for i, (code, label, kind) in enumerate(modules_bot):
        x = x_bot_start + i * (bw + gap)
        s.box(x, y_bot, bw, bh, code, [label], kind=kind)

    # Connector from end of top row down to start of bottom row
    s.arrow(x_start + 4 * (bw + gap) + bw, y_top + bh // 2,
            x_bot_start, y_bot + bh // 2, kind="neutral", dashed=True)

    # Arrows between bottom row
    for i in range(3):
        x1 = x_bot_start + i * (bw + gap) + bw
        x2 = x_bot_start + (i + 1) * (bw + gap)
        s.arrow(x1, y_bot + bh // 2, x2, y_bot + bh // 2, kind="neutral")

    # Maturity progression at bottom
    s.chip(50, 460, "REACTIVE", kind="danger")
    s.arrow(170, 471, 1090, 471, kind="neutral")
    s.chip(1090, 460, "STRATEGIC", kind="govern")

    s.label(630, 500, "8 hours  |  full-day hands-on workshop", size=12,
            anchor="middle", color=PALETTE["muted"])

    s.write()


def maturity_model():
    s = Scene("r04-maturity-model", width=1200, height=580,
              title="Capacity Planning Maturity Model",
              subtitle="Where are you today? Where does this workshop take you?")

    levels = [
        ("Level 1", "Reactive", [
            "No baselines or forecasts",
            "Ad-hoc firefighting",
            "Surprise outages",
        ], "danger"),
        ("Level 2", "Tactical", [
            "Basic monitoring in place",
            "Manual capacity forecasts",
            "90-day audit cycle",
        ], "svc"),
        ("Level 3", "Operational", [
            "Pod Velocity forecasting",
            "Multi-cluster dashboards",
            "Quarterly capacity roadmaps",
        ], "platform"),
        ("Level 4", "Strategic", [
            "AI-assisted operations",
            "FinOps integration",
            "Multi-year commitment planning",
        ], "govern"),
    ]

    bw = 230
    gap = 35
    x_start = 55

    for i, (level, name, bullets, kind) in enumerate(levels):
        x = x_start + i * (bw + gap)
        y = 340 - i * 55
        h = 105 + i * 10
        s.box(x, y, bw, h, f"{level}: {name}", bullets, kind=kind)

    # Workshop coverage callout
    s.panel(55, 475, 795, 55)
    s.label(452, 508, "This workshop: Level 1 → Level 3", size=14,
            weight="bold", anchor="middle", color=PALETTE["platform"])

    s.write()


SCENES = [
    hub_student_architecture,
    observability_data_flow,
    workshop_journey,
    maturity_model,
]

if __name__ == "__main__":
    for fn in SCENES:
        fn()
        print(f"  built {fn.__name__}")
