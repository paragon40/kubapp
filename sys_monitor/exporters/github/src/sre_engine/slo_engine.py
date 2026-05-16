from dataclasses import dataclass


@dataclass
class ErrorBudgetState:
    """
    PURE STATE HOLDER (no business logic).
    """
    total: int = 0
    good: int = 0

    def record(self, value: float):
        self.total += 1
        if value > 0:
            self.good += 1

    def success_rate(self):
        if self.total == 0:
            return 1.0
        return self.good / self.total
