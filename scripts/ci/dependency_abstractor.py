# Identify docker/*_app, detect all valid application components,
# identify their runtime, and dispatch application work independently.

import reuse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed


print("Abstractor script Found")

root = Path(reuse.get_root())
docker_dir = root / "docker"

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

runtime_list = set(manifest_list.values())

MAX_WORKERS = 4


def line():
    return "=" * 60


def detect_valid_apps():
    """Find valid application directories under /docker."""
    if not docker_dir.exists():
        print("[dependency_abstractor.py] Docker directory NOT Found")
        return []

    valid_apps = []

    for app_dir in docker_dir.iterdir():
        if app_dir.is_dir() and app_dir.name.endswith(valid_name):
            valid_apps.append(app_dir)

    return valid_apps


def detect_app_runtime(app_dir):
    """Find all recognized manifests and their runtimes."""
    app_data = {}

    for file in app_dir.rglob("*"):
        if not file.is_file():
            continue

        runtime = manifest_list.get(file.name)

        if runtime:
            app_data[file] = runtime

    return app_data


def classify_apps():
    """Build application -> component/runtime information."""
    apps = detect_valid_apps()

    if not apps:
        return {}

    apps_dict = {}

    for app_dir in apps:
        manifests = detect_app_runtime(app_dir)

        if not manifests:
            apps_dict[app_dir] = None
            continue

        apps_dict[app_dir] = {
            "app": app_dir.name,
            "components": [
                {
                    "manifest": manifest,
                    "runtime": runtime,
                }
                for manifest, runtime in manifests.items()
            ],
        }

    return apps_dict


def build_app(app_dir, app_data):
    """
    Placeholder for the actual application build/dispatch.

    Later this function will:
        1. Select the appropriate runtime handler.
        2. Install dependencies.
        3. Run the language-specific build process.
    """

    print(
        f"[START] {app_data['app']} "
        f"({len(app_data['components'])} component(s))"
    )

    for component in app_data["components"]:
        manifest = component["manifest"]
        runtime = component["runtime"]

        if runtime not in runtime_list:
            raise RuntimeError(
                f"Unsupported runtime '{runtime}' "
                f"for {manifest}"
            )

        print(
            f"  → {manifest.name}: {runtime}"
        )

        # Later:
        # handler = get_runtime_handler(runtime)
        # handler.install_dependencies(...)
        # handler.build(...)

    return app_dir, True


def start_app_build():
    apps = classify_apps()

    print(line())

    if not apps:
        print("No valid applications found")
        print(line())
        return False

    futures = {}

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:

        for app_dir, app_data in apps.items():

            if not app_data:
                print(
                    f"❌ {app_dir}: runtime could not be detected. "
                    "Provide a valid manifest."
                )
                continue

            future = executor.submit(
                build_app,
                app_dir,
                app_data,
            )

            futures[future] = app_dir

        success = True

        for future in as_completed(futures):
            app_dir = futures[future]

            try:
                _, result = future.result()

                if result:
                    print(f"✅ {app_dir.name}: completed")

            except Exception as exc:
                success = False
                print(
                    f"❌ {app_dir.name}: failed - {exc}"
                )

    print(line())

    if success:
        print("All applications completed successfully")
    else:
        print("One or more applications failed")

    print(line())
    return success


if __name__ == "__main__":
    success = start_app_build()
    raise SystemExit(0 if success else 1)
