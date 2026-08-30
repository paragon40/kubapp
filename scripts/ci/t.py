
manifest_list = {"requirements.txt": "python", "pyproject.toml": "python",
                 "pom.xml": "java", "build.gradle": "java",
                 "build.gradle.kts": "java", "package.json": "node",
                 "go.mod": "golang" }

for x in manifest_list.keys():
  print(x)


    with ThreadPoolExecutor(max_workers=4) as executor:

        futures = {
            executor.submit(build_app, app_dir, manifests): app_dir
            for app_dir, manifests in apps.items()
            if manifests
        }

        for future in as_completed(futures):
            app_dir = futures[future]

            try:
                result = future.result()
                print(f"✅ {app_dir}: completed")

            except Exception as exc:
                print(f"❌ {app_dir}: {exc}")
