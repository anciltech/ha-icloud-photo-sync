# AncilTech iCloud Photo Sync Add-on

Home Assistant add-on repository for syncing iCloud Photos into Home Assistant media storage.

This wraps [`boredazfcuk/docker-icloudpd`](https://github.com/boredazfcuk/docker-icloudpd) so Home Assistant OS dashboards can show iCloud Photos from `/media/icloud_photos`.

## Quick Start

1. Open Home Assistant.
2. Go to `Settings -> Add-ons -> Add-on Store`.
3. Open the top-right menu and choose `Repositories`.
4. Add this repository URL:

   ```text
   https://github.com/anciltech/ha-icloud-photo-sync
   ```

5. Install `iCloud Photo Sync` from the add-on store.
6. In the add-on options, set your Apple ID, album name, and `download_path: /media/icloud_photos`.
7. Start the add-on once, then complete the Apple authentication step below from an HAOS terminal.
8. Restart the add-on and watch the log until the first sync finishes.
9. Point your dashboard card at `media-source://media_source/local/icloud_photos`.

This is a Home Assistant add-on repository, so it is installed through the Add-on Store rather than HACS. HACS is still the right path for frontend cards and some integrations.

## Recommended Display Options

Still-photo dashboard:

```yaml
convert_heic_to_jpeg: true
delete_heic_after_conversion: true
downscale_display_images: true
display_max_width: 1920
display_max_height: 1080
display_jpeg_quality: 82
skip_videos: true
skip_live_photos: true
recent_only: 200
```

Live Photo-aware dashboard:

```yaml
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

## What It Does

- Downloads selected iCloud Photos content into `/media/icloud_photos`.
- Supports named albums, shared libraries, recent-only syncs, videos, and Live Photo companions through `icloudpd`.
- Can convert HEIC/HEIF still images to JPEG.
- Can delete converted HEIC/HEIF originals after a matching non-empty JPEG/JPG exists, while leaving videos controlled by the video options.
- Removes empty failed-conversion JPG placeholders when the original HEIC/HEIF still exists.
- Can optionally downscale oversized JPEG display copies for 1080p dashboard panels.

## Pair With A Photo Display Card

The add-on only performs server-side sync. For dashboard playback, point a media card at:

```text
media-source://media_source/local/icloud_photos
```

The AncilTech fork of `ha-media-card` includes an `icloud_photos` preset and Live Photo playback mode that keeps the still photo visible, overlays the companion video, waits for a configurable repeat delay after the clip stops, and leaves normal slideshow timing in control of when the card advances:

```text
https://github.com/anciltech/ha-media-card/tree/feature/icloud-live-photos
```

## First-Time Apple Authentication

Apple authentication is handled by `icloudpd` inside the add-on container. The add-on does not store Apple passwords in this repository.

After installing and starting the add-on once, use the Home Assistant `Advanced SSH & Web Terminal` add-on or another HAOS shell:

```sh
docker ps --format '{{.Names}}' | grep icloud_photo_sync
docker exec -it <container_name> sync-icloud.sh --Initialise
```

Use the container name returned by the first command. Follow the Apple password and MFA prompts. After the cookie and keyring are created, normal scheduled syncs can run unattended until Apple requires re-authentication.

## Verify The First Sync

After authentication, restart the add-on and check:

- Add-on log shows a completed `icloudpd` sync.
- Home Assistant Media Browser contains `/media/icloud_photos`.
- Your chosen album folder appears below that path when `photo_album` is set.
- Converted JPEG files appear for HEIC/HEIF photos when `convert_heic_to_jpeg` is enabled.

See [`icloud_photo_sync/DOCS.md`](icloud_photo_sync/DOCS.md) for configuration details.
