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
APPLE_PASSWORD="$(json_get '.apple_password // ""')"
MFA_CODE="$(json_get '.mfa_code // ""')"
TIMEZONE="$(json_get '.timezone')"
DOWNLOAD_PATH="$(json_get '.download_path')"
DOWNLOAD_INTERVAL="$(json_get '.download_interval')"
NOTIFICATION_DAYS="$(json_get '.notification_days')"
FOLDER_STRUCTURE="$(json_get '.folder_structure')"
PHOTO_SIZE="$(json_get '.photo_size | if type == "array" then join(",") else . end')"
CONVERT_HEIC_TO_JPEG="$(json_get '.convert_heic_to_jpeg')"
DELETE_HEIC_AFTER_CONVERSION="$(json_get '.delete_heic_after_conversion // true')"
DOWNSCALE_DISPLAY_IMAGES="$(json_get '.downscale_display_images // false')"
DISPLAY_MAX_WIDTH="$(json_get '.display_max_width // 1920')"
DISPLAY_MAX_HEIGHT="$(json_get '.display_max_height // 1080')"
DISPLAY_JPEG_QUALITY="$(json_get '.display_jpeg_quality // 82')"
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
KEYRING_FILE="${CONFIG_DIR}/python_keyring/keyring_pass.cfg"
COOKIE_FILE="$(printf '%s' "${APPLE_ID}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]//g')"
COOKIE_PATH="${CONFIG_DIR}/${COOKIE_FILE}"

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

has_keyring() {
  [ -f "${KEYRING_FILE}" ] && grep -q '=' "${KEYRING_FILE}"
}

has_mfa_cookie() {
  [ -f "${COOKIE_PATH}" ] && grep -q 'X-APPLE-WEBAUTH-USER' "${COOKIE_PATH}"
}

auth_ready() {
  has_keyring && has_mfa_cookie
}

run_option_based_auth() {
  if auth_ready; then
    if [ -n "${APPLE_PASSWORD}" ] || [ -n "${MFA_CODE}" ]; then
      echo "Apple authentication is already ready. Clear apple_password and mfa_code from the add-on options after this start."
    fi
    return 0
  fi

  if [ -z "${MFA_CODE}" ] || [ "${MFA_CODE}" = "null" ]; then
    echo "Apple authentication is not ready yet."
    echo "Set mfa_code in the add-on options, save, then start or restart the add-on."
    echo "After the log says authentication succeeded, clear apple_password and mfa_code from the options."
    return 1
  fi

  if ! has_keyring && { [ -z "${APPLE_PASSWORD}" ] || [ "${APPLE_PASSWORD}" = "null" ]; }; then
    echo "Apple authentication needs apple_password because the keyring is not initialized yet."
    echo "Set apple_password and mfa_code in the add-on options, save, then start or restart the add-on."
    return 1
  fi

  if ! command -v expect >/dev/null 2>&1; then
    echo "Apple authentication needs expect, but expect is not installed in this image." >&2
    return 1
  fi

  echo "Starting Apple authentication from add-on options for ${APPLE_ID}."
  echo "Apple may ask your trusted devices to approve this sign-in; if the code expires, enter a fresh code and restart the add-on."

  export HA_ICLOUD_SETUP_PASSWORD="${APPLE_PASSWORD}"
  export HA_ICLOUD_SETUP_MFA_CODE="${MFA_CODE}"

  if expect <<'EOF'
set timeout 600
set stty_init -echo

proc send_secret {value} {
  send -- "$value\r"
}

spawn /usr/local/bin/sync-icloud.sh --Initialise

expect {
  -nocase -re {(enter )?icloud password[^:]*:} {
    send_secret $env(HA_ICLOUD_SETUP_PASSWORD)
    exp_continue
  }
  -nocase -re {save password.*:} {
    send -- "y\r"
    exp_continue
  }
  -nocase -re {which device.*:} {
    send -- "\r"
    exp_continue
  }
  -nocase -re {please choose an option.*:} {
    send -- "1\r"
    exp_continue
  }
  -nocase -re {(validation|verification|authentication|two-factor).*code.*:} {
    send_secret $env(HA_ICLOUD_SETUP_MFA_CODE)
    exp_continue
  }
  eof {
    catch wait result
    exit [lindex $result 3]
  }
  timeout {
    exit 124
  }
}
EOF
  then
    unset HA_ICLOUD_SETUP_PASSWORD HA_ICLOUD_SETUP_MFA_CODE
    if auth_ready; then
      echo "Apple authentication succeeded. Clear apple_password and mfa_code from the add-on options, then keep the add-on running normally."
      return 0
    fi
    echo "Apple authentication command finished, but the keyring or MFA cookie was not found." >&2
    return 1
  fi

  unset HA_ICLOUD_SETUP_PASSWORD HA_ICLOUD_SETUP_MFA_CODE
  echo "Apple authentication failed. Enter a fresh mfa_code in the add-on options and restart the add-on." >&2
  return 1
}

cleanup_empty_jpeg_placeholders() {
  if [ "${CONVERT_HEIC_TO_JPEG}" != "true" ]; then
    return
  fi

  echo "Removing empty JPEG placeholders that still have HEIC/HEIF originals under ${DOWNLOAD_PATH}"
  find "${DOWNLOAD_PATH}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -size 0 -exec sh -c '
    for jpeg_path do
      dir="${jpeg_path%/*}"
      filename="${jpeg_path##*/}"
      basename="${filename%.*}"
      original=""

      for extension in HEIC heic HEIF heif; do
        candidate="${dir}/${basename}.${extension}"
        if [ -f "${candidate}" ]; then
          original="${candidate}"
          break
        fi
      done

      if [ -n "${original}" ]; then
        rm -f "${jpeg_path}" && echo "Removed empty JPEG placeholder: ${jpeg_path}"
      fi
    done
  ' sh {} +
}

cleanup_converted_heic_originals() {
  if [ "${CONVERT_HEIC_TO_JPEG}" != "true" ] || [ "${DELETE_HEIC_AFTER_CONVERSION}" != "true" ]; then
    return
  fi

  echo "Removing HEIC originals that have matching non-empty JPEG conversions under ${DOWNLOAD_PATH}"
  find "${DOWNLOAD_PATH}" -type f \( -iname '*.heic' -o -iname '*.heif' \) -exec sh -c '
    for original_path do
      dir="${original_path%/*}"
      filename="${original_path##*/}"
      basename="${filename%.*}"
      converted=""

      for extension in jpg JPG jpeg JPEG; do
        candidate="${dir}/${basename}.${extension}"
        if [ -s "${candidate}" ]; then
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

imagemagick_identify() {
  if command -v identify >/dev/null 2>&1; then
    identify "$@"
  elif command -v magick >/dev/null 2>&1; then
    magick identify "$@"
  else
    return 127
  fi
}

imagemagick_convert() {
  if command -v magick >/dev/null 2>&1; then
    magick "$@"
  elif command -v convert >/dev/null 2>&1; then
    convert "$@"
  else
    return 127
  fi
}

downscale_display_images() {
  if [ "${DOWNSCALE_DISPLAY_IMAGES}" != "true" ]; then
    return
  fi

  if ! command -v identify >/dev/null 2>&1 && ! command -v magick >/dev/null 2>&1; then
    echo "Image downscale requested, but ImageMagick is not installed; skipping" >&2
    return
  fi

  echo "Downscaling oversized JPEG display images under ${DOWNLOAD_PATH} to fit ${DISPLAY_MAX_WIDTH}x${DISPLAY_MAX_HEIGHT} at quality ${DISPLAY_JPEG_QUALITY}"
  find "${DOWNLOAD_PATH}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) | while IFS= read -r image_path; do
    dimensions="$(imagemagick_identify -format '%w %h' "${image_path}[0]" 2>/dev/null || true)"
    if [ -z "${dimensions}" ]; then
      echo "Skipping unreadable image: ${image_path}" >&2
      continue
    fi

    set -- ${dimensions}
    width="$1"
    height="$2"

    if [ "${width}" -le "${DISPLAY_MAX_WIDTH}" ] && [ "${height}" -le "${DISPLAY_MAX_HEIGHT}" ]; then
      continue
    fi

    tmp_path="${image_path}.display-resize.$$.jpg"
    if imagemagick_convert "${image_path}[0]" -auto-orient -resize "${DISPLAY_MAX_WIDTH}x${DISPLAY_MAX_HEIGHT}>" -strip -quality "${DISPLAY_JPEG_QUALITY}" "jpg:${tmp_path}"; then
      touch -r "${image_path}" "${tmp_path}" >/dev/null 2>&1 || true
      chown "${LOCAL_USER}:${LOCAL_GROUP}" "${tmp_path}" >/dev/null 2>&1 || true
      chmod 644 "${tmp_path}" >/dev/null 2>&1 || true
      mv "${tmp_path}" "${image_path}"
      echo "Downscaled display image: ${image_path} (${width}x${height} -> max ${DISPLAY_MAX_WIDTH}x${DISPLAY_MAX_HEIGHT})"
    else
      rm -f "${tmp_path}" >/dev/null 2>&1 || true
      echo "Failed to downscale image: ${image_path}" >&2
    fi
  done
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

run_option_based_auth || true

trap 'exit 0' TERM INT

echo "Starting managed sync loop for ${PHOTO_ALBUM:-iCloud Photos}"

while true; do
  touch "${DOWNLOAD_PATH}/${MOUNT_MARKER}" >/dev/null 2>&1 || true
  chown -R "${LOCAL_USER}:${LOCAL_GROUP}" "${CONFIG_DIR}" "${DOWNLOAD_PATH}" "${STATE_TMP_ROOT}" >/dev/null 2>&1 || true
  chmod 700 "${TMP_DIR}" >/dev/null 2>&1 || true

  if auth_ready; then
    /usr/local/bin/sync-icloud.sh || true
    cleanup_empty_jpeg_placeholders
    cleanup_converted_heic_originals
    downscale_display_images
  else
    echo "Skipping sync until Apple authentication is ready."
    echo "Set mfa_code in the add-on options, plus apple_password if the keyring is not initialized, then restart the add-on."
  fi

  echo "Sleeping ${DOWNLOAD_INTERVAL}s until next sync"
  sleep "${DOWNLOAD_INTERVAL}" &
  wait $!
done
