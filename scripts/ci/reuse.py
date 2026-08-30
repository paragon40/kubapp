import os
from pathlib import Path
import subprocess

def get_comit_id():
  a = subprocess.run(["git", "rev-parse", "HEAD"],
      capture_output=True, text=True)
  if b.returncode != 0:
    return False
  return a.stdout.strip()

def get_root():
  b = subprocess.run(["git", "rev-parse", "--show-toplevel"],
      capture_output=True, text=True)
  if b.returncode != 0:
    return False
  return b.stdout.strip()

print(get_root())
