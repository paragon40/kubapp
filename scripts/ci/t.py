
manifest_list = {"requirements.txt": "python", "pyproject.toml": "python",
                 "pom.xml": "java", "build.gradle": "java",
                 "build.gradle.kts": "java", "package.json": "node",
                 "go.mod": "golang" }

for x in manifest_list.keys():
  print(x)
