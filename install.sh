#!/usr/bin/env bash
# install.sh — instala dependências, Java 25, Paper, Geyser, Floodgate e playit; depois inicia.
# Funciona no Termux (Android) e em Linux Debian/Ubuntu (ex.: sandbox do Daytona).
# Uso: bash install.sh [--no-start]
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

START=1
for a in "$@"; do
  case "$a" in
    --no-start) START=0 ;;
    *) echo "Opção desconhecida: $a (use --no-start)"; exit 1 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64|aarch64|arm64) ;;
  *) echo "[erro] CPU $(uname -m) não suportada (precisa x86_64 ou aarch64/arm64)."; exit 1 ;;
esac

IS_TERMUX=0
if [ -n "${TERMUX_VERSION:-}" ] || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]; then IS_TERMUX=1; fi

if [ "$IS_TERMUX" -eq 1 ]; then
  echo "[install] Termux detectado. Atualizando pacotes (upgrade completo, evita bibliotecas quebradas)..."
  export DEBIAN_FRONTEND=noninteractive
  # apt direto: o 'pkg' usa curl, que pode estar quebrado justamente por falta de upgrade
  if ! { apt-get update && apt-get -y -o Dpkg::Options::=--force-confnew full-upgrade; }; then
    echo "[erro] upgrade falhou. Rode 'termux-change-repo', escolha outro mirror e tente de novo."
    exit 1
  fi
  echo "[install] Instalando dependências..."
  pkg install -y curl tar tmux jq proot ca-certificates
  if ! curl --version >/dev/null 2>&1; then
    echo "[erro] curl quebrado (libs desatualizadas). Rode: apt update && apt full-upgrade -y   e depois: bash install.sh"
    exit 1
  fi
else
  MISSING=""
  for p in curl tar tmux jq; do
    command -v "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
  done
  if [ -n "$MISSING" ]; then
    if [ "$(id -u)" -eq 0 ]; then SUDO=""; elif command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else SUDO="none"; fi
    if [ "$SUDO" = "none" ]; then
      echo "[erro] Faltam:$MISSING e não sou root nem tenho sudo. Instale-os e rode de novo."
      exit 1
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
      echo "[erro] Faltam:$MISSING e não achei apt-get. Instale-os manualmente."
      exit 1
    fi
    echo "[install] Instalando:$MISSING"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -y
    # shellcheck disable=SC2086
    $SUDO apt-get install -y --no-install-recommends ca-certificates$MISSING
  else
    echo "[install] Dependências já presentes."
  fi
fi

chmod +x "$ROOT/mc" "$ROOT/install.sh"

echo "[install] Checando a rede..."
"$ROOT/mc" preflight || true

"$ROOT/mc" setup

if [ "$START" -eq 1 ]; then
  "$ROOT/mc" start
  echo
  echo "Pronto. Comandos: ./mc help   |   acompanhe a subida: ./mc logs"
else
  echo
  echo "Pronto. Inicie com: ./mc start"
fi
