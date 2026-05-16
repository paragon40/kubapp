from collections import defaultdict

from sre_engine.slo_policy import SLOPolicy
from sre_engine.slo_state import SLOState


class SLOEvaluator:
    """
    Turns events into SLO decisions.
    """

    def __init__(self, policy: SLOPolicy):
        self.policy = policy
        self.state = defaultdict(SLOState)

    def ingest(self, repo: str, event_type: str):
        weight = self.policy.weights.get(event_type, 0.0)
        self.state[repo].record(weight)

    def success_rate(self, repo: str):
        return self.state[repo].success_rate()

    def is_breached(self, repo: str):
        return self.success_rate(repo) < self.policy.success_threshold

    def error_budget_remaining(self, repo: str):
        sr = self.success_rate(repo)
        return max(0.0, self.policy.success_threshold - sr)

    def burn_rate(self, repo: str):
        sr = self.success_rate(repo)
        if self.policy.success_threshold == 0:
            return 0
        used = 1 - sr
        return used / self.policy.success_threshold
