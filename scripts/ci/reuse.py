import os
from pathlib import Path
import subprocess
import time
from datetime import datetime
import uuid

def get_latest_commit_id():
    id = subprocess.run(["git", "rev-parse", "HEAD"],
         capture_output=True, text=True)
    if id.returncode != 0:
        id = f"{uuid.uuid4().hex[:5]}-uuid"
    return id.stdout.strip()[:10]

def get_timestamp():
    TS = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    return TS

def get_root():
  b = subprocess.run(["git", "rev-parse", "--show-toplevel"],
      capture_output=True, text=True)
  if b.returncode != 0:
    return False
  return b.stdout.strip()

def start_timer():
    return time.perf_counter()


def ci_log(message, level="INFO"):
    prefix = {
        "INFO": "ℹ️",
        "SUCCESS": "✅",
        "WARNING": "⚠️",
        "ERROR": "❌",
        "DEBUG": "🔍",
    }.get(level.upper(), "ℹ️")

    print(f"{prefix} {message}")

def run_command(command, cwd=None, label=None):
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            check=True,
            text=True,
            capture_output=True,
        )

        if result.stdout:
            print(result.stdout, end="")

        if result.stderr:
            print(result.stderr, end="")

        return result

    except subprocess.CalledProcessError as e:
        ci_log(
            f"{label or 'Command'} failed "
            f"(exit code {e.returncode})",
            "ERROR",
        )

        if e.stdout:
            print(e.stdout, end="")

        if e.stderr:
            print(e.stderr, end="")

        raise

