import json
import os
import subprocess
import sys
from pathlib import Path
import yaml


res = subprocess.run(
      ["git", "rev-parse", "--show-toplevel"],
      capture_output=True, text=True,
    )
if res.returncode != 0:
    ROOT = Path(__file__).resolve().parents[2]
else:
    ROOT = Path(res.stdout.strip())

STATE_FILE = ROOT / "gitops" / "state" / "secrets.json"
SECRETS_DIR = ROOT / "gitops" / "secrets"


def load_state():
    if not STATE_FILE.is_file():
        raise RuntimeError(f"State file not found: {STATE_FILE}")

    if STATE_FILE.stat().st_size == 0:
        raise RuntimeError(f"State file is empty: {STATE_FILE}")

    try:
        data = json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON: {STATE_FILE}") from exc

    if not isinstance(data, dict):
        raise RuntimeError("Secret state must be a JSON object.")

    return data


def apply_file(secret_file):
    if secret_file.stat().st_size == 0:
        raise RuntimeError(f"Secret file is empty: {secret_file}")

    print(f"Decrypting: {secret_file}")

    decrypted = subprocess.run(
        ["sops", "-d", str(secret_file)],
        capture_output=True,
        text=True,
        check=True,
    )

    if not decrypted.stdout.strip():
        raise RuntimeError(f"Decrypted secret is empty: {secret_file}")

    subprocess.run(
        ["kubectl", "apply", "--validate=false", "-f", "-"],
        input=decrypted.stdout,
        text=True,
        check=True,
    )

    print(f"✓ Applied: {secret_file}")


def generate_github_repo_secret():
    private_key = os.getenv("PRIVATE_KEY")
    app_id = os.getenv("APP_ID")
    repo_url = os.getenv("REPO_URL")

    if not private_key:
        raise RuntimeError("PRIVATE_KEY is missing")

    if not app_id:
        raise RuntimeError("APP_ID is missing")

    if not repo_url:
        raise RuntimeError("REPO_URL is missing")

    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": "github-app-repo",
            "namespace": "argocd",
            "labels": {
                "argocd.argoproj.io/secret-type": "repo-creds"
            },
        },
        "type": "Opaque",
        "stringData": {
            "url": repo_url,
            "githubAppID": app_id,
            "githubAppPrivateKey": private_key,
        },
    }

    manifest = yaml.safe_dump(secret, sort_keys=False)
    subprocess.run(
        ["kubectl", "apply", "--validate=false", "-f", "-"],
        input=manifest,
        text=True,
        check=True,
    )

    print("✓ Applied github-repo-secret Successfully")


def execute_static_secret(name):
    secret_dir = SECRETS_DIR / name

    if not secret_dir.is_dir():
        raise RuntimeError(f"Secret directory not found: {secret_dir}")

    yaml_files = sorted(secret_dir.glob("*.yaml"))

    if not yaml_files:
        raise RuntimeError(f"No YAML files found in: {secret_dir}")

    for secret_file in yaml_files:
        apply_file(secret_file)


def execute_dynamic_secret(name):
    if name == "github-repo-secret":
        generate_github_repo_secret()
        return

    raise RuntimeError(
        f"No dynamic secret generator configured for: {name}"
    )


def main():
    state = load_state()

    for name, exists in state.items():

        if not isinstance(name, str):
            raise RuntimeError("Secret names must be strings.")

        if not isinstance(exists, bool):
            raise RuntimeError(
                f"Invalid state for '{name}': expected true or false."
            )

        print()
        print(f"Processing: {name}")

        if exists:
            execute_static_secret(name)
        else:
            execute_dynamic_secret(name)

    print()
    print("✓ Secret execution complete.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"❌ {exc}", file=sys.stderr)
        sys.exit(1)
