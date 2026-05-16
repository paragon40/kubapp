from prometheus_client import Gauge


# ============================================================
# PROMETHEUS METRICS (OUTPUT ONLY)
# ============================================================

github_health_score = Gauge(
    "github_health_score",
    "SRE Health Score (0-100 based on SLO + burn rate)",
    ["repo"]
)

github_anomaly_flag = Gauge(
    "github_anomaly_flag",
    "SRE anomaly detection flag (1 = anomaly detected)",
    ["repo", "type"]
)

slo_success_rate = Gauge(
    "slo_success_rate",
    "Service Level Objective success rate",
    ["repo"]
)

error_budget_burn_rate = Gauge(
    "error_budget_burn_rate",
    "Error budget burn rate (SRE standard)",
    ["repo"]
)

error_budget_remaining = Gauge(
    "error_budget_remaining",
    "Remaining error budget percentage",
    ["repo"]
)


# ============================================================
# HEALTH SCORING LOGIC (PURE FUNCTION LAYER)
# ============================================================

def compute_health_score(sli: float, burn_rate: float) -> float:
    """
    Converts SLI + burn rate into a 0–100 health score.

    SRE interpretation:
    - SLI is primary signal
    - Burn rate is degradation amplifier
    """

    base = sli * 100

    # Penalize excessive burn rate
    if burn_rate > 1.0:
        penalty = min(50, (burn_rate - 1.0) * 50)
    else:
        penalty = 0

    score = base - penalty

    return max(0.0, min(100.0, score))


def detect_anomaly(sli: float, burn_rate: float) -> bool:
    """
    SRE anomaly rules:

    - SLI below 0.90 → degradation
    - burn rate > 1 → fast budget consumption
    """

    if sli < 0.90:
        return True

    if burn_rate > 1.0:
        return True

    return False
