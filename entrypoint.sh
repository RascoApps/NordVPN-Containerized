#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

normalize_on_off() {
  local value
  value="${1:-}"
  if [[ -z "$value" ]]; then
    return 1
  fi
  case "${value,,}" in
    on|true|1|yes|enabled|enable) echo "on" ;;
    off|false|0|no|disabled|disable) echo "off" ;;
    *) return 1 ;;
  esac
}

normalize_enable_disable() {
  local value
  value="${1:-}"
  if [[ -z "$value" ]]; then
    return 1
  fi
  case "${value,,}" in
    enable|enabled|on|true|1|yes) echo "enable" ;;
    disable|disabled|off|false|0|no) echo "disable" ;;
    *) return 1 ;;
  esac
}

maybe_set() {
  local key value
  key="$1"
  value="${2:-}"
  if [[ -z "$value" ]]; then
    return
  fi
  log "nordvpn set ${key} ${value}"
  if ! nordvpn set "$key" "$value"; then
    log "WARNING: 'nordvpn set ${key} ${value}' failed, continuing"
  fi
}

apply_on_off_setting() {
  local key value normalized
  key="$1"
  value="${2:-}"
  normalized="$(normalize_on_off "$value" 2>/dev/null || true)"
  if [[ -z "$normalized" ]]; then
    return
  fi
  log "nordvpn set ${key} ${normalized}"
  if ! nordvpn set "$key" "$normalized"; then
    log "WARNING: 'nordvpn set ${key} ${normalized}' failed, continuing"
  fi
}

apply_enable_disable_setting() {
  local key value normalized
  key="$1"
  value="${2:-}"
  normalized="$(normalize_enable_disable "$value" 2>/dev/null || true)"
  if [[ -z "$normalized" ]]; then
    return
  fi
  log "nordvpn set ${key} ${normalized}"
  if ! nordvpn set "$key" "$normalized"; then
    log "WARNING: 'nordvpn set ${key} ${normalized}' failed, continuing"
  fi
}

apply_dns_setting() {
  local raw values
  raw="${1:-}"
  if [[ -z "$raw" ]]; then
    return
  fi
  IFS=' ,;' read -r -a values <<< "$raw"
  if [[ "${#values[@]}" -eq 0 ]]; then
    return
  fi
  log "nordvpn set dns ${values[*]}"
  if ! nordvpn set dns "${values[@]}"; then
    log "WARNING: 'nordvpn set dns ${values[*]}' failed, continuing"
  fi
}

apply_allowlist() {
  local type raw items item
  type="$1"
  raw="${2:-}"
  if [[ -z "$raw" ]]; then
    return
  fi
  IFS=' ,;' read -r -a items <<< "$raw"
  for item in "${items[@]}"; do
    if [[ -z "$item" ]]; then
      continue
    fi
    log "nordvpn whitelist add ${type} ${item}"
    nordvpn whitelist add "$type" "$item" || true
  done
}

start_daemon() {
  if /etc/init.d/nordvpn status >/dev/null 2>&1; then
    return
  fi
  log "Starting nordvpnd"
  /etc/init.d/nordvpn start
  sleep 3
}

ensure_login() {
  if nordvpn account >/dev/null 2>&1; then
    log "Already logged in"
    return
  fi
  if [[ -n "${NORDVPN_TOKEN:-}" ]]; then
    log "Logging in with service token"
    nordvpn login --token "$NORDVPN_TOKEN"
    return
  fi
  die "NordVPN login required. Provide NORDVPN_TOKEN or log in interactively via docker exec."
}

apply_settings() {
  local technology protocol autoconnect
  technology="${NORDVPN_TECHNOLOGY:-NordLynx}"
  protocol="${NORDVPN_PROTOCOL:-udp}"

  case "${technology,,}" in
    nordlynx|wireguard) technology="NordLynx" ;;
    openvpn) technology="OpenVPN" ;;
  esac

  if [[ -n "$technology" ]]; then
    log "Setting technology to ${technology}"
    nordvpn set technology "$technology"
  fi

  if [[ "${technology,,}" == "openvpn" ]]; then
    protocol="${protocol,,}"
    case "$protocol" in
      tcp|udp) ;; 
      *) protocol="udp" ;;
    esac
    maybe_set protocol "$protocol"
  else
    log "Skipping protocol override because ${technology} uses WireGuard"
  fi

  apply_on_off_setting killswitch "${NORDVPN_KILLSWITCH:-}"
  apply_on_off_setting threatprotectionlite "${NORDVPN_THREAT_PROTECTION_LITE:-}"
  apply_on_off_setting obfuscate "${NORDVPN_OBFUSCATE:-}"
  apply_on_off_setting meshnet "${NORDVPN_MESHNET:-}"
  apply_on_off_setting analytics "${NORDVPN_ANALYTICS:-}"
  apply_on_off_setting notify "${NORDVPN_NOTIFY:-}"
  apply_on_off_setting autoconnect "${NORDVPN_AUTOCONNECT_STATE:-}"
  autoconnect="${NORDVPN_AUTOCONNECT_TARGET:-}"
  if [[ -n "$autoconnect" ]]; then
    log "Configuring autoconnect target ${autoconnect}"
    nordvpn set autoconnect on "$autoconnect"
  fi
  apply_enable_disable_setting lan-discovery "${NORDVPN_LAN_DISCOVERY:-}"
  apply_dns_setting "${NORDVPN_DNS:-}"
  apply_allowlist port "${NORDVPN_ALLOWLIST_PORTS:-}"
  apply_allowlist subnet "${NORDVPN_ALLOWLIST_SUBNETS:-}"
}

connect_vpn() {
  local connect_cmd extra
  if [[ "${NORDVPN_SKIP_CONNECT:-false}" =~ ^(true|1|yes)$ ]]; then
    log "Skipping auto-connect per configuration"
    return
  fi

  connect_cmd=(nordvpn connect)

  local group
  group="${NORDVPN_GROUP:-p2p}"
  if [[ -n "$group" ]]; then
    connect_cmd+=(--group "$group")
  fi

  if [[ -n "${NORDVPN_CONNECT:-}" ]]; then
    log "Using raw connect arguments: ${NORDVPN_CONNECT}"
    read -r -a extra <<< "${NORDVPN_CONNECT}"
    connect_cmd+=("${extra[@]}")
  elif [[ -n "${NORDVPN_SERVER:-}" ]]; then
    connect_cmd+=("${NORDVPN_SERVER}")
  elif [[ -n "${NORDVPN_COUNTRY:-}" ]]; then
    connect_cmd+=("${NORDVPN_COUNTRY}")
  fi

  log "Connecting with: ${connect_cmd[*]}"
  "${connect_cmd[@]}"
}

await_logs() {
  trap 'log "Disconnecting"; nordvpn disconnect || true; exit 0' SIGTERM SIGINT
  touch /var/log/nordvpn/daemon.log /var/log/nordvpn/nordvpnd.log
  tail -F /var/log/nordvpn/daemon.log /var/log/nordvpn/nordvpnd.log &
  wait "$!"
}

main() {
  start_daemon
  ensure_login
  apply_settings
  connect_vpn
  await_logs
}

main "$@"
