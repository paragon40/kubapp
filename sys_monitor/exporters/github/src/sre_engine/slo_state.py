from collections import deque
import time


class SLOState:
    """
    Time-windowed SLI state buffer.

    Stores raw reliability signals (success/failure events)
    for SLO evaluation in the worker layer.
    """

    def __init__(self):
        # stores (timestamp, success_flag)
        self.events = deque()

    # --------------------------------------------------------
    # INGEST EVENT
    # --------------------------------------------------------
    def record(self, success: bool):
        self.events.append((time.time(), 1 if success else 0))

    # --------------------------------------------------------
    # PRUNE OLD EVENTS (ROLLING WINDOW)
    # --------------------------------------------------------
    def prune(self, window_seconds: int):
        now = time.time()

        while self.events and (now - self.events[0][0]) > window_seconds:
            self.events.popleft()

    # --------------------------------------------------------
    # SLI COMPUTATION
    # --------------------------------------------------------
    def success_rate(self):
        if not self.events:
            return 1.0

        total = len(self.events)
        success = sum(v for _, v in self.events)

        return success / total

    # --------------------------------------------------------
    # RAW METRICS HELPERS
    # --------------------------------------------------------
    def total_events(self):
        return len(self.events)

    def failure_count(self):
        return sum(1 for _, v in self.events if v == 0)

    def success_count(self):
        return sum(1 for _, v in self.events if v == 1)

