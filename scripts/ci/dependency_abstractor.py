# Identify docker/**, detect all valid app dirs
# detect language and call appropriate app dependency functions

import reuse
from pathlib import Path

print("Abstractor script Found")
r = Path(reuse.get_root())
docker_dir = r / "docker"
scripts_dir = r / "scripts"
valid_name = "_app"
runtime_list = ["python", "node", "java", "rust"]

def detect_valid_apps():
    if not docker_dir.exists():
        print("[dependency_abstractor.py] Docker directory NOT Found")
        return
    dirs = docker_dir.iterdir()
    valid_apps = []
    for each in dirs:
      name = each.name
      if name.endswith(valid_name) and each.is_dir():
        valid_apps.append(each)
    return valid_apps

def detect_app_runtime(x):
    contents = list(x.rglob("*"))
    for c in contents:
        if not c.is_file():
            continue

        name = c.name
        if name in {"requirements.txt", "pyproject.toml"}:
            if any(component.name.endswith(".py") for component in contents):
                return "python"

        elif name in {"pom.xml", "build.gradle", "build.gradle.kts"}:
            if any(component.name.endswith(".java") for component in contents):
                return "java"

        elif name == "package.json":
            if any(component.name.endswith((".js", ".mjs", ".cjs")) for component in contents):
                return "node"

        elif name == "Cargo.toml":
            if any(component.name.endswith(".rs") for component in contents):
                return "rust"
    return False

def classify_apps():
    apps = detect_valid_apps()
    if not apps:
      return
    apps_dict = {}
    for each in apps:
      app = detect_app_runtime(each)
      apps_dict[each] = app
    return apps_dict

def start_app_build():
    apps = classify_apps()
    n = len(apps)
    for key, app in apps.items():
      if app in runtime_list:
        print(f"{key}: {app}")
        #call_its_app_build()

start_app_build()

