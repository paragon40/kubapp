import numpy as np
from collections import deque

class AnomalyDetector:
    def __init__(self, window_size=20):
        self.window = deque(maxlen=window_size)

    def add(self, value):
        self.window.append(value)

    def is_anomaly(self, value):
        if len(self.window) < 5:
            return False

        mean = np.mean(self.window)
        std = np.std(self.window)

        if std == 0:
            return False

        z_score = (value - mean) / std
        return abs(z_score) > 2.5
