#!/usr/bin/env bash
# Encrypted, retention-managed off-host Qdrant snapshot backup using Restic.
# This script never initializes or writes a local repository: only remote backends are accepted.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ACTION=${1:-backup}
TAG=atende-ai-local
SOURCE=${BACKUP_SOURCE:-/var/backups/atende-ai-local/qdrant}
REPOSITORY=${RESTIC_REPOSITORY:-}
PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/etc/atende-ai/restic-password}

die() { echo "backup_offsite: $*" >&2; exit 2; }
command -v restic >/dev/null || die "restic não instalado"
command -v jq >/dev/null || die "jq não instalado"
[[ -n "$REPOSITORY" ]] || die "RESTIC_REPOSITORY não configurado"
case "$REPOSITORY" in
  sftp:*|s3:*|rest:*|rclone:*) ;;
  *) die "o repositório precisa usar backend remoto sftp:, s3:, rest: ou rclone:" ;;
esac
[[ -f "$PASSWORD_FILE" && ! -L "$PASSWORD_FILE" ]] || die "arquivo de senha ausente ou inválido"
mode=$(stat -c '%a' "$PASSWORD_FILE")
[[ "$mode" == 600 || "$mode" == 400 ]] || die "permissão do arquivo de senha deve ser 600 ou 400"
export RESTIC_REPOSITORY="$REPOSITORY" RESTIC_PASSWORD_FILE="$PASSWORD_FILE"

case "$ACTION" in
  init)
    restic init
    ;;
  backup)
    [[ $EUID -eq 0 ]] || die "execute como root para ler snapshots locais"
    [[ -d "$SOURCE" ]] || die "diretório de snapshots ausente: $SOURCE"
    KEEP=14 bash "$ROOT/scripts/backup.sh"
    restic backup --host "$(hostname -s)" --tag "$TAG" "$SOURCE"
    restic forget --tag "$TAG" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
    restic check --read-data
    ;;
  check)
    restic check --read-data
    ;;
  restore-test)
    [[ $EUID -eq 0 ]] || die "execute como root para comparar snapshots locais"
    [[ -d "$SOURCE" ]] || die "diretório de snapshots ausente: $SOURCE"
    snapshot=$(restic snapshots --tag "$TAG" --latest 1 --json | jq -r '.[0].id // empty')
    [[ -n "$snapshot" ]] || die "nenhum snapshot remoto com a tag $TAG"
    target=$(mktemp -d /tmp/atende-ai-restic-restore.XXXXXX)
    trap 'rm -rf -- "$target"' EXIT
    restic restore "$snapshot" --target "$target"
    restored="$target$(realpath "$SOURCE")"
    [[ -d "$restored" ]] || die "caminho restaurado não encontrado"
    diff -qr -- "$SOURCE" "$restored"
    echo "restore test OK: snapshot $snapshot"
    ;;
  *)
    die "uso: $0 {init|backup|check|restore-test}"
    ;;
esac
