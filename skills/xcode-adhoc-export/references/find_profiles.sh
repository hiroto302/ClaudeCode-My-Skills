#!/bin/bash
# find_profiles.sh - Ad Hoc プロビジョニングプロファイル検出スクリプト
# Usage: bash find_profiles.sh <TEAM_ID> <BUNDLE_ID>
#
# 出力形式: PROFILE:{名前}|EXPIRE:{有効期限}|BUNDLE:{App ID}|TYPE:{exact|wildcard}|CERT:{証明書CN}
# CERT はプロファイルに埋め込まれた証明書のうち、キーチェーンに identity (秘密鍵付き) が
# 存在するものの Common Name。ExportOptions.plist の signingCertificate にそのまま使える。

TEAM_ID="$1"
BUNDLE_ID="$2"

if [ -z "$TEAM_ID" ] || [ -z "$BUNDLE_ID" ]; then
  echo "ERROR: Usage: bash find_profiles.sh <TEAM_ID> <BUNDLE_ID>" >&2
  exit 1
fi

# Xcode 16 以降は UserData 配下、それ以前は MobileDevice 配下に保存される (両方をスキャン)
PROFILES_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)
NOW=$(date +%s)

EXACT_MATCH=""
EXACT_EXPIRE=0
EXACT_FILE=""
WILDCARD_MATCH=""
WILDCARD_EXPIRE=0
WILDCARD_FILE=""

for dir in "${PROFILES_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.mobileprovision; do
    [ -f "$f" ] || continue

    xml=$(security cms -D -i "$f" 2>/dev/null)
    [ -z "$xml" ] && continue

    team=$(echo "$xml" | plutil -extract TeamIdentifier.0 raw -o - -- - 2>/dev/null)
    [ "$team" != "$TEAM_ID" ] && continue

    has_devices=$(echo "$xml" | grep -c "ProvisionedDevices")
    has_all=$(echo "$xml" | grep -c "ProvisionsAllDevices")
    [ "$has_devices" -eq 0 ] && continue
    [ "$has_all" -gt 0 ] && continue

    # development プロファイル (get-task-allow = true) を除外する
    # (Xcode 管理の "iOS Team Provisioning Profile" も ProvisionedDevices を持つため)
    get_task_allow=$(echo "$xml" | plutil -extract "Entitlements.get-task-allow" raw -o - -- - 2>/dev/null)
    [ "$get_task_allow" = "true" ] && continue

    expire_raw=$(echo "$xml" | plutil -extract ExpirationDate raw -o - -- - 2>/dev/null)
    expire_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expire_raw" +%s 2>/dev/null)
    if [ -z "$expire_epoch" ] || [ "$expire_epoch" -le "$NOW" ]; then
      continue
    fi

    name=$(echo "$xml" | plutil -extract Name raw -o - -- - 2>/dev/null)
    app_id=$(echo "$xml" | plutil -extract Entitlements.application-identifier raw -o - -- - 2>/dev/null)

    # exact / wildcard それぞれで有効期限が最も未来のものを選ぶ
    # (証明書更新の移行期に新旧プロファイルが併存しても新しい方を採用する)
    if [ "$app_id" = "${TEAM_ID}.${BUNDLE_ID}" ]; then
      if [ "$expire_epoch" -gt "$EXACT_EXPIRE" ]; then
        EXACT_EXPIRE=$expire_epoch
        EXACT_MATCH="PROFILE:${name}|EXPIRE:${expire_raw}|BUNDLE:${app_id}|TYPE:exact"
        EXACT_FILE="$f"
      fi
    elif echo "$app_id" | grep -qF '.*'; then
      if [ "$expire_epoch" -gt "$WILDCARD_EXPIRE" ]; then
        WILDCARD_EXPIRE=$expire_epoch
        WILDCARD_MATCH="PROFILE:${name}|EXPIRE:${expire_raw}|BUNDLE:${app_id}|TYPE:wildcard"
        WILDCARD_FILE="$f"
      fi
    fi
  done
done

SELECTED=""
SELECTED_FILE=""
if [ -n "$EXACT_MATCH" ]; then
  SELECTED="$EXACT_MATCH"
  SELECTED_FILE="$EXACT_FILE"
elif [ -n "$WILDCARD_MATCH" ]; then
  SELECTED="$WILDCARD_MATCH"
  SELECTED_FILE="$WILDCARD_FILE"
else
  echo "ERROR: No valid Ad Hoc provisioning profile found for Team=${TEAM_ID}, Bundle=${BUNDLE_ID}" >&2
  exit 1
fi

# プロファイル埋め込み証明書のうち、キーチェーンに identity (秘密鍵付き) が存在する CN を採用する
# (signingCertificate はプロファイルに含まれる証明書と一致している必要がある)
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null)
CERT_CN=""
xml=$(security cms -D -i "$SELECTED_FILE" 2>/dev/null)
for i in 0 1 2 3 4; do
  cert_b64=$(echo "$xml" | plutil -extract "DeveloperCertificates.$i" raw -o - -- - 2>/dev/null)
  [ -z "$cert_b64" ] && break
  cn=$(echo "$cert_b64" | base64 -d 2>/dev/null \
       | openssl x509 -inform DER -noout -subject -nameopt multiline 2>/dev/null \
       | sed -n 's/^ *commonName *= //p')
  [ -z "$cn" ] && continue
  if echo "$IDENTITIES" | grep -qF "\"$cn\""; then
    CERT_CN="$cn"
    break
  fi
done

if [ -z "$CERT_CN" ]; then
  echo "WARNING: プロファイルに埋め込まれた証明書に対応する identity (秘密鍵) がキーチェーンに見つかりません" >&2
fi

echo "${SELECTED}|CERT:${CERT_CN}"
exit 0
