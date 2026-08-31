import subprocess
import sys

class PythonHandler:
    def __init__(self, manifest, dockerfile=False):
      self.manifest = manifest
      self.dockerfile = dockerfile
      self.app_dir  = manifest.parent
      self.app_name = manifest.parent.name

    def install_dependencies(self):
        print(
           f"[PYTHON_HANDLER] app={self.app_name} "
           f"manifest={self.manifest} Installing.....")
        if self.manifest.name ==  "requirements.txt":
            command = [
              sys.executable,
              "-m", "pip", "install", "-r",
              str(self.manifest),
            ]
        elif self.manifest.name == "pyproject.toml":
            command = [
                sys.executable,
                "-m", "pip", "install", ".",
            ]
        else:
            raise RuntimeError(
                f"Unsupported Python manifest: "
                f"{self.manifest.name}"
            )

        ruff_command = [
            sys.executable,
            "-m", "pip", "install", "ruff",
        ]

        subprocess.run(command, cwd=self.app_dir, check=True)
        subprocess.run(ruff_command, cwd=self.app_dir, check=True)
        print(f"[{self.app_name}] Dependencies installed successfully")

    def lint(self):
        print(f"[{self.app_name}] Started Linting......")
        subprocess.run(
            [
              sys.executable,
              "-m", "ruff",  "check", ".",
            ],
          cwd=self.app_dir, check=True,
        )
        print(f"[{self.app_name}] Lint passed successfully")


    def security_analysis(self):
        pass

    def unit_tests(self):
        pass

    def build(self):
        pass

    def build_from_dockerfile(self):
        pass
