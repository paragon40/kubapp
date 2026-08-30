# Identify docker/**, detect all valid app dirs
# detect language and call appropriate app dependency functions

import reuse
from pathlib import Path

print("Abstractor script Found")

r = Path(reuse.get_root())
docker_dir = r / "docker"
scripts_dir = r / "scripts"

valid_name = "_app"
manifest_list = {
    "requirements.txt": "python",
    "pyproject.toml": "python",
    "pom.xml": "java",
    "build.gradle": "java",
    "build.gradle.kts": "java",
    "package.json": "node",
    "go.mod": "golang",
}


def line():
    return "=" * 60


def detect_valid_apps():
    if not docker_dir.exists():
        print("[dependency_abstractor.py] Docker directory NOT Found")
        return []

    valid_apps = []

    for each in docker_dir.iterdir():
        if each.name.endswith(valid_name) and each.is_dir():
            valid_apps.append(each)

    return valid_apps


def detect_app_runtime(app_dir):
    app_data = {}

    for file in app_dir.rglob("*"):
        if not file.is_file():
            continue

        runtime = manifest_list.get(file.name)

        if runtime:
            app_data[file] = runtime

    return app_data


def classify_apps():
    apps = detect_valid_apps()

    if not apps:
        return {}

    apps_dict = {}

    for app_dir in apps:
        manifests = detect_app_runtime(app_dir)

        if not manifests:
            apps_dict[app_dir] = None
            continue
        a = app_dir.name
        m = next(iter(manifests))
        r = manifests[m]
        manifests = {"app": a, "manifest": m.name, "runtime": r}
        apps_dict[app_dir] = manifests
    return apps_dict


def start_app_build():
    apps = classify_apps()

    print(line())
    if not apps:
        print("No valid applications found")
        print(line())
        return

    for app_dir, manifests in apps.items():
        if not manifests:
            print(
                f"❌ {app_dir}: runtime could not be detected. "
                "Provide a valid manifest."
            )
            continue

        print(f"Application: {app_dir} --> {manifests}")
            # call_its_app_build()
    print(line())

start_app_build()
