#!/usr/bin/env bash
#
# distribution.mirrorsnap.net へ .ipa をアップロードするスクリプト
# API 仕様: api-automation-guide.md (v1.0.2) / 2026-09-25 に実 API で動作確認済み
#
# 使い方:
#   新規追加:
#     upload.sh --ipa ./MirrorSnap.ipa --title "260828_XXX案件" \
#               --product-id 01KNNFDF8GR32781199JWR9QJ4 [--environment test|production]
#   バージョン更新 (元アプリの QR を引き継ぐ):
#     upload.sh --ipa ./MirrorSnap.ipa --title "260828_XXX案件" \
#               --product-id 01KN... --source-app-id 01KZ... [--app-version 6.0]
#   アップロードのみ再試行 (POST /apps は冪等でないため、作成済みレコードに対して):
#     upload.sh --ipa ./MirrorSnap.ipa --app-id 01M3...
#
# 認証情報:
#   --credentials <path> で指定 (既定: ~/.config/mirrorsnap-distribution/env)。
#   Unity の Distribution Uploader と同じファイルを共有する (export MS_API/MS_WEB/MS_EMAIL/MS_PASSWORD)
#
set -euo pipefail

# ─── 引数 ───────────────────────────────────
IPA_PATH="" TITLE="" PRODUCT_ID="" SOURCE_APP_ID="" APP_VERSION=""
ENVIRONMENT="test" NOTE="" APP_ID="" END_DATE="" QR_EXPIRES_AT=""
CREDENTIALS="$HOME/.config/mirrorsnap-distribution/env"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ipa)            IPA_PATH="$2"; shift 2 ;;
    --title)          TITLE="$2"; shift 2 ;;
    --product-id)     PRODUCT_ID="$2"; shift 2 ;;
    --source-app-id)  SOURCE_APP_ID="$2"; shift 2 ;;
    --app-version)    APP_VERSION="$2"; shift 2 ;;
    --environment)    ENVIRONMENT="$2"; shift 2 ;;
    --note)           NOTE="$2"; shift 2 ;;
    --app-id)         APP_ID="$2"; shift 2 ;;
    --end-date)       END_DATE="$2"; shift 2 ;;         # operationEndDate YYYY-MM-DD
    --qr-expires-at)  QR_EXPIRES_AT="$2"; shift 2 ;;    # tokenExpiresAt YYYY-MM-DD
    --credentials)    CREDENTIALS="$2"; shift 2 ;;
    -h|--help)        usage ;;
    *) echo "不明な引数: $1" >&2; usage ;;
  esac
done

[ -n "$IPA_PATH" ] || { echo "--ipa は必須です" >&2; exit 1; }
[ -f "$IPA_PATH" ] || { echo "IPA が見つかりません: $IPA_PATH" >&2; exit 1; }
if [ -z "$APP_ID" ]; then
  [ -n "$TITLE" ]      || { echo "--title は必須です (--app-id 指定時を除く)" >&2; exit 1; }
  [ -n "$PRODUCT_ID" ] || { echo "--product-id は必須です (--app-id 指定時を除く)" >&2; exit 1; }
fi

# ─── 認証情報 ───────────────────────────────
[ -f "$CREDENTIALS" ] || { echo "認証情報ファイルがありません: $CREDENTIALS" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CREDENTIALS"
: "${MS_API:?MS_API が未設定です}"
: "${MS_EMAIL:?MS_EMAIL が未設定です}"
: "${MS_PASSWORD:?MS_PASSWORD が未設定です}"
MS_WEB="${MS_WEB:-https://distribution.mirrorsnap.net}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# API 呼び出し。レスポンス本文はファイルに保存する
# (note 欄等に制御文字が入り得るため、jq へ直接パイプしない)
# 使い方: call <出力ファイル> <期待ステータス> <curl引数...>
call() {
  local out="$1" expect="$2"; shift 2
  local code
  code=$(curl -sS -o "$out" -w '%{http_code}' "$@")
  if [ "$code" != "$expect" ]; then
    echo "✖ HTTP $code (期待: $expect)" >&2
    cat "$out" >&2; echo >&2
    return 1
  fi
}

echo "▶ ログイン ($MS_EMAIL)"
call "$TMP/login.json" 200 -X POST "$MS_API/auth/login" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg e "$MS_EMAIL" --arg p "$MS_PASSWORD" '{email:$e, password:$p}')"
TOKEN=$(jq -r '.idToken' "$TMP/login.json")
auth() { call "$@" -H "Authorization: Bearer $TOKEN"; }

# ─── アプリレコード作成 (--app-id 指定時はスキップ) ───
if [ -z "$APP_ID" ]; then
  echo "▶ IPA を解析"
  unzip -o -q "$IPA_PATH" -d "$TMP/ipa" 'Payload/*/Info.plist' 'Payload/*/embedded.mobileprovision' || true
  INFO_PLIST=$(find "$TMP/ipa/Payload" -maxdepth 2 -name 'Info.plist' 2>/dev/null | head -1)
  PROVISION=$(find "$TMP/ipa/Payload" -maxdepth 2 -name 'embedded.mobileprovision' 2>/dev/null | head -1)
  [ -n "$INFO_PLIST" ] || { echo "Info.plist が見つかりません。IPA が壊れていないか確認してください" >&2; exit 1; }

  INFO_B64=$(base64 < "$INFO_PLIST" | tr -d '\n')
  PROV_B64=""
  [ -n "$PROVISION" ] && PROV_B64=$(base64 < "$PROVISION" | tr -d '\n')
  jq -n --arg i "$INFO_B64" --arg m "$PROV_B64" \
    '{infoPlist:$i, mobileprovision:(if $m == "" then null else $m end)}' > "$TMP/analyze_req.json"
  auth "$TMP/analyze.json" 200 -X POST "$MS_API/apps/analyze-ipa-content" \
    -H 'Content-Type: application/json' --data @"$TMP/analyze_req.json"
  IPA_METADATA=$(jq '.metadata' "$TMP/analyze.json")
  BUNDLE_ID=$(jq -r '.metadata.bundleIdentifier' "$TMP/analyze.json")
  echo "  Bundle ID : $BUNDLE_ID"
  echo "  プロファイル期限: $(jq -r '.metadata.profileExpirationDate' "$TMP/analyze.json")"

  # バージョン: 未指定なら sourceAppId ありは next-version、なしは IPA の値
  if [ -z "$APP_VERSION" ]; then
    if [ -n "$SOURCE_APP_ID" ]; then
      auth "$TMP/next.json" 200 "$MS_API/apps/$SOURCE_APP_ID/next-version"
      APP_VERSION=$(jq -r '.nextVersion' "$TMP/next.json")
      echo "  次バージョン(自動採番): $APP_VERSION"
    else
      APP_VERSION=$(jq -r '.metadata.appVersion' "$TMP/analyze.json")
      echo "  バージョン(IPA から): $APP_VERSION"
    fi
  fi

  echo "▶ アプリを登録 (environment=$ENVIRONMENT$([ -n "$SOURCE_APP_ID" ] && echo ", バージョン更新: $SOURCE_APP_ID" || echo ", 新規追加"))"
  jq -n \
    --arg title "$TITLE" --arg productId "$PRODUCT_ID" \
    --arg bundleId "$BUNDLE_ID" --arg version "$APP_VERSION" \
    --arg env "$ENVIRONMENT" --arg note "$NOTE" \
    --arg sourceAppId "$SOURCE_APP_ID" \
    --arg endDate "$END_DATE" --arg qrExpiresAt "$QR_EXPIRES_AT" \
    --argjson ipaMetadata "$IPA_METADATA" \
    '{title:$title, productId:$productId, appType:"ios",
      bundleIdentifier:$bundleId, appVersion:$version,
      environment:$env, ipaMetadata:$ipaMetadata}
     + (if $note        != "" then {note:$note}                     else {} end)
     + (if $sourceAppId != "" then {sourceAppId:$sourceAppId}       else {} end)
     + (if $endDate     != "" then {operationEndDate:$endDate}      else {} end)
     + (if $qrExpiresAt != "" then {tokenExpiresAt:$qrExpiresAt}    else {} end)' > "$TMP/create_req.json"
  auth "$TMP/create.json" 201 -X POST "$MS_API/apps" \
    -H 'Content-Type: application/json' --data @"$TMP/create_req.json"
  APP_ID=$(jq -r '.app.id' "$TMP/create.json")
  echo "  appId: $APP_ID"
else
  echo "▶ 既存レコード $APP_ID へアップロードします (作成はスキップ)"
fi

# ─── アップロード (⑤〜⑦のみリトライ。POST /apps は冪等でないため再実行しない) ───
FILE_NAME=$(basename "$IPA_PATH")
CONTENT_TYPE="application/octet-stream"

upload_once() {
  echo "▶ アップロード先を発行"
  auth "$TMP/upload.json" 200 -X POST "$MS_API/apps/$APP_ID/upload" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg f "$FILE_NAME" --arg c "$CONTENT_TYPE" '{fileName:$f, contentType:$c}')"
  local upload_url upload_id
  upload_url=$(jq -r '.uploadUrl' "$TMP/upload.json")
  upload_id=$(jq -r '.uploadId' "$TMP/upload.json")

  echo "▶ ファイルを送信 ($(du -h "$IPA_PATH" | cut -f1 | tr -d ' '))"
  curl -sS --fail-with-body -X PUT "$upload_url" \
    -H "Content-Type: $CONTENT_TYPE" --upload-file "$IPA_PATH" \
    -w '  PUT: HTTP %{http_code} / %{size_upload} bytes / %{time_total}s\n'

  echo "▶ 完了を確定"
  auth "$TMP/complete.json" 200 -X POST "$MS_API/apps/$APP_ID/upload/complete" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg u "$upload_id" '{uploadId:$u}')"
}

OK=0
for attempt in 1 2 3; do
  if upload_once; then OK=1; break; fi
  echo "⚠ アップロード失敗 (試行 $attempt/3)。⑤から再試行します" >&2
  sleep 3
done
if [ "$OK" != 1 ]; then
  echo "✖ アップロードに失敗しました。レコード $APP_ID は作成済みなので、" >&2
  echo "  再試行は: $0 --ipa \"$IPA_PATH\" --app-id $APP_ID" >&2
  exit 1
fi

echo
echo "✅ 完了"
echo "  タイトル   : $(jq -r '.app.title' "$TMP/complete.json")"
echo "  バージョン : $(jq -r '.app.appVersion' "$TMP/complete.json")"
echo "  ファイル   : $(jq -r '.app.fileName' "$TMP/complete.json")"
echo "  環境       : $(jq -r '.app.environment' "$TMP/complete.json")"
echo "  管理画面   : $MS_WEB/apps/$(jq -r '.app.id' "$TMP/complete.json")"
# インストール URL (itms-services://...) と配布リンクトークンは表示しない。
# QR の表示・共有は管理画面から行う
