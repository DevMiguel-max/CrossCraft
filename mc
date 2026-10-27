#!/usr/bin/env bash
# mc — servidor Minecraft Java + Bedrock (Paper + Geyser + Floodgate), para Termux e Linux/Daytona.
# Jogadores do Java entram pela porta TCP 25565; os do Bedrock pela UDP 19132 (via Geyser).
# Uso: ./mc help
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT/server"
PLAYIT_DIR="$ROOT/playit"
BACKUP_DIR="$ROOT/backups"
JAVA_DIR="$ROOT/runtime/java"
SESSION="mc"
PLAYIT_SESSION="mc-playit"

# ---------- padrões (config.env sobrescreve) ----------
EULA="false"
PAPER_VERSION="26.3"
PAPER_ALLOW_UNSTABLE="0"
PAPER_API="https://fill.papermc.io/v3/projects/paper"
PAPER_UA="crossplay-server-script/1.0 (+https://github.com/DevMiguel-max)"
GEYSER_URL="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
FLOODGATE_URL="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
USE_FLOODGATE="1"
VIAVERSION="0"
JAVA_URL=""
MEMORY="auto"
JAVA_FLAGS="-XX:+UseG1GC"
JAVA_PORT="25565"
BEDROCK_PORT="19132"
BEDROCK_TRANSPORT="raknet"
SERVER_NAME="Crossplay Server"
MAX_PLAYERS="10"
VIEW_DISTANCE="8"
SIMULATION_DISTANCE="6"
GAMEMODE="survival"
DIFFICULTY="normal"
ONLINE_MODE="true"
AUTO_RESTART="1"
USE_PLAYIT="1"
PLAYIT_VERSION="v1.0.10"
BACKUP_KEEP="3"
MIN_PAPER_BYTES="10000000"
MIN_PLUGIN_BYTES="500000"
# shellcheck disable=SC1091
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"

PAPER_JAR="$SERVER_DIR/paper.jar"
PLUGINS_DIR="$SERVER_DIR/plugins"
GEYSER_JAR="$PLUGINS_DIR/Geyser-Spigot.jar"
FLOODGATE_JAR="$PLUGINS_DIR/floodgate-spigot.jar"
VIA_JAR="$PLUGINS_DIR/ViaVersion.jar"
PLAYIT_BIN="$PLAYIT_DIR/playit"
PLAYIT_CLI="$PLAYIT_DIR/playit-cli"

# ---------- util ----------
if [ -t 1 ]; then
  C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[36m'; C_0=$'\e[0m'
else
  C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""
fi
log()  { printf '%s\n' "${C_B}[mc]${C_0} $*"; }
ok()   { printf '%s\n' "${C_G}[ok]${C_0} $*"; }
warn() { printf '%s\n' "${C_Y}[aviso]${C_0} $*" >&2; }
die()  { printf '%s\n' "${C_R}[erro]${C_0} $*" >&2; exit 1; }

is_termux() {
  case "${MC_PLATFORM:-}" in termux) return 0 ;; linux) return 1 ;; esac
  [ -n "${TERMUX_VERSION:-}" ] || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Falta '$1'. Rode: bash install.sh"
  if [ "$1" = "curl" ] && ! curl --version >/dev/null 2>&1; then
    die "curl está quebrado (bibliotecas desatualizadas). Rode: apt update && apt full-upgrade -y"
  fi
}

cpu_arch() { # imprime aarch64 ou x86_64
  case "$(uname -m)" in
    aarch64|arm64) echo aarch64 ;;
    x86_64|amd64)  echo x86_64 ;;
    *) die "Arquitetura $(uname -m) não suportada (precisa x86_64 ou aarch64/arm64)." ;;
  esac
}

dl() { # dl URL DESTINO [User-Agent]
  local url="$1" dest="$2" ua="${3:-}" tmp="$2.part"
  rm -f "$tmp"
  log "baixando: $url"
  if [ -n "$ua" ]; then
    curl -fL --retry 4 --retry-delay 3 --connect-timeout 20 -A "$ua" -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  else
    curl -fL --retry 4 --retry-delay 3 --connect-timeout 20 -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  fi
  mv -f "$tmp" "$dest"
}

fsize() { wc -c < "$1" | tr -d '[:space:]'; }

is_running()     { command -v tmux >/dev/null 2>&1 && tmux has-session -t "$SESSION" 2>/dev/null; }
playit_running() { command -v tmux >/dev/null 2>&1 && tmux has-session -t "$PLAYIT_SESSION" 2>/dev/null; }

wake_lock()   { if is_termux && command -v termux-wake-lock   >/dev/null 2>&1; then termux-wake-lock;   fi; }
wake_unlock() { if is_termux && command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi; }

set_prop() { # set_prop ARQUIVO CHAVE VALOR
  local f="$1" k="$2" v="$3"
  v="${v//|/ }"; v="${v//&/\\&}"
  if grep -q "^${k}=" "$f" 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$f"
  else
    printf '%s=%s\n' "$k" "${v//\\&/&}" >> "$f"
  fi
}

# ---------- Java 25 (o Paper 26.x exige) ----------
find_java() {
  if [ -x "$JAVA_DIR/bin/java" ]; then printf '%s' "$JAVA_DIR/bin/java"; return 0; fi
  command -v java 2>/dev/null
}
java_major() { "$1" -version 2>&1 | head -n1 | sed -n 's/.*version "\([0-9]*\).*/\1/p'; }

install_java() {
  local j m
  j="$(find_java || true)"
  if [ -n "$j" ]; then
    m="$(java_major "$j")"
    if [ "${m:-0}" -ge 25 ]; then ok "Java $m já instalado ($j)"; return 0; fi
    log "Java $m encontrado, mas o Paper 26.x exige 25 ou mais."
  fi
  if is_termux; then
    log "Instalando openjdk-25 pelo pkg (Termux)..."
    pkg install -y openjdk-25 || die "Falha ao instalar openjdk-25. Rode: apt update && apt full-upgrade -y, e tente de novo."
  else
    need tar
    local arch ta url="$JAVA_URL" tag href
    arch="$(cpu_arch)"; ta="x64"; [ "$arch" = "aarch64" ] && ta="aarch64"
    if [ -z "$url" ]; then
      tag="$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/adoptium/temurin25-binaries/releases/latest | sed 's|.*/tag/||')"
      [ -n "$tag" ] || die "Não consegui descobrir a versão do Temurin 25 (github.com bloqueado?). Use JAVA_URL no config.env."
      href="$(curl -sL "https://github.com/adoptium/temurin25-binaries/releases/expanded_assets/$tag" | grep -o "href=\"[^\"]*jre_${ta}_linux_hotspot[^\"]*\\.tar\\.gz\"" | head -n1 | sed 's/^href="//; s/"$//')"
      [ -n "$href" ] || die "Não achei o JRE do Temurin 25 para $ta. Use JAVA_URL no config.env."
      url="https://github.com$href"
    fi
    local tmp; tmp="$(mktemp -d)" || die "mktemp falhou"
    if ! dl "$url" "$tmp/java.tar.gz"; then rm -rf "$tmp"; die "Falha ao baixar o Java 25"; fi
    rm -rf "${JAVA_DIR:?}"; mkdir -p "$JAVA_DIR"
    tar -xzf "$tmp/java.tar.gz" -C "$JAVA_DIR" --strip-components=1 || { rm -rf "$tmp"; die "Falha ao extrair o Java"; }
    rm -rf "$tmp"
  fi
  j="$(find_java || true)"
  [ -n "$j" ] || die "Java não encontrado depois da instalação."
  m="$(java_major "$j")"
  [ "${m:-0}" -ge 25 ] || die "Java $m instalado, mas precisa ser 25 ou mais."
  ok "Java $m pronto ($j)"
}

resolve_memory() { # imprime ex.: 2048M
  if [ "$MEMORY" != "auto" ]; then printf '%s' "$MEMORY"; return 0; fi
  local kb lim mb x
  kb="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\) kB.*/\1/p' /proc/meminfo 2>/dev/null | head -n1)"
  if [ -z "$kb" ]; then printf '1G'; return 0; fi
  # Em containers (Daytona) o /proc/meminfo mostra a máquina inteira; vale o limite do cgroup.
  lim="$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
  case "$lim" in ""|max) lim="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)" ;; esac
  case "$lim" in
    ""|*[!0-9]*) ;;
    *) if [ $((lim / 1024)) -lt "$kb" ]; then kb=$((lim / 1024)); fi ;;
  esac
  mb=$((kb / 1024)); x=$((mb * 60 / 100))
  [ "$x" -lt 768 ] && x=768
  [ "$x" -gt 4096 ] && x=4096
  printf '%sM' "$x"
}

total_memory_mb() {
  local kb lim
  kb="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\) kB.*/\1/p' /proc/meminfo 2>/dev/null | head -n1)"
  [ -n "$kb" ] || { echo 0; return 0; }
  lim="$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
  case "$lim" in ""|max) lim="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)" ;; esac
  case "$lim" in ""|*[!0-9]*) ;; *) if [ $((lim / 1024)) -lt "$kb" ]; then kb=$((lim / 1024)); fi ;; esac
  echo $((kb / 1024))
}

# ---------- checagem de rede ----------
probe() { # probe NOME URL
  local code
  code="$(curl -sS -o /dev/null --max-time 8 -w '%{http_code}' "$2" 2>/dev/null)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    printf '  %s[ok]%s        %s\n' "$C_G" "$C_0" "$1"
    return 0
  fi
  printf '  %s[BLOQUEADO]%s %s\n' "$C_R" "$C_0" "$1"
  return 1
}

cmd_preflight() {
  need curl
  local pl=1 bad=0
  echo "Rede (saída para a internet):"
  probe "github.com (Java, playit, ViaVersion)" "https://github.com" || bad=1
  probe "fill.papermc.io (baixar o Paper)" "https://fill.papermc.io/v3/projects/paper" || bad=1
  probe "download.geysermc.org (baixar Geyser e Floodgate)" "https://download.geysermc.org" || bad=1
  probe "piston-data.mojang.com (o Paper baixa o servidor da Mojang)" "https://piston-data.mojang.com" || bad=1
  probe "libraries.minecraft.net (bibliotecas do Paper)" "https://libraries.minecraft.net" || bad=1
  probe "repo.maven.apache.org (bibliotecas do Paper)" "https://repo.maven.apache.org" || bad=1
  probe "sessionserver.mojang.com (login de jogadores Java)" "https://sessionserver.mojang.com" || bad=1
  probe "api.playit.gg (túnel playit)" "https://api.playit.gg" || pl=0
  echo
  if [ "$bad" -eq 1 ]; then
    warn "Algum host necessário está bloqueado: o setup ou a primeira subida do servidor pode falhar."
  fi
  if [ "$USE_PLAYIT" = "1" ] && [ "$pl" -eq 0 ]; then
    warn "playit bloqueado: ninguém de fora conseguirá entrar (só a rede local, se houver)."
    warn "No Daytona isso acontece nos Tiers 1 e 2 (saída restrita); o Daytona também só expõe HTTP, nunca UDP."
  fi
  return 0
}

# ---------- instalação ----------
paper_resolve() { # imprime "URL|VERSÃO|BUILD"
  local ver="$PAPER_VERSION" json url id chans
  need jq
  if [ "$ver" = "latest" ]; then
    json="$(curl -fsSL -A "$PAPER_UA" "$PAPER_API")" || return 1
    ver="$(printf '%s' "$json" | jq -r '.versions | to_entries[0] | .value[0]')"
    [ -n "$ver" ] && [ "$ver" != "null" ] || return 1
  fi
  json="$(curl -fsSL -A "$PAPER_UA" "$PAPER_API/versions/$ver/builds")" || return 1
  url="$(printf '%s' "$json" | jq -r 'first(.[] | select(.channel=="STABLE") | .downloads."server:default".url) // empty')"
  id="$(printf '%s' "$json" | jq -r 'first(.[] | select(.channel=="STABLE") | .id) // empty')"
  if [ -z "$url" ] && [ "$PAPER_ALLOW_UNSTABLE" = "1" ]; then
    url="$(printf '%s' "$json" | jq -r 'first(.[] | .downloads."server:default".url) // empty')"
    id="$(printf '%s' "$json" | jq -r 'first(.[] | .id) // empty')"
  fi
  if [ -z "$url" ]; then
    chans="$(printf '%s' "$json" | jq -r '[.[].channel] | unique | join(",")' 2>/dev/null)"
    warn "O Paper $ver não tem build STABLE (canais disponíveis: ${chans:-nenhum}). Ponha PAPER_ALLOW_UNSTABLE=\"1\" no config.env para aceitar uma build não estável."
    return 2
  fi
  printf '%s|%s|%s' "$url" "$ver" "$id"
}

install_paper() {
  local force="${1:-}" res url ver id rc
  mkdir -p "$SERVER_DIR"
  if [ -f "$PAPER_JAR" ] && [ "$force" != "force" ]; then
    ok "Paper já instalado ($(cat "$SERVER_DIR/.paper-version" 2>/dev/null || echo desconhecido))"
    return 0
  fi
  res="$(paper_resolve)"; rc=$?
  [ "$rc" -eq 0 ] && [ -n "$res" ] || die "Não consegui resolver o download do Paper (rede bloqueada? versão inexistente?)."
  url="${res%%|*}"; ver="$(printf '%s' "$res" | cut -d'|' -f2)"; id="$(printf '%s' "$res" | cut -d'|' -f3)"
  dl "$url" "$PAPER_JAR.new" "$PAPER_UA" || { rm -f "$PAPER_JAR.new"; die "Falha ao baixar o Paper"; }
  if [ "$(fsize "$PAPER_JAR.new")" -lt "$MIN_PAPER_BYTES" ]; then
    rm -f "$PAPER_JAR.new"; die "Paper baixado parece inválido ($(fsize "$PAPER_JAR.new") bytes)"
  fi
  [ -f "$PAPER_JAR" ] && mv -f "$PAPER_JAR" "$PAPER_JAR.bak"
  mv -f "$PAPER_JAR.new" "$PAPER_JAR"
  echo "$ver (build $id)" > "$SERVER_DIR/.paper-version"
  ok "Paper $ver (build $id) instalado"
}

install_plugin() { # install_plugin NOME URL DESTINO [force]
  local name="$1" url="$2" dest="$3" force="${4:-}"
  mkdir -p "$PLUGINS_DIR"
  if [ -f "$dest" ] && [ "$force" != "force" ]; then ok "$name já instalado"; return 0; fi
  dl "$url" "$dest.new" || { rm -f "$dest.new"; die "Falha ao baixar $name"; }
  if [ "$(fsize "$dest.new")" -lt "$MIN_PLUGIN_BYTES" ]; then
    rm -f "$dest.new"; die "$name baixado parece inválido"
  fi
  mv -f "$dest.new" "$dest"
  ok "$name instalado"
}

install_via() {
  local force="${1:-}" tag
  if [ -f "$VIA_JAR" ] && [ "$force" != "force" ]; then ok "ViaVersion já instalado"; return 0; fi
  tag="$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/ViaVersion/ViaVersion/releases/latest | sed 's|.*/tag/||')"
  [ -n "$tag" ] || die "Não consegui descobrir a versão do ViaVersion"
  install_plugin "ViaVersion $tag" "https://github.com/ViaVersion/ViaVersion/releases/download/$tag/ViaVersion-$tag.jar" "$VIA_JAR" "$force"
}

install_plugins() {
  local force="${1:-}"
  install_plugin "Geyser" "$GEYSER_URL" "$GEYSER_JAR" "$force"
  if [ "$USE_FLOODGATE" = "1" ]; then install_plugin "Floodgate" "$FLOODGATE_URL" "$FLOODGATE_JAR" "$force"; fi
  if [ "$VIAVERSION" = "1" ]; then install_via "$force"; fi
}

require_eula() {
  if [ "$EULA" != "true" ]; then
    die "Aceite o EULA do Minecraft para continuar: leia https://aka.ms/MinecraftEULA e, se concordar, ponha EULA=\"true\" no config.env."
  fi
  mkdir -p "$SERVER_DIR"
  printf 'eula=true\n' > "$SERVER_DIR/eula.txt"
}

seed_properties() {
  local f="$SERVER_DIR/server.properties"
  if [ -f "$SERVER_DIR/.configured" ]; then ok "server.properties já configurado (não sobrescrito)"; return 0; fi
  [ -f "$f" ] || : > "$f"
  set_prop "$f" server-port "$JAVA_PORT"
  set_prop "$f" motd "$SERVER_NAME"
  set_prop "$f" max-players "$MAX_PLAYERS"
  set_prop "$f" view-distance "$VIEW_DISTANCE"
  set_prop "$f" simulation-distance "$SIMULATION_DISTANCE"
  set_prop "$f" gamemode "$GAMEMODE"
  set_prop "$f" difficulty "$DIFFICULTY"
  set_prop "$f" online-mode "$ONLINE_MODE"
  touch "$SERVER_DIR/.configured"
  ok "server.properties configurado"
}

cmd_setup() {
  need curl; need tar; need jq
  cpu_arch >/dev/null
  require_eula
  mkdir -p "$SERVER_DIR" "$BACKUP_DIR"
  install_java
  install_paper
  install_plugins
  seed_properties
  if [ "$USE_PLAYIT" = "1" ]; then
    playit_install || warn "playit não instalado (opcional). Sem ele ninguém de fora entra."
  fi
  ok "Setup concluído. Inicie com: ./mc start"
}

# ---------- servidor ----------
installed() { [ -f "$PAPER_JAR" ] && [ -f "$GEYSER_JAR" ] && [ -n "$(find_java || true)" ]; }

geyser_auth_type() { if [ "$USE_FLOODGATE" = "1" ]; then echo floodgate; else echo online; fi; }

cmd_run() { # primeiro plano (usado dentro do tmux; também serve para depurar)
  installed || die "Servidor não instalado. Rode: ./mc setup"
  require_eula
  cd "$SERVER_DIR" || exit 1
  local java mem fast=0 code t0 t1
  java="$(find_java)"; mem="$(resolve_memory)"
  # Geyser lê estas variáveis de ambiente (GEYSER_<caminho-da-opção>) e sobrescreve o config.yml.
  export GEYSER_BEDROCK_PORT="$BEDROCK_PORT"
  export GEYSER_BEDROCK_TRANSPORT="$BEDROCK_TRANSPORT"
  export GEYSER_JAVA_AUTH_TYPE="$(geyser_auth_type)"
  while :; do
    t0="$(date +%s)"
    # shellcheck disable=SC2086
    "$java" -Xms512M -Xmx"$mem" $JAVA_FLAGS -jar "$PAPER_JAR" --nogui
    code=$?
    t1="$(date +%s)"
    echo
    echo "[mc] servidor encerrou (código $code)"
    [ "$code" -eq 0 ] && break
    [ "$AUTO_RESTART" = "1" ] || break
    if [ $((t1 - t0)) -lt 30 ]; then fast=$((fast + 1)); else fast=0; fi
    if [ "$fast" -ge 3 ]; then
      echo "[mc] 3 quedas seguidas em menos de 30s: desisti de reiniciar. Rode ./mc doctor e ./mc run para ver o erro."
      break
    fi
    echo "[mc] reiniciando em 5s (Ctrl+C cancela)..."
    sleep 5
  done
}

cmd_start() {
  need tmux
  installed || die "Servidor não instalado. Rode: ./mc setup"
  require_eula
  if is_running; then
    warn "Servidor já está rodando (./mc console)"
  else
    wake_lock
    tmux new-session -d -s "$SESSION" -c "$SERVER_DIR" "bash '$ROOT/mc' run" || die "Falha ao abrir sessão tmux"
    ok "Servidor iniciando: Java TCP $JAVA_PORT, Bedrock UDP $BEDROCK_PORT. Console: ./mc console (sair sem parar: Ctrl+B, depois D)"
    log "A primeira subida demora (o Paper baixa bibliotecas e o servidor da Mojang). Acompanhe com: ./mc logs"
  fi
  if [ "$USE_PLAYIT" = "1" ] && [ -s "$PLAYIT_DIR/secret" ]; then
    cmd_playit_start || warn "playit não subiu (veja ./mc playit-logs)"
  elif [ "$USE_PLAYIT" = "1" ]; then
    log "playit ainda não vinculado: rode ./mc playit-setup para liberar acesso pela internet."
  fi
}

cmd_stop() {
  if playit_running; then cmd_playit_stop; fi
  if is_running; then
    log "Parando servidor (salva o mundo)..."
    tmux send-keys -t "$SESSION" -l -- "stop"
    tmux send-keys -t "$SESSION" Enter
    local _
    for _ in $(seq 1 60); do
      is_running || break
      sleep 1
    done
    if is_running; then
      warn "Não parou em 60s, forçando."
      tmux kill-session -t "$SESSION" 2>/dev/null
    fi
    ok "Servidor parado"
  else
    warn "Servidor não estava rodando"
  fi
  wake_unlock
}

cmd_status() {
  if is_running; then ok "servidor: RODANDO (Java TCP $JAVA_PORT | Bedrock UDP $BEDROCK_PORT)"; else warn "servidor: parado"; fi
  if playit_running; then ok "playit: rodando"; else log "playit: parado"; fi
  local pv; pv="$(cat "$SERVER_DIR/.paper-version" 2>/dev/null)"
  [ -n "$pv" ] && log "Paper (Java): $pv. Jogadores Java precisam da mesma versão do jogo (a menos que use ViaVersion)."
  log "Bedrock (Geyser): transporte $BEDROCK_TRANSPORT. Confira as versões aceitas no README."
  if playit_running; then log "Endereços públicos: site playit.gg > seus túneis > Overview (não aparecem no terminal)."; fi
  return 0
}

cmd_console() {
  need tmux
  is_running || die "Servidor parado. Use ./mc start"
  log "Para sair sem parar o servidor: Ctrl+B, depois D"
  exec tmux attach -t "$SESSION"
}

cmd_logs() { # últimas 200 linhas do console
  is_running || die "Servidor parado"
  tmux capture-pane -p -J -t "$SESSION" -S -200 | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

cmd_cmd() {
  [ $# -gt 0 ] || die "Uso: ./mc cmd <comando>   ex: ./mc cmd op Steve"
  is_running || die "Servidor parado"
  tmux send-keys -t "$SESSION" -l -- "$*"
  tmux send-keys -t "$SESSION" Enter
}

cmd_backup() {
  mkdir -p "$BACKUP_DIR"
  local saved=0 i
  if is_running; then
    # Backup consistente: pausa o salvamento automático, força um save completo, copia, religa.
    tmux send-keys -t "$SESSION" -l -- "save-off"; tmux send-keys -t "$SESSION" Enter
    sleep 1
    tmux send-keys -t "$SESSION" -l -- "save-all flush"; tmux send-keys -t "$SESSION" Enter
    saved=1
    for i in $(seq 1 30); do
      sleep 1
      if tmux capture-pane -p -J -t "$SESSION" -S -40 | grep -q "Saved the game"; then break; fi
      [ "$i" -eq 30 ] && warn "O servidor não confirmou o save em 30s; copiando assim mesmo."
    done
  fi
  local items=() f
  for f in world world_nether world_the_end plugins server.properties bukkit.yml spigot.yml config ops.json whitelist.json banned-players.json banned-ips.json; do
    [ -e "$SERVER_DIR/$f" ] && items+=("$f")
  done
  local out="$BACKUP_DIR/mc-$(date +%Y%m%d-%H%M%S).tar.gz" rc=0
  if [ "${#items[@]}" -eq 0 ]; then
    warn "Nada para salvar ainda"
  else
    tar -czf "$out" --exclude='*.jar' -C "$SERVER_DIR" "${items[@]}" || rc=1
    if [ "$rc" -eq 0 ]; then ok "Backup: $out"; else warn "Backup falhou"; fi
  fi
  if [ "$saved" -eq 1 ]; then
    tmux send-keys -t "$SESSION" -l -- "save-on"; tmux send-keys -t "$SESSION" Enter
  fi
  local n=0 old
  while IFS= read -r old; do
    n=$((n + 1))
    [ "$n" -gt "$BACKUP_KEEP" ] && rm -f "$old"
  done < <(ls -1t "$BACKUP_DIR"/mc-*.tar.gz 2>/dev/null)
  return "$rc"
}

cmd_update() {
  local was=0
  if is_running; then was=1; cmd_stop; fi
  cmd_backup
  install_paper force
  install_plugins force
  [ "$was" -eq 1 ] && cmd_start
  return 0
}

# ---------- playit (túnel de saída para TCP e UDP) ----------
# No Termux o binário musl estático não lê o /etc/resolv.conf (não existe no Android): sobrepomos o /etc via proot.
playit_wrap() {
  if is_termux && command -v proot >/dev/null 2>&1 && [ -n "${PREFIX:-}" ]; then
    proot -b "$PREFIX/etc:/etc" "$@"
  else
    "$@"
  fi
}

playit_install() {
  local force="${1:-}" base arch
  mkdir -p "$PLAYIT_DIR"
  if [ -x "$PLAYIT_BIN" ] && [ -x "$PLAYIT_CLI" ] && [ "$force" != "force" ]; then
    ok "playit já instalado"
    return 0
  fi
  arch="$(cpu_arch)"; [ "$arch" = "x86_64" ] && arch="amd64"
  if [ "$PLAYIT_VERSION" = "latest" ]; then
    base="https://github.com/playit-cloud/playit-agent/releases/latest/download"
  else
    base="https://github.com/playit-cloud/playit-agent/releases/download/$PLAYIT_VERSION"
  fi
  dl "$base/playit-linux-$arch" "$PLAYIT_BIN" || return 1
  dl "$base/playit-cli-linux-$arch" "$PLAYIT_CLI" || return 1
  chmod +x "$PLAYIT_BIN" "$PLAYIT_CLI"
  ok "playit $PLAYIT_VERSION instalado"
}

cmd_playit_setup() {
  need curl
  playit_install || die "Não consegui baixar o playit (github.com bloqueado? rode ./mc preflight)"
  if [ -s "$PLAYIT_DIR/secret" ]; then
    ok "playit já vinculado (apague playit/secret para refazer)"
    return 0
  fi
  local code url secret
  code="$(playit_wrap "$PLAYIT_CLI" claim generate 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  [ -n "$code" ] || die "playit-cli claim generate não retornou código"
  url="$(playit_wrap "$PLAYIT_CLI" claim url "$code" --name "mc-crossplay" --type self-managed 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  [ -n "$url" ] || die "playit-cli claim url não retornou link"
  echo
  log "Abra este link no SEU navegador, entre na conta playit e aprove o agente:"
  echo "    $url"
  echo
  if is_termux && command -v termux-open-url >/dev/null 2>&1; then termux-open-url "$url" >/dev/null 2>&1 || true; fi
  log "Aguardando aprovação (Ctrl+C cancela)..."
  secret="$(playit_wrap "$PLAYIT_CLI" claim exchange "$code" --wait 0 | tail -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  case "$secret" in
    ""|*[!A-Za-z0-9_-]*) die "Não recebi um secret válido (recebido: '$secret'). Rode de novo." ;;
  esac
  if [ "${#secret}" -lt 16 ]; then die "Secret curto demais (${#secret} chars). Rode de novo."; fi
  ( umask 077; printf '%s' "$secret" > "$PLAYIT_DIR/secret" )
  ok "playit vinculado."
  log "Faltam passos manuais no site playit.gg:"
  log "  1) confirme o e-mail da conta (senão: account_status=email_not_verified e o túnel não funciona)"
  log "  2) crie um túnel 'Minecraft Java' com origem 127.0.0.1 porta $JAVA_PORT"
  log "  3) crie um túnel 'Minecraft Bedrock' com origem 127.0.0.1 porta $BEDROCK_PORT"
  log "Depois: ./mc restart. Os endereços públicos ficam na aba Overview de cada túnel."
}

cmd_playit_run() { # interno (roda dentro do tmux)
  [ -s "$PLAYIT_DIR/secret" ] || die "playit sem secret: rode ./mc playit-setup"
  cd "$PLAYIT_DIR" || exit 1
  playit_wrap "$PLAYIT_BIN" --secret "$(cat "$PLAYIT_DIR/secret")" --socket-path "$PLAYIT_DIR/playit.sock"
}

cmd_playit_start() {
  need tmux
  [ -x "$PLAYIT_BIN" ] || die "playit não instalado: ./mc setup"
  [ -s "$PLAYIT_DIR/secret" ] || die "playit não vinculado: ./mc playit-setup"
  if playit_running; then warn "playit já está rodando"; return 0; fi
  tmux new-session -d -s "$PLAYIT_SESSION" -c "$PLAYIT_DIR" "bash '$ROOT/mc' _playit_run" || return 1
  ok "playit iniciado (logs: ./mc playit-logs)"
}

cmd_playit_stop() {
  playit_running || { warn "playit não estava rodando"; return 0; }
  tmux send-keys -t "$PLAYIT_SESSION" C-c
  sleep 2
  tmux kill-session -t "$PLAYIT_SESSION" 2>/dev/null
  ok "playit parado"
}

cmd_playit_status() {
  [ -x "$PLAYIT_CLI" ] || die "playit não instalado"
  playit_running || die "playit não está rodando (./mc playit-start)"
  playit_wrap "$PLAYIT_CLI" --socket-path "$PLAYIT_DIR/playit.sock" status
}

cmd_playit_logs() {
  playit_running || die "playit não está rodando"
  tmux capture-pane -p -J -t "$PLAYIT_SESSION" -S -200 | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

# ---------- diagnóstico ----------
cmd_doctor() {
  local bad=0 t j m
  row() { # row OK|FALHA mensagem
    if [ "$1" = "OK" ]; then printf '  %s[ok]%s    %s\n' "$C_G" "$C_0" "$2"; else printf '  %s[FALHA]%s %s\n' "$C_R" "$C_0" "$2"; bad=1; fi
  }
  echo "Diagnóstico ($(is_termux && echo Termux || echo Linux), $(uname -m)):"
  for t in curl tar tmux jq; do
    if command -v "$t" >/dev/null 2>&1; then row OK "$t instalado"; else row FALHA "$t ausente (bash install.sh)"; fi
  done
  j="$(find_java || true)"
  if [ -n "$j" ]; then
    m="$(java_major "$j")"
    if [ "${m:-0}" -ge 25 ]; then row OK "Java $m"; else row FALHA "Java $m (o Paper 26.x exige 25 ou mais): rode ./mc setup"; fi
  else
    row FALHA "Java não instalado (./mc setup)"
  fi
  m="$(total_memory_mb)"
  if [ "$m" -ge 2000 ] || [ "$m" -eq 0 ]; then row OK "memória disponível: ${m} MB (usando $(resolve_memory) no Java)"; else row FALHA "memória ${m} MB: o Paper 26.x com Geyser precisa de pelo menos ~2 GB"; fi
  if [ -f "$PAPER_JAR" ]; then row OK "Paper presente ($(cat "$SERVER_DIR/.paper-version" 2>/dev/null))"; else row FALHA "paper.jar ausente (./mc setup)"; fi
  if [ -f "$GEYSER_JAR" ]; then row OK "Geyser presente"; else row FALHA "Geyser ausente (./mc setup)"; fi
  if [ "$USE_FLOODGATE" = "1" ]; then
    if [ -f "$FLOODGATE_JAR" ]; then row OK "Floodgate presente"; else row FALHA "Floodgate ausente (./mc setup)"; fi
  fi
  if [ -f "$SERVER_DIR/logs/latest.log" ]; then
    if grep -qi "Enabling Geyser" "$SERVER_DIR/logs/latest.log"; then row OK "Geyser carregou na última subida"; else warn "Geyser não aparece no log da última subida (o servidor já subiu?)"; fi
    if [ "$USE_FLOODGATE" = "1" ]; then
      if grep -qi "Enabling floodgate" "$SERVER_DIR/logs/latest.log"; then row OK "Floodgate carregou na última subida"; else warn "Floodgate não aparece no log da última subida"; fi
    fi
  fi
  if [ "$USE_PLAYIT" = "1" ]; then
    if [ -x "$PLAYIT_BIN" ]; then row OK "playit instalado"; else row FALHA "playit não instalado"; fi
    if [ -s "$PLAYIT_DIR/secret" ]; then row OK "playit vinculado"; else log "playit não vinculado (./mc playit-setup)"; fi
    if playit_running; then
      local st
      st="$(tmux capture-pane -p -J -t "$PLAYIT_SESSION" -S -300 2>/dev/null | grep -o 'account_status="[a-z_]*"' | tail -n1)"
      case "$st" in
        'account_status="verified"') row OK "conta playit verificada" ;;
        "") log "playit: sem status de conta nos logs ainda (espere 20s e rode de novo)" ;;
        *) row FALHA "conta playit: $st. Confirme o e-mail em playit.gg e rode: ./mc playit-stop && ./mc playit-start" ;;
      esac
    fi
  fi
  echo
  cmd_preflight
  return "$bad"
}

usage() {
  cat <<'EOF'
mc — servidor Minecraft Java + Bedrock (Paper + Geyser + Floodgate), Termux e Linux/Daytona

  setup              instala Java 25, Paper, Geyser, Floodgate e playit (exige EULA="true" no config.env)
  start | stop | restart | status
  console            console do servidor (sair sem parar: Ctrl+B, depois D)
  logs               últimas 200 linhas do console
  cmd <comando>      envia comando ao servidor (ex: ./mc cmd op Steve | ./mc cmd geyser version)
  run                primeiro plano, sem tmux (para ver erros de inicialização)
  backup             compacta mundos e configs em backups/ (mantém BACKUP_KEEP)
  update             atualiza Paper, Geyser e Floodgate, com backup antes
  doctor             diagnóstico completo (inclui checagem de rede)
  preflight          só a checagem de rede
  playit-setup       vincula o playit à sua conta (gera link de aprovação)
  playit-start | playit-stop | playit-status | playit-logs

Config: edite config.env
EOF
}

case "${1:-help}" in
  setup)          cmd_setup ;;
  start)          cmd_start ;;
  stop)           cmd_stop ;;
  restart)        cmd_stop; cmd_start ;;
  status)         cmd_status ;;
  console|attach) cmd_console ;;
  logs)           cmd_logs ;;
  cmd)            shift; cmd_cmd "$@" ;;
  run|_run)       cmd_run ;;
  backup)         cmd_backup ;;
  update)         cmd_update ;;
  doctor)         cmd_doctor ;;
  preflight)      cmd_preflight ;;
  playit-setup)   cmd_playit_setup ;;
  playit-start)   cmd_playit_start ;;
  playit-stop)    cmd_playit_stop ;;
  playit-status)  cmd_playit_status ;;
  playit-logs)    cmd_playit_logs ;;
  _playit_run)    cmd_playit_run ;;
  help|-h|--help) usage ;;
  *)              usage; exit 1 ;;
esac
