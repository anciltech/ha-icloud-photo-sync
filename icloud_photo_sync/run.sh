#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
CONFIG_DIR="/config"
CONFIG_FILE="${CONFIG_DIR}/icloudpd.conf"
STATE_TMP_ROOT="${CONFIG_DIR}/tmp"
TMP_DIR="${STATE_TMP_ROOT}/icloudpd"
TMP_LINK="/tmp/icloudpd"
MOUNT_MARKER=".mounted"

if [ ! -f "${OPTIONS_FILE}" ]; then
  echo "Missing add-on options at ${OPTIONS_FILE}" >&2
  exit 1
fi

json_get() {
  jq -r "$1" "${OPTIONS_FILE}"
}

APPLE_ID="$(json_get '.apple_id')"
TIMEZONE="$(json_get '.timezone')"
DOWNLOAD_PATH="$(json_get '.download_path')"
DOWNLOAD_INTERVAL="$(json_get '.download_interval')"
NOTIFICATION_DAYS="$(json_get '.notification_days')"
FOLDER_STRUCTURE="$(json_get '.folder_structure')"
PHOTO_SIZE="$(json_get '.photo_size | if type == "array" then join(",") else . end')"
CONVERT_HEIC_TO_JPEG="$(json_get '.convert_heic_to_jpeg')"
DELETE_HEIC_AFTER_CONVERSION="$(json_get '.delete_heic_after_conversion // true')"
PHOTO_ALBUM="$(json_get '.photo_album')"
PHOTO_LIBRARY="$(json_get '.photo_library')"
SKIP_ALBUM="$(json_get '.skip_album')"
SKIP_LIBRARY="$(json_get '.skip_library')"
SKIP_VIDEOS="$(json_get '.skip_videos')"
SKIP_LIVE_PHOTOS="$(json_get '.skip_live_photos')"
AUTO_DELETE="$(json_get '.auto_delete')"
RECENT_ONLY="$(json_get '.recent_only')"
DEBUG_LOGGING="$(json_get '.debug_logging // false')"
LOCAL_USER="icloudpd"
LOCAL_USER_ID="1000"
LOCAL_GROUP="icloudpd"
LOCAL_GROUP_ID="1000"
KEEP_UNICODE="false"
LIVE_PHOTO_MOV_FILENAME_POLICY="suffix"
FILE_MATCH_POLICY="name-size-dedup-with-suffix"
DOWNLOAD_DELAY="0"
SET_EXIF_DATE_TIME="false"
DELETE_AFTER_DOWNLOAD="false"
DELETE_EMPTY_DIRECTORIES="false"
ALIGN_RAW="as-is"
SINGLE_PASS="false"
SKIP_CHECK="false"
LIVE_PHOTO_SIZE="original"

if [ -z "${APPLE_ID}" ] || [ "${APPLE_ID}" = "null" ]; then
  echo "apple_id is required in the add-on options." >&2
  exit 1
fi

if ! getent group "${LOCAL_GROUP}" >/dev/null 2>&1; then
  addgroup -g "${LOCAL_GROUP_ID}" "${LOCAL_GROUP}" >/dev/null 2>&1 || true
fi

if ! id -u "${LOCAL_USER}" >/dev/null 2>&1; then
  adduser -D -u "${LOCAL_USER_ID}" -G "${LOCAL_GROUP}" "${LOCAL_USER}" >/dev/null 2>&1 || true
fi

mkdir -p "${CONFIG_DIR}" "${DOWNLOAD_PATH}" "${STATE_TMP_ROOT}" "${TMP_DIR}"
touch "${DOWNLOAD_PATH}/${MOUNT_MARKER}"

rm -rf "${TMP_LINK}" >/dev/null 2>&1 || true
ln -s "${TMP_DIR}" "${TMP_LINK}" >/dev/null 2>&1 || true

chown -R "${LOCAL_USER}:${LOCAL_GROUP}" "${CONFIG_DIR}" "${DOWNLOAD_PATH}" "${STATE_TMP_ROOT}" >/dev/null 2>&1 || true
chmod 700 "${TMP_DIR}" >/dev/null 2>&1 || true

CONFIG_TMP="$(mktemp "${CONFIG_DIR}/icloudpd.conf.XXXXXX")"

cat > "${CONFIG_TMP}" <<EOF
apple_id=${APPLE_ID}
user=${LOCAL_USER}
user_id=${LOCAL_USER_ID}
group=${LOCAL_GROUP}
group_id=${LOCAL_GROUP_ID}
authentication_type=MFA
download_path=${DOWNLOAD_PATH}
download_interval=${DOWNLOAD_INTERVAL}
notification_days=${NOTIFICATION_DAYS}
folder_structure=${FOLDER_STRUCTURE}
photo_size=${PHOTO_SIZE}
convert_heic_to_jpeg=${CONVERT_HEIC_TO_JPEG}
keep_unicode=${KEEP_UNICODE}
live_photo_mov_filename_policy=${LIVE_PHOTO_MOV_FILENAME_POLICY}
file_match_policy=${FILE_MATCH_POLICY}
download_delay=${DOWNLOAD_DELAY}
set_exif_date_time=${SET_EXIF_DATE_TIME}
delete_after_download=${DELETE_AFTER_DOWNLOAD}
delete_empty_directories=${DELETE_EMPTY_DIRECTORIES}
align_raw=${ALIGN_RAW}
single_pass=${SINGLE_PASS}
skip_check=${SKIP_CHECK}
live_photo_size=${LIVE_PHOTO_SIZE}
skip_videos=${SKIP_VIDEOS}
skip_live_photos=${SKIP_LIVE_PHOTOS}
auto_delete=${AUTO_DELETE}
recent_only=${RECENT_ONLY}
debug_logging=${DEBUG_LOGGING}
EOF

append_if_set() {
  key="$1"
  value="$2"
  if [ -n "${value}" ] && [ "${value}" != "null" ]; then
    printf '%s="%s"\n' "${key}" "${value}" >> "${CONFIG_TMP}"
  fi
}

append_if_set "photo_album" "${PHOTO_ALBUM}"
append_if_set "photo_library" "${PHOTO_LIBRARY}"
append_if_set "skip_album" "${SKIP_ALBUM}"
append_if_set "skip_library" "${SKIP_LIBRARY}"

cleanup_converted_heic_originals() {
  if [ "${CONVERT_HEIC_TO_JPEG}" != "true" ] || [ "${DELETE_HEIC_AFTER_CONVERSION}" != "true" ]; then
    return
  fi

  echo "Removing HEIC originals that have matching JPEG conversions under ${DOWNLOAD_PATH}"
  find "${DOWNLOAD_PATH}" -type f \( -iname '*.heic' -o -iname '*.heif' \) -exec sh -c '
    for original_path do
      dir="${original_path%/*}"
      filename="${original_path##*/}"
      basename="${filename%.*}"
      converted=""

      for extension in jpg JPG jpeg JPEG; do
        candidate="${dir}/${basename}.${extension}"
        if [ -f "${candidate}" ]; then
          converted="${candidate}"
          break
        fi
      done

      if [ -n "${converted}" ]; then
        rm -f "${original_path}" && echo "Removed converted original: ${original_path}"
      fi
    done
  ' sh {} +
}

mv "${CONFIG_TMP}" "${CONFIG_FILE}"
chown "${LOCAL_USER}:${LOCAL_GROUP}" "${CONFIG_FILE}" >/dev/null 2>&1 || true
chmod 600 "${CONFIG_FILE}" >/dev/null 2>&1 || true

export TZ="${TIMEZONE}"
export config_file="${CONFIG_FILE}"
export XDG_DATA_HOME="${CONFIG_DIR}"
export ENV="/etc/profile"

echo "Prepared ${CONFIG_FILE} for ${APPLE_ID}"
echo "Download destination: ${DOWNLOAD_PATH}"
echo "Runtime user/group: ${LOCAL_USER}:${LOCAL_GROUP}"
echo "Temporary work dir: ${TMP_DIR}"
echo "If this is the first run, initialise the keyring and MFA cookie from the SSH add-on terminal."

trap 'exit 0' TERM INT

echo "Starting managed sync loop for ${PHOTO_ALBUM:-iCloud Photos}"

while true; do
  touch "${DOWNLOAD_PATH}/${MOUNT_MARKER}" >/dev/null 2>&1 || true
  chown -R "${LOCAL_USER}:${LOCAL_GROUP}" "${CONFIG_DIR}" "${DOWNLOAD_PATH}" "${STATE_TMP_ROOT}" >/dev/null 2>&1 || true
  chmod 700 "${TMP_DIR}" >/dev/null 2>&1 || true

  /usr/local/bin/sync-icloud.sh || true
  cleanup_converted_heic_originals

  echo "Sleeping ${DOWNLOAD_INTERVAL}s until next sync"
  sleep "${DOWNLOAD_INTERVAL}" &
  wait $!
done
