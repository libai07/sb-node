#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROJECT_NAME="sb-node"
CONFIG_DIR="${CONFIG_DIR:-/etc/sing-box}"
OUTPUT_DIR="${OUTPUT_DIR:-/root/sb-node}"
CONFIG_PATH="${CONFIG_PATH:-$CONFIG_DIR/config.json}"
INFO_PATH="${INFO_PATH:-$OUTPUT_DIR/sb-node.txt}"
HY2_CERT_PATH="${HY2_CERT_PATH:-$CONFIG_DIR/hysteria2.crt}"
HY2_KEY_PATH="${HY2_KEY_PATH:-$CONFIG_DIR/hysteria2.key}"

PORT="${PORT:-443}"
HY2_PORT="${HY2_PORT:-$PORT}"
LISTEN="${LISTEN:-}"
UUID="${UUID:-}"
SERVER_ADDR="${SERVER_ADDR:-}"
SERVER_NAME="${SERVER_NAME:-apple.com}"
REALITY_SERVER="${REALITY_SERVER:-$SERVER_NAME}"
REALITY_SERVER_PORT="${REALITY_SERVER_PORT:-443}"
SHORT_ID="${SHORT_ID:-}"
CLIENT_NAME="${CLIENT_NAME:-sing-box-reality}"
HY2_CLIENT_NAME="${HY2_CLIENT_NAME:-sing-box-hysteria2}"
HY2_SERVER_NAME="${HY2_SERVER_NAME:-$SERVER_NAME}"
HY2_PASSWORD="${HY2_PASSWORD:-}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-1}"
SELF_CHECK="${SELF_CHECK:-1}"

log() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$PROJECT_NAME" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$PROJECT_NAME" "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "run as root: sudo bash install.sh"
  fi
}

validate_port_value() {
  local name="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*) die "$name must be a number between 1 and 65535" ;;
  esac
  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    die "$name must be a number between 1 and 65535"
  fi
}

validate_json_string() {
  local name="$1" value="$2"
  [ -n "$value" ] || die "$name must not be empty"
  case "$value" in
    *'"'*|*'\'*) die "$name contains unsupported characters" ;;
  esac
}

is_ipv4_address() {
  local value="$1"
  case "$value" in
    *.*.*.*)
      case "$value" in
        *[!0-9.]*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
  esac
  return 1
}

is_ipv6_address() {
  local value="$1"
  case "$value" in
    *:*) return 0 ;;
  esac
  return 1
}

validate_hostname_or_ip() {
  local name="$1" value="$2"
  validate_json_string "$name" "$value"
  if is_ipv6_address "$value"; then
    case "$value" in
      *[!0-9a-fA-F:.]*) die "$name must be an IPv6 address without brackets or port" ;;
    esac
    return
  fi

  case "$value" in
    *[!a-zA-Z0-9.-]*) die "$name must be a hostname, IPv4 address or IPv6 address without port" ;;
  esac
}

validate_hex() {
  local name="$1" value="$2"
  case "$value" in
    *[!0-9a-fA-F]*) die "$name must be hexadecimal" ;;
  esac
}

validate_uri_safe() {
  local name="$1" value="$2"
  case "$value" in
    *[!a-zA-Z0-9._~-]*) die "$name must contain only letters, numbers, dot, underscore, tilde or hyphen" ;;
  esac
}

validate_uri_label() {
  local name="$1" value="$2"
  case "$value" in
    *[!a-zA-Z0-9._~\ -]*) die "$name must contain only letters, numbers, space, dot, underscore, tilde or hyphen" ;;
  esac
}

validate_settings() {
  validate_port_value "PORT" "$PORT"
  validate_port_value "HY2_PORT" "$HY2_PORT"
  validate_port_value "REALITY_SERVER_PORT" "$REALITY_SERVER_PORT"
  if [ -n "$LISTEN" ]; then
    validate_hostname_or_ip "LISTEN" "$LISTEN"
  fi
  validate_hostname_or_ip "SERVER_NAME" "$SERVER_NAME"
  validate_hostname_or_ip "REALITY_SERVER" "$REALITY_SERVER"
  validate_hostname_or_ip "HY2_SERVER_NAME" "$HY2_SERVER_NAME"
  validate_json_string "HY2_CERT_PATH" "$HY2_CERT_PATH"
  validate_json_string "HY2_KEY_PATH" "$HY2_KEY_PATH"
  validate_uri_label "CLIENT_NAME" "$CLIENT_NAME"
  validate_uri_label "HY2_CLIENT_NAME" "$HY2_CLIENT_NAME"
  if [ -n "$HY2_PASSWORD" ]; then
    validate_json_string "HY2_PASSWORD" "$HY2_PASSWORD"
    validate_uri_safe "HY2_PASSWORD" "$HY2_PASSWORD"
  fi
}

install_base_tools() {
  if command_exists apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl openssl iproute2
  elif command_exists dnf; then
    dnf -y install ca-certificates curl openssl iproute
  elif command_exists yum; then
    yum -y install ca-certificates curl openssl iproute
  elif command_exists apk; then
    apk add --no-cache ca-certificates curl openssl iproute2
  elif command_exists pacman; then
    pacman -Sy --noconfirm ca-certificates curl openssl iproute2
  else
    log "unknown package manager; using existing curl/openssl"
  fi

  command_exists curl || die "missing curl"
  command_exists openssl || die "missing openssl"
}

install_sing_box() {
  if command_exists sing-box; then
    log "found: $(sing-box version | head -n 1)"
    return
  fi

  log "installing sing-box with official repository or installer"
  if command_exists apt-get; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
    chmod a+r /etc/apt/keyrings/sagernet.asc
    cat >/etc/apt/sources.list.d/sagernet.sources <<'SOURCES'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
SOURCES
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y sing-box
  elif command_exists dnf; then
    dnf -y install dnf-plugins-core || true
    dnf config-manager addrepo --from-repofile=https://sing-box.app/sing-box.repo \
      || dnf config-manager --add-repo https://sing-box.app/sing-box.repo
    dnf -y install sing-box
  else
    curl -fsSL https://sing-box.app/install.sh | sh
  fi

  command_exists sing-box || die "sing-box installation failed"
  log "installed: $(sing-box version | head -n 1)"
}

generate_uuid() {
  local output hex

  if [ -n "$UUID" ]; then
    printf '%s' "$UUID"
    return
  fi

  if output="$(sing-box generate uuid 2>/dev/null)" && [ -n "$output" ]; then
    printf '%s' "$output" | tr -d '\r\n'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    tr -d '\r\n' </proc/sys/kernel/random/uuid
  elif command_exists uuidgen; then
    uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '\r\n'
  else
    hex="$(openssl rand -hex 16)"
    printf '%s-%s-4%s-8%s-%s' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "${hex:17:3}" "${hex:20:12}"
  fi
}

generate_reality_keypair() {
  local output private public
  output="$(sing-box generate reality-keypair)"
  private="$(printf '%s\n' "$output" | awk -F': ' 'tolower($1) ~ /private/ {print $2; exit}')"
  public="$(printf '%s\n' "$output" | awk -F': ' 'tolower($1) ~ /public/ {print $2; exit}')"
  [ -n "$private" ] || die "failed to parse REALITY private key"
  [ -n "$public" ] || die "failed to parse REALITY public key"
  printf '%s\n%s\n' "$private" "$public"
}

generate_short_id() {
  local value
  if [ -n "$SHORT_ID" ]; then
    value="$SHORT_ID"
  else
    value="$(openssl rand -hex 8)"
  fi

  if [ "${#value}" -gt 16 ]; then
    die "SHORT_ID must be 16 hex characters or fewer"
  fi
  if [ $(( ${#value} % 2 )) -ne 0 ]; then
    die "SHORT_ID must contain an even number of hex characters"
  fi
  validate_hex "SHORT_ID" "$value"
  printf '%s' "$value"
}

generate_hysteria2_password() {
  if [ -n "$HY2_PASSWORD" ]; then
    printf '%s' "$HY2_PASSWORD"
  else
    openssl rand -hex 16
  fi
}

generate_hysteria2_tls_cert() {
  local san
  san="DNS:$HY2_SERVER_NAME"

  if is_ipv4_address "$HY2_SERVER_NAME" || is_ipv6_address "$HY2_SERVER_NAME"; then
    san="IP:$HY2_SERVER_NAME"
  fi

  if [ -s "$HY2_CERT_PATH" ] && [ -s "$HY2_KEY_PATH" ]; then
    return
  fi

  mkdir -p "$(dirname "$HY2_CERT_PATH")" "$(dirname "$HY2_KEY_PATH")"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$HY2_KEY_PATH" \
    -out "$HY2_CERT_PATH" \
    -subj "/CN=$HY2_SERVER_NAME" \
    -addext "subjectAltName=$san"
  chmod 600 "$HY2_KEY_PATH"
  chmod 644 "$HY2_CERT_PATH"
}

detect_server_addr() {
  if [ -n "$SERVER_ADDR" ]; then
    printf '%s' "$SERVER_ADDR"
    return
  fi

  SERVER_ADDR="$(curl -fsSL --max-time 5 https://api4.ipify.org || true)"
  if ! is_ipv4_address "$SERVER_ADDR"; then
    SERVER_ADDR=""
  fi
  if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR="$(curl -fsSL --max-time 5 https://api6.ipify.org || true)"
    if ! is_ipv6_address "$SERVER_ADDR"; then
      SERVER_ADDR=""
    fi
  fi
  if [ -z "$SERVER_ADDR" ]; then
    read -r -p "Enter server public IP or domain: " SERVER_ADDR
  fi

  [ -n "$SERVER_ADDR" ] || die "server address is empty"
  printf '%s' "$SERVER_ADDR"
}

resolve_listen_addr() {
  local server_addr="$1"
  if [ -n "$LISTEN" ]; then
    return
  fi

  if is_ipv6_address "$server_addr"; then
    LISTEN="::"
  else
    LISTEN="0.0.0.0"
  fi
}

write_config() {
  local uuid="$1" private_key="$2" hy2_password="$3"
  local backup_path

  mkdir -p "$CONFIG_DIR"
  if [ -f "$CONFIG_PATH" ]; then
    backup_path="$CONFIG_PATH.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$CONFIG_PATH" "$backup_path"
    chmod 600 "$backup_path" || true
  fi

  cat >"$CONFIG_PATH" <<JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "$LISTEN",
      "listen_port": $PORT,
      "users": [
        {
          "name": "default",
          "uuid": "$uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_NAME",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$REALITY_SERVER",
            "server_port": $REALITY_SERVER_PORT
          },
          "private_key": "$private_key",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "$LISTEN",
      "listen_port": $HY2_PORT,
      "users": [
        {
          "name": "default",
          "password": "$hy2_password"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$HY2_SERVER_NAME",
        "alpn": [
          "h3"
        ],
        "certificate_path": "$HY2_CERT_PATH",
        "key_path": "$HY2_KEY_PATH"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
JSON
}

urlencode_label() {
  local value="$1"
  value="${value// /%20}"
  printf '%s' "$value"
}

uri_host() {
  local value="$1"
  if is_ipv6_address "$value"; then
    printf '[%s]' "$value"
  else
    printf '%s' "$value"
  fi
}

write_connection_info() {
  local server_addr="$1" uuid="$2" public_key="$3" hy2_password="$4"
  local label uri hy2_label hy2_uri uri_server_addr
  label="$(urlencode_label "$CLIENT_NAME")"
  hy2_label="$(urlencode_label "$HY2_CLIENT_NAME")"
  uri_server_addr="$(uri_host "$server_addr")"
  uri="vless://$uuid@$uri_server_addr:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_NAME&fp=chrome&pbk=$public_key&sid=$SHORT_ID&type=tcp&headerType=none#$label"
  hy2_uri="hysteria2://$hy2_password@$uri_server_addr:$HY2_PORT/?security=tls&alpn=h3&sni=$HY2_SERVER_NAME&insecure=1&allowInsecure=1#$hy2_label"

  mkdir -p "$(dirname "$INFO_PATH")"
  cat >"$INFO_PATH" <<INFO
Server: $server_addr

VLESS:
$uri

Hysteria2:
$hy2_uri
INFO
  chmod 600 "$INFO_PATH"

  printf '\n%s\n' "========== sb-node =========="
  cat "$INFO_PATH"
  printf '%s\n' "================================="
}

detect_service_user() {
  local user

  if command_exists systemctl; then
    user="$(systemctl cat sing-box 2>/dev/null | awk -F= '/^[[:space:]]*User=/ {print $2; exit}')"
    if [ -n "$user" ] && [ "$user" != "root" ] && id "$user" >/dev/null 2>&1; then
      printf '%s' "$user"
      return
    fi
  fi

  if id sing-box >/dev/null 2>&1; then
    printf '%s' "sing-box"
  fi
}

configure_systemd_override() {
  local sing_box_bin

  command_exists systemctl || return
  sing_box_bin="$(command -v sing-box)"
  mkdir -p /etc/systemd/system/sing-box.service.d
  cat >/etc/systemd/system/sing-box.service.d/10-sb-node.conf <<EOF
[Service]
ExecStart=
ExecStart=$sing_box_bin run -c $CONFIG_PATH
EOF
}

cleanup_legacy_outputs() {
  local timestamp legacy target
  timestamp="$(date +%Y%m%d%H%M%S)"

  mkdir -p "$OUTPUT_DIR"
  for legacy in \
    "$CONFIG_DIR/vless-client-outbound.json" \
    "$CONFIG_DIR/hysteria2-client-outbound.json" \
    "$CONFIG_DIR/sb-node.txt" \
    "$OUTPUT_DIR/vless-client-outbound.json" \
    "$OUTPUT_DIR/hysteria2-client-outbound.json"
  do
    [ -f "$legacy" ] || continue
    case "$legacy" in
      "$INFO_PATH") continue ;;
    esac
    target="$OUTPUT_DIR/legacy-$(basename "$legacy").$timestamp"
    mv -f "$legacy" "$target"
    chmod 600 "$target" || true
    log "moved legacy output: $target"
  done
}

apply_file_permissions() {
  local service_user service_group

  mkdir -p "$CONFIG_DIR" "$OUTPUT_DIR"
  chmod 755 "$CONFIG_DIR"
  chmod 700 "$OUTPUT_DIR"

  chmod 600 "$CONFIG_PATH"
  chmod 600 "$HY2_KEY_PATH"
  chmod 644 "$HY2_CERT_PATH"
  [ -f "$INFO_PATH" ] && chmod 600 "$INFO_PATH"

  service_user="$(detect_service_user || true)"
  [ -n "$service_user" ] || return
  service_group="$(id -gn "$service_user")"
  chown "$service_user:$service_group" "$CONFIG_PATH" "$HY2_KEY_PATH" "$HY2_CERT_PATH"
  log "granted runtime file access to service user: $service_user"
}

open_firewall() {
  [ "$ENABLE_FIREWALL" = "1" ] || return

  if command_exists ufw && ufw status | grep -qi active; then
    log "opening ufw ports: $PORT/tcp $HY2_PORT/udp"
    ufw allow "$PORT/tcp"
    ufw allow "$HY2_PORT/udp"
  fi

  if command_exists firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    log "opening firewalld ports: $PORT/tcp $HY2_PORT/udp"
    firewall-cmd --permanent --add-port="$PORT/tcp"
    firewall-cmd --permanent --add-port="$HY2_PORT/udp"
    firewall-cmd --reload
  fi
}

enable_service() {
  cleanup_legacy_outputs
  configure_systemd_override
  apply_file_permissions
  sing-box check -c "$CONFIG_PATH"

  if command_exists systemctl; then
    systemctl daemon-reload || true
    systemctl enable sing-box
    if ! systemctl restart sing-box; then
      warn "failed to restart sing-box; self check will show the local failure"
    fi
  else
    log "systemd not found; run manually: sing-box run -c $CONFIG_PATH"
  fi
}

port_is_listening() {
  local protocol="$1" port="$2" flags

  command_exists ss || return 2
  case "$protocol" in
    tcp) flags="-H -lnt" ;;
    udp) flags="-H -lnu" ;;
    *) return 2 ;;
  esac

  ss $flags 2>/dev/null | awk -v port="$port" '
    $0 ~ ":" port "([[:space:]]|$)" { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

run_self_check() {
  local failed=0

  [ "$SELF_CHECK" = "1" ] || return

  printf '\n%s\n' "========== Self Check =========="

  if sing-box check -c "$CONFIG_PATH" >/dev/null; then
    log "config: ok"
  else
    warn "config check failed: sudo sing-box check -c $CONFIG_PATH"
    failed=1
  fi

  if command_exists systemctl; then
    if systemctl is-active --quiet sing-box; then
      log "service: active"
    else
      warn "sing-box service is not active: sudo journalctl -u sing-box --output cat -n 100"
      failed=1
    fi
  else
    warn "systemd not found; service status was not checked"
  fi

  if port_is_listening tcp "$PORT"; then
    log "tcp/$PORT: ok"
  else
    warn "tcp/$PORT is not listening; VLESS Reality will not connect"
    failed=1
  fi

  if port_is_listening udp "$HY2_PORT"; then
    log "udp/$HY2_PORT: ok"
  else
    warn "udp/$HY2_PORT is not listening; Hysteria2 will not connect"
    failed=1
  fi

  if [ "$failed" -eq 0 ]; then
    log "self check passed"
  else
    warn "self check failed"
  fi

  printf '%s\n' "==============================="
}

main() {
  need_root
  validate_settings
  install_base_tools
  install_sing_box

  local uuid private_key public_key server_addr hy2_password
  local keys
  uuid="$(generate_uuid)"
  mapfile -t keys < <(generate_reality_keypair)
  private_key="${keys[0]}"
  public_key="${keys[1]}"
  SHORT_ID="$(generate_short_id)"
  hy2_password="$(generate_hysteria2_password)"
  server_addr="$(detect_server_addr)"
  validate_hostname_or_ip "SERVER_ADDR" "$server_addr"
  resolve_listen_addr "$server_addr"
  generate_hysteria2_tls_cert

  write_config "$uuid" "$private_key" "$hy2_password"
  open_firewall
  enable_service
  write_connection_info "$server_addr" "$uuid" "$public_key" "$hy2_password"
  run_self_check

  log "done. server config: $CONFIG_PATH"
}

main "$@"
