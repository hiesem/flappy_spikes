#!/usr/bin/env bash
# Firestore TTL policy for the versus data (PRD-2 §3.13 retention, ARCH §6.2):
# players/{uid}.expireAt — inactive players vanish 60 days after their last write.
# (Pool / recent entries live inside documents, so the function and the daily
# sweepPools trim those; TTL can only delete whole documents.)
#
# `firebase deploy --only firestore:indexes` also applies the policy (the
# `"ttl": true` field override in firestore.indexes.json). This script sets or
# checks it directly through the Firestore Admin REST API, e.g. when the CLI
# path is not used or to verify the state.
#
# Usage:  functions/scripts/set_ttl.sh [enable|disable|status]   (default: status)
# Auth:   ACCESS_TOKEN=<oauth token>  or a logged-in `gcloud` (gcloud auth print-access-token).
# Env:    PROJECT (default flappy-spikes-a2b55), DATABASE (default "(default)").
set -euo pipefail

PROJECT="${PROJECT:-flappy-spikes-a2b55}"
DATABASE="${DATABASE:-(default)}"
GROUP="players"
FIELD="expireAt"
action="${1:-status}"

token="${ACCESS_TOKEN:-}"
if [[ -z "$token" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    token="$(gcloud auth print-access-token)"
  else
    echo "No ACCESS_TOKEN and no gcloud. Get a token (e.g. OAuth Playground with the" >&2
    echo "https://www.googleapis.com/auth/datastore scope, or gcloud on another machine) and" >&2
    echo "run: ACCESS_TOKEN=... $0 $action" >&2
    exit 2
  fi
fi

url="https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/${DATABASE}/collectionGroups/${GROUP}/fields/${FIELD}"

case "$action" in
  enable)
    # ttlConfig {} turns the policy on; the field is also exempted from indexing
    # (a monotonically growing timestamp index is a write hotspot and not needed).
    curl -sS -X PATCH -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
      "${url}?updateMask=ttlConfig,indexConfig" \
      -d '{"ttlConfig": {}, "indexConfig": {"indexes": []}}'
    echo
    echo "Requested. The policy takes a few minutes to become ACTIVE: $0 status"
    ;;
  disable)
    curl -sS -X PATCH -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
      "${url}?updateMask=ttlConfig" -d '{}'
    echo
    ;;
  status)
    curl -sS -H "Authorization: Bearer ${token}" "${url}"
    echo
    ;;
  *)
    echo "usage: $0 [enable|disable|status]" >&2
    exit 2
    ;;
esac
