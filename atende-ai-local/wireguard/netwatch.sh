#!/usr/bin/env bash
# Atende AI — monitor de rede do servidor local (executado a cada minuto pelo atende-ai-netwatch.timer).
# Registra Wi-Fi, gateway e túnel em JSON. Única ação corretiva: (re)iniciar wg-quick@wg0, no máximo
# uma vez a cada MIN_RESTART_INTERVAL_S e somente quando o gateway local responde (sem Internet não adianta).
# Nunca reinicia o servidor, a rede Wi-Fi nem containers.
set -uo pipefail

WIFI=${WIFI_IFACE:-wlxe01cfca274a9}
PEER=${VPN_PEER:-10.77.0.1}
DIR=${NETWATCH_DIR:-/var/lib/atende-ai/netwatch}
STALE_S=${STALE_S:-300}
MIN_RESTART_INTERVAL_S=${MIN_RESTART_INTERVAL_S:-600}

mkdir -p "$DIR"
now=$(date +%s)
restarts_total=0
last_restart=0
last_successful_handshake=0
[[ -f "$DIR/state" ]] && source "$DIR/state"

wifi_up=false
[[ "$(cat "/sys/class/net/$WIFI/operstate" 2>/dev/null)" == "up" ]] && wifi_up=true
signal=$(awk -v i="$WIFI:" '$1 == i { v = $4; sub(/\.$/, "", v); print v }' /proc/net/wireless)
[[ "$signal" =~ ^-?[0-9]+$ ]] || signal=null

probe() {
  local host=$1 out status loss rtt
  [[ -n "$host" ]] || { echo 'false null null'; return; }
  out=$(ping -n -c3 -W2 "$host" 2>&1) && status=0 || status=$?
  loss=$(sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' <<<"$out" | tail -1)
  rtt=$(sed -n '/^rtt /s/.* = //p' <<<"$out" | cut -d/ -f2 | tr -d ' ' | tail -1)
  [[ "$loss" =~ ^[0-9]+([.][0-9]+)?$ ]] || loss=null
  [[ "$rtt" =~ ^[0-9]+([.][0-9]+)?$ ]] || rtt=null
  if [[ "$status" == 0 && "$loss" != 100 ]]; then echo "true $rtt $loss"; else echo "false $rtt $loss"; fi
}

gw=$(ip -4 route show default | awk '{ print $3; exit }')
read -r gateway_ok gateway_rtt_ms gateway_loss_pct < <(probe "$gw")

wg_present=false
ip link show wg0 >/dev/null 2>&1 && wg_present=true
peer_ok=false
peer_rtt_ms=null
peer_loss_pct=null
if $wg_present; then
  read -r peer_ok peer_rtt_ms peer_loss_pct < <(probe "$PEER")
fi

age=null
hs=$(wg show wg0 latest-handshakes 2>/dev/null | awk '{ print $2; exit }')
if [[ -n "$hs" && "$hs" != "0" ]]; then
  age=$((now - hs))
  (( hs > last_successful_handshake )) && last_successful_handshake=$hs
fi

action=none
can_act=false
$gateway_ok && (( now - last_restart >= MIN_RESTART_INTERVAL_S )) && can_act=true
if ! $wg_present; then
  if $can_act; then
    systemctl start wg-quick@wg0 && action=start || action=start_failed
  fi
elif ! $peer_ok && { [[ "$age" == "null" ]] || (( age > STALE_S )); }; then
  if $can_act; then
    systemctl restart wg-quick@wg0 && action=restart || action=restart_failed
  else
    action=waiting
  fi
fi
if [[ "$action" == start* || "$action" == restart* ]]; then
  restarts_total=$((restarts_total + 1))
  last_restart=$now
  logger -t atende-ai-netwatch "wg0 $action (peer_ok=$peer_ok handshake_age=$age gateway_ok=$gateway_ok wifi_up=$wifi_up)"
fi

printf 'restarts_total=%d\nlast_restart=%d\nlast_successful_handshake=%d\n' \
  "$restarts_total" "$last_restart" "$last_successful_handshake" > "$DIR/state.tmp" && mv "$DIR/state.tmp" "$DIR/state"
cat > "$DIR/netwatch.json.tmp" <<EOF
{"checked_at": "$(date -Is)", "wifi_up": $wifi_up, "wifi_signal_dbm": $signal, "gateway_ok": $gateway_ok,
 "gateway_rtt_ms": $gateway_rtt_ms, "gateway_packet_loss_pct": $gateway_loss_pct,
 "vpn_interface": $wg_present, "vpn_peer_ok": $peer_ok, "vpn_peer_rtt_ms": $peer_rtt_ms,
 "vpn_peer_packet_loss_pct": $peer_loss_pct, "handshake_age_s": $age,
 "last_successful_handshake_at": $last_successful_handshake,
 "vpn_restarts_total": $restarts_total, "last_action": "$action"}
EOF
chmod 644 "$DIR/netwatch.json.tmp"
mv "$DIR/netwatch.json.tmp" "$DIR/netwatch.json"
