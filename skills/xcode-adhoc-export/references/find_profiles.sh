#!/bin/bash
# find_profiles.sh - Ad Hoc プロビジョニングプロファイル検出スクリプト
# Usage: bash find_profiles.sh <TEAM_ID> <BUNDLE_ID>

TEAM_ID="$1"
BUNDLE_ID="$2"

if [ -z "$TEAM_ID" ] || [ -z "$BUNDLE_ID" ]; then
  echo "ERROR: Usage: bash find_profiles.sh <TEAM_ID> <BUNDLE_ID>" >&2
  exit 1
fi

PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
NOW=$(date +%s)

EXACT_MATCH=""
WILDCARD_MATCH=""

for f in "$PROFILES_DIR"/*.mobileprovision; do
  [ -f "$f" ] || continue

  xml=$(security cms -D -i "$f" 2>/dev/null)
  [ -z "$xml" ] && continue

  team=$(echo "$xml" | plutil -extract TeamIdentifier.0 raw -o - -- - 2>/dev/null)
  [ "$team" != "$TEAM_ID" ] && continue

  has_devices=$(echo "$xml" | grep -c "ProvisionedDevices")
  has_all=$(echo "$xml" | grep -c "ProvisionsAllDevices")
  [ "$has_devices" -eq 0 ] && continue
  [ "$has_all" -gt 0 ] && continue

  expire_raw=$(echo "$xml" | plutil -extract ExpirationDate raw -o - -- - 2>/dev/null)
  expire_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expire_raw" +%s 2>/dev/null)
  if [ -z "$expire_epoch" ] || [ "$expire_epoch" -le "$NOW" ]; then
    continue
  fi

  name=$(echo "$xml" | plutil -extract Name raw -o - -- - 2>/dev/null)
  app_id=$(echo "$xml" | plutil -extract Entitlements.application-identifier raw -o - -- - 2>/dev/null)

  if [ "$app_id" = "${TEAM_ID}.${BUNDLE_ID}" ]; then
    EXACT_MATCH="PROFILE:${name}|EXPIRE:${expire_raw}|BUNDLE:${app_id}|TYPE:exact"
  elif echo "$app_id" | grep -qF '.*'; then
    if [ -z "$WILDCARD_MATCH" ]; then
      WILDCARD_MATCH="PROFILE:${name}|EXPIRE:${expire_raw}|BUNDLE:${app_id}|TYPE:wildcard"
    fi
  fi
done

if [ -n "$EXACT_MATCH" ]; then
  echo "$EXACT_MATCH"
  exit 0
elif [ -n "$WILDCARD_MATCH" ]; then
  echo "$WILDCARD_MATCH"
  exit 0
else
  echo "ERROR: No valid Ad Hoc provisioning profile found for Team=${TEAM_ID}, Bundle=${BUNDLE_ID}" >&2
  exit 1
fi
