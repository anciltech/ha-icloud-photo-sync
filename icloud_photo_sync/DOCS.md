# iCloud Photo Sync

Sync selected iCloud Photos content into Home Assistant media storage for dashboard playback.

This add-on wraps [`boredazfcuk/docker-icloudpd`](https://github.com/boredazfcuk/docker-icloudpd). Apple authentication, MFA cookies, download behavior, album filtering, shared-library support, and re-authentication are provided by `icloudpd`.

## First-Run Checklist

1. In Home Assistant, go to `Settings -> Add-ons -> Add-on Store`.
2. Open the top-right menu and choose `Repositories`.
3. Add this repository URL:

   ```text
   https://github.com/anciltech/ha-icloud-photo-sync
   ```

4. Install `iCloud Photo Sync`.
5. Open the add-on options and set at least `apple_id`, `photo_album`, and `download_path`.
6. Temporarily enter `apple_password` and the current six-digit Apple code in `mfa_code`.
7. Start the add-on and confirm the log says `Apple authentication succeeded`.
8. Clear `apple_password` and `mfa_code` from the add-on options.
9. Confirm the log shows a successful sync.
10. Open Home Assistant Media Browser and verify `/media/icloud_photos` contains the synced album.
11. Point a dashboard media card at `media-source://media_source/local/icloud_photos`.

This is a Home Assistant add-on repository, not a HACS package.

## Configure

Typical still-photo display:

```yaml
apple_id: "your-apple-id@example.com"
apple_password: ""
mfa_code: ""
timezone: "Europe/Zurich"
download_path: "/media/icloud_photos"
download_interval: 86400
notification_days: 7
folder_structure: "{:%Y/%m/%d}"
photo_size: "original"
convert_heic_to_jpeg: true
delete_heic_after_conversion: true
downscale_display_images: true
display_max_width: 1920
display_max_height: 1080
display_jpeg_quality: 82
photo_album: "Favorites"
photo_library: ""
skip_album: ""
skip_library: ""
skip_videos: true
skip_live_photos: true
auto_delete: false
recent_only: 200
debug_logging: false
```

Live Photo display with companion videos available:

```yaml
apple_id: "your-apple-id@example.com"
apple_password: ""
mfa_code: ""
download_path: "/media/icloud_photos"
photo_album: "Favorites"
convert_heic_to_jpeg: true
delete_heic_after_conversion: true
downscale_display_images: true
display_max_width: 1920
display_max_height: 1080
display_jpeg_quality: 82
skip_videos: false
skip_live_photos: false
recent_only: 200
```

Credential handling:

- Put the Apple ID in the add-on config.
- Put the Apple password and six-digit Apple code in `apple_password` and `mfa_code` only while authenticating.
- Clear `apple_password` and `mfa_code` after the log says authentication succeeded.
- Do not commit or paste Apple passwords into GitHub issues or chat.

## First-Time Apple Authentication

The upstream container stores the Apple password in its own keyring and creates the MFA cookie. This add-on feeds the first-time prompts from temporary Home Assistant add-on options so you do not need an HAOS terminal.

Setup flow:

1. Enter `apple_id`, `apple_password`, and `mfa_code` in the add-on options.
2. Start or restart the add-on.
3. Approve the Apple sign-in request on your trusted device when prompted.
4. Watch the add-on log for `Apple authentication succeeded`.
5. Clear `apple_password` and `mfa_code` from the add-on options.

If Apple asks for a new code or the code expires, enter a fresh `mfa_code` and restart the add-on. The setup fields are not written to `icloudpd.conf`; normal syncs use the keyring and cookie under the add-on `/config` volume.

## After Authentication

1. Restart the add-on.
2. Open the add-on log and wait for `icloudpd` to finish a sync pass.
3. In Home Assistant, open Media Browser and browse to `Local Media -> icloud_photos`.
4. If you configured `photo_album`, confirm that album folder exists below `icloud_photos`.
5. Use that media-source path in the display card:

   ```text
   media-source://media_source/local/icloud_photos
   ```

   For one album folder, append the album name:

   ```text
   media-source://media_source/local/icloud_photos/Favorites
   ```

## Re-Authentication

`icloudpd` cookie auth typically needs renewal periodically.

When it expires, enter a fresh `mfa_code` in the add-on options and restart the add-on. If the Apple password changed or the keyring was removed, also enter `apple_password`. Clear both setup fields again after the log says authentication succeeded.

## Choosing Which Photos Get Pulled

You do not need to pull the whole library.

- `photo_album: "Favorites"` pulls one named album.
- `photo_album: "Vacation 2026"` pulls one named custom album.
- `photo_album: "Favorites,Landscapes"` can pull multiple albums, but that causes multiple runs and may increase re-auth pressure.
- `photo_library: "all libraries"` or a named shared library pulls shared-library content.
- `recent_only: 200` limits the sync to the most recently added items.
- `skip_videos: true` keeps the display library photo-only.
- `skip_live_photos: true` avoids Live Photo companion videos.
- `skip_videos: false` and `skip_live_photos: false` keeps video files and Live Photo companions for cards that support them.
- `convert_heic_to_jpeg: true` adds JPEG copies for HEIC/HEIF photos.
- After each sync, the wrapper also converts any remaining HEIC/HEIF originals that do not already have a valid JPEG display file. It tries `heif-convert`, ImageMagick, and Pillow HEIF in that order so dashboards do not need browser-side HEIC conversion.
- `delete_heic_after_conversion: true` removes only HEIC/HEIF originals that have a same-folder non-empty JPEG/JPG conversion, leaving videos and Live Photo MOV companions controlled by the video options.
- `downscale_display_images: true` rewrites oversized JPEG/JPG display copies after each sync so they fit within `display_max_width` x `display_max_height`.
- `display_jpeg_quality: 82` is a good starting point for a 1080p dashboard panel; leave downscaling disabled if `/media/icloud_photos` should keep archive-quality originals.

Important upstream limits:

- Album filtering is supported.
- Shared-library sync is supported.
- Apple Photos search queries such as `mountains` are not a documented selector.
- Apple's `Featured Photos` feed is not a documented selector.

## Folder Structure

`folder_structure` is mainly for full-library syncs.

- Default: `"{:%Y/%m/%d}"` keeps files split by date, which reduces filename collisions.
- `none` gives a flat folder, but upstream warns this can skip files when iCloud has duplicate filenames.
- If you use `photo_album`, the downloader stores files under the album name, so the date structure matters less.

## Dashboard Playback

Home Assistant exposes `/media/icloud_photos` through Media Source at:

```text
media-source://media_source/local/icloud_photos
```

For the AncilTech `ha-media-card` fork at `https://github.com/anciltech/ha-media-card/tree/feature/icloud-live-photos`, use:

```yaml
type: custom:media-card
icloud_photos:
  enabled: true
  media_source_path: media-source://media_source/local/icloud_photos
live_photo:
  enabled: true
  still_duration: 1
  repeat_delay: 10
```

With that card behavior, Live Photos keep the still image visible, overlay the companion video after about one second, then wait `repeat_delay` seconds after the clip stops before playing the motion clip again. The Live Photo loop does not advance the slideshow; the card's normal photo timing still controls when the next photo appears.

## Live Photos

Apple Live Photos are exported by `icloudpd` as separate still image and MOV video files, not as Apple's Photos-app bundle.

For simple photo-only dashboards:

```yaml
skip_videos: true
skip_live_photos: true
```

For Live Photo-aware dashboard cards:

```yaml
skip_videos: false
skip_live_photos: false
convert_heic_to_jpeg: true
delete_heic_after_conversion: true
downscale_display_images: true
display_max_width: 1920
display_max_height: 1080
display_jpeg_quality: 82
```

The downscale step only touches JPEG/JPG files larger than the configured bounds and does not downscale videos. HEIC/HEIF originals are first converted to JPEG display files when possible, and are only deleted after a matching non-empty JPEG/JPG exists; empty failed-conversion placeholders are removed so the original can be retried on a later sync.
