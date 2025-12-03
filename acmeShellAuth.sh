#!/bin/bash
# TrueNAS ACME DNS Authenticator using acme.sh dnsapi (multi-provider)

set -eo pipefail

##############################################
# Resolve paths relative to this script
##############################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ACME_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"      # /path/to
ACME_DIR="${ACME_BASE}/acme.sh"               # /path/to/acme.sh
ACME_SH="${ACME_DIR}/acme.sh"                 # /path/to/acme.sh/acme.sh
DNSAPI_DIR="${ACME_DIR}/dnsapi"               # /path/to/acme.sh/dnsapi

LOGFILE="${SCRIPT_DIR}/acmeShellAuth.log"
CRED_FILE="${SCRIPT_DIR}/credentials"

##############################################
# Logging helper (to stderr AND logfile)
##############################################

log() {
  local ts
  ts="$(date '+[%Y-%m-%d %H:%M:%S]')"
  # print to stderr and append to logfile
  printf '%s %s\n' "$ts" "$1" | tee -a "$LOGFILE" >&2
}

# Ensure logfile exists with safe permissions
if [ ! -f "$LOGFILE" ]; then
  touch "$LOGFILE"
  chmod 600 "$LOGFILE"
fi

##############################################
# Load provider + credentials
##############################################

if [ ! -f "$CRED_FILE" ]; then
  log "ERROR: credentials file missing: $CRED_FILE"
  exit 1
fi

# shellcheck disable=SC1090
. "$CRED_FILE"

if [ -z "${PROVIDER:-}" ]; then
  log "ERROR: PROVIDER is not defined in credentials"
  exit 1
fi

PROVIDER_SH="${DNSAPI_DIR}/${PROVIDER}.sh"

if [ ! -f "$ACME_SH" ]; then
  log "ERROR: acme.sh not found at: $ACME_SH"
  exit 1
fi

if [ ! -f "$PROVIDER_SH" ]; then
  log "ERROR: Provider script not found: $PROVIDER_SH"
  exit 1
fi

##############################################
# Source acme.sh core and dnsapi provider
##############################################

# shellcheck disable=SC1090
. "$ACME_SH"

# shellcheck disable=SC1090
. "$PROVIDER_SH"

##############################################
# TrueNAS arguments
##############################################

if [ "$#" -ne 4 ]; then
  log "ERROR: Expected 4 args, got $#"
  exit 1
fi

ACTION="$1"   # set | unset
DOMAIN="$2"   # currently unused, but passed by TrueNAS
FQDN="$3"
TOKEN="$4"

log "INFO: ACTION=$ACTION PROVIDER=$PROVIDER FQDN=$FQDN"

##############################################
# Perform the action
##############################################

case "$ACTION" in
  set)
    set +e
    # provider output → tee → shown + logged
    "${PROVIDER}_add" "$FQDN" "$TOKEN" 2>&1 | tee -a "$LOGFILE"
    RET=${PIPESTATUS[0]}
    set -e
    log "INFO: ${PROVIDER}_add returned $RET"
    exit "$RET"
    ;;

  unset)
    set +e
    "${PROVIDER}_rm" "$FQDN" "$TOKEN" 2>&1 | tee -a "$LOGFILE"
    RET=${PIPESTATUS[0]}
    set -e
    log "INFO: ${PROVIDER}_rm returned $RET"
    exit "$RET"
    ;;

  *)
    log "ERROR: Unknown action: $ACTION"
    exit 1
    ;;
esac
