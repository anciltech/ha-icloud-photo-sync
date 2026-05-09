# iCloud Photo Sync

Sync selected iCloud Photos content into Home Assistant media storage for dashboard playback.

This add-on wraps [`boredazfcuk/docker-icloudpd`](https://github.com/boredazfcuk/docker-icloudpd). Apple authentication, MFA cookies, download behavior, album filtering, shared-library support, and re-authentication are provided by `icloudpd`.

## Install

1. In Home Assistant, go to `Settings -> Add-ons -> Add-on Store`.
2. Open the top-right menu and choose `Repositories`.
3. Add this repository URL:

   ```text
   https://github.com/anciltech/ha-icloud-photo-sync
   ```

4. Install `iCloud Photo Sync`.

This is a Home Assistant add-on repository, not a HACS package.

## Configure

Typical still-photo display:

```yaml
apple_id: "your-apple-id@example.com"
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
- Do not commit or paste Apple passwords into Home Assistant config, GitHub issues, or chat.
- Enter the Apple password only during the interactive initialise step below.

## First-Time Initialise

The upstream container stores the Apple password in its own keyring and creates the MFA cookie interactively. Use the installed `Advanced SSH & Web Terminal` add-on for this one-time step.

From the SSH add-on terminal on HAOS:

```sh
docker ps --format '{{.Names}}' | grep icloud_photo_sync
docker exec -it <container_name> sync-icloud.sh --Initialise
```

Use the container name returned by the first command.

What to expect:

- It will prompt for the Apple password.
- It will ask whether to save the password in the keyring.
- Apple will send or display a 2FA code.
- After success, the cookie is stored under the add-on `/config` volume and normal sync can proceed.

## Re-Authentication

`icloudpd` cookie auth typically needs renewal periodically.

When it expires, run:

```sh
docker ps --format '{{.Names}}' | grep icloud_photo_sync
docker exec -it <container_name> reauth.sh
```

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
- `delete_heic_after_conversion: true` removes only HEIC/HEIF originals that have a same-folder JPEG/JPG conversion, leaving videos and Live Photo MOV companions controlled by the video options.
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

The downscale step only touches JPEG/JPG files larger than the configured bounds and does not downscale videos.
