# Identify docker/*_app, detect all valid application components,
# identify their runtime, and dispatch application work independently.
import reuse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from python_file import PythonHandler
# import PythonHandler, JavaHandler, GoHandler, NodeHandler

print("Abstractor script Found")
root = Path(reuse.get_root())
docker_dir = root / "docker"

valid_name = "_app"
platform_filename = "kubapp.yml"
platform_secrets_filename = "secrets.yml"
manifest_list = {
    "requirements.txt": "python",
    "pyproject.toml": "python",
    "pom.xml": "java",
    "build.gradle": "java",
    "build.gradle.kts": "java",
    "package.json": "node",
    "go.mod": "golang",
}

HANDLERS = {
    "python": PythonHandler, }
#    "node": NodeHandler,
#    "java": JavaHandler,
#    "golang": GoHandler,
#}

runtime_list = set(manifest_list.values())
MAX_WORKERS = 4


def line():
    return "=" * 60

def detect_valid_apps():
    if not docker_dir.exists():
        print("[dependency_abstractor.py] Docker directory NOT Found")
        return []

    valid_apps = []
    for app_dir in docker_dir.iterdir():
        if app_dir.is_dir() and app_dir.name.endswith(valid_name):
            valid_apps.append(app_dir)

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


def is_file_okay(path):
    return path.is_file() and bool(path.read_text().strip())

def classify_apps():
    apps = detect_valid_apps()
    if not apps:
        return {}

    apps_dict = {}
    for app_dir in apps:
        manifests = detect_app_runtime(app_dir)
        if not manifests:
            print(line())
            print("ATTENTION NEEDED!")
            print(
                f"❌ UNKNOWN app runtime could not be detected. "
                f"Provide a valid manifest at {app_dir}."
            )
            print(line())
            continue

        components = []
        for manifest, runtime in manifests.items():
            #print(manifest)
            component_dir = manifest.parent
            dockerfile = component_dir / "Dockerfile"
            platform_file = component_dir / platform_filename
            secret_file = component_dir / platform_secrets_filename
            manifest_okay = is_file_okay(manifest)
            dockerfile_okay = is_file_okay(dockerfile)
            platform_file_okay = is_file_okay(platform_file)
            platform_secrets_okay = is_file_okay(secret_file)

            if not manifest_okay:
                continue
            if not dockerfile_okay:
                dockerfile = False
            if not platform_file_okay:
                platform_file = False
            if not platform_secrets_okay:
                secret_file = False

            components.append(
                {
                    "manifest": manifest,
                    "runtime": runtime,
                    "Dockerfile": dockerfile,
                    "platform_file": platform_file,
                    "app_secrets": secret_file,
                }
            )
        if not components:
            print(line())
            print(
                f"❌ {app_dir.name}: no valid components found "
                f"App manifest MUST be Provided"
            )
            print(line())
            continue

        apps_dict[app_dir] = {
            "app": app_dir.name,
            "components": components,
        }

        #print(f"MANI: {manifests}")
        #for component in components:
        #    print(f"Component: {component['manifest']}")
        #    print(f"Runtime: {component['runtime']}")
        #    print(f"Dockerfile: {component['Dockerfile']}")
    return apps_dict


def get_runtime_handler(runtime):
    return HANDLERS.get(runtime)

def build_app(app_dir, app_data):
    for component in app_data["components"]:
        manifest = component["manifest"]
        runtime = component["runtime"]
        dockerfile = component["Dockerfile"]
        platform_file = component["platform_file"]

        app = manifest.parent.name
        if runtime not in runtime_list:
            print(
                f"Unsupported runtime '{runtime}' "
                f"for {app} with {manifest}"
            )
            continue

        print(line())
        length = len(app_data["components"])
        print(
            f"[STARTING] {app_data['app']} "
            f"({length} component(s))"
        )
        #print(
        #    f"{app} → {manifest.name} || {runtime} || "
        #    f"[Dockerfile={dockerfile}]"
        #    f"[platform_file={platform_file}]"
        #)

        handler_class = get_runtime_handler(runtime)
        if not handler_class:
            continue
        handler = handler_class(manifest=manifest, dockerfile=dockerfile)
        start = reuse.start_timer()
        if dockerfile:
            handler.build_from_dockerfile()
        else:
            handler.install_dependencies()
            handler.lint()
            handler.security_analysis()
            handler.unit_tests()
            handler.build()
        duration = reuse.start_timer() - start
        print(F"[{app}] Build Duration: {duration:.2f}s")
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
                continue
            if app_data["components"][0]["runtime"] != "python":
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
                    print(
                        f"✅ {app_dir.name}: completed"
                    )
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

