#!/usr/bin/env bash
# Make systemd-logind ignore a short press of the power button on the local AI server.
# Run ON the local server as the admin user:  sudo bash disable_power_key.sh
# Does not touch sshd, the network, WireGuard or Docker. A long press (hardware, ~4 s) still forces power off.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "execute com sudo"; exit 1; }

DROPIN_DIR=/etc/systemd/logind.conf.d
DROPIN=$DROPIN_DIR/90-atendeai-powerkey.conf
mkdir -p "$DROPIN_DIR"
printf '[Login]\nHandlePowerKey=ignore\n' > "$DROPIN.tmp"
chmod 644 "$DROPIN.tmp"
mv "$DROPIN.tmp" "$DROPIN"

echo "== configuração efetiva do logind"
systemd-analyze cat-config systemd/logind.conf | grep -v '^#' | grep -v '^$'

current() { busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey | awk '{print $2}' | tr -d '"'; }

# logind re-reads its configuration on SIGHUP without ending sessions.
systemctl kill -s HUP systemd-logind
sleep 2
value=$(current)
if [ "$value" != "ignore" ]; then
  echo "logind ainda reporta HandlePowerKey=$value; reinicie o logind manualmente (sessões SSH permanecem): systemctl restart systemd-logind"
  exit 2
fi
echo "HandlePowerKey=$value"
systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1 && echo "sshd ativo"
