#!/usr/bin/env bash

install_sops() {
  if command -v sops >/dev/null 2>&1; then
    echo "sops already installed"
    return
  fi

  echo "Installing sops..."
  curl -Lo sops https://github.com/getsops/sops/releases/latest/download/sops-v3.9.0.linux.amd64
  chmod +x sops
  sudo mv sops /usr/local/bin/sops
}

install_age() {
  if command -v age-keygen >/dev/null 2>&1; then
    echo "age already installed"
    return
  fi

  echo "Installing age..."
  sudo apt-get update -y
  sudo apt-get install -y age
}

ensure_age_key() {
  mkdir -p "$HOME/.config/sops/age"

  if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
    echo "Creating AGE key..."
    age-keygen -o "$HOME/.config/sops/age/keys.txt"
  else
    echo "AGE key exists"
  fi
}

get_age_public_key() {
  grep -oE 'age1[a-z0-9]+' "$HOME/.config/sops/age/keys.txt"
}
