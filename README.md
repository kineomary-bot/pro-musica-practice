# Pro Musica Choir Practice App

This is the upgraded, mobile-first version of the existing choir practice app. The Windows source files and MuseScore workflow are retained. The interface keeps a teal-and-white palette and uses squarer, quieter surfaces designed for phone screens.

## Build the song library and recordings (Windows)

1. Install MuseScore 4 on the computer that will build the tracks.
2. Put each choir score (`.mscz`) in the `songs` folder. The sample `Joy to the World` files are included. Number filenames if you want to control song order.
3. Optional: add a PDF of the choir's original score and a shared lyrics text file with the same base filename as the `.mscz`. For different lyrics by part, add files named `<Song title> - <Part name>.txt` (for example, `Joy to the World - Alto.txt`, `Joy to the World - Soprano 1.txt`, `Joy to the World - Soprano 2.txt`, `Joy to the World - Tenor.txt`, and `Joy to the World - Bass.txt`). Part-specific files override the shared lyrics for that voice; other parts fall back to the shared file.
4. Double-click **Make practice tracks.bat** and wait for it to finish. This creates `site/pieces.json` and the per-song audio files under `site/audio/`. If FFmpeg is not installed, files may be larger; it is optional.
5. Open the `site` folder and confirm `pieces.json` and an `audio` folder exist before publishing.

## Publish and install on phones

1. Upload the **contents of the `site` folder** to your hosting provider (for example, Netlify Drop). Do not upload only `index.html`; the JSON file, audio folder, PDFs, icons, manifest and service worker are needed.
2. Open the published HTTPS link on the phone.
3. iPhone: Safari → Share → Add to Home Screen. Android: Chrome menu → Install app / Add to Home screen.
4. The app shell can be available offline after it has been loaded once. Song audio and PDFs must be explicitly downloaded from the library; collection downloads are also available.

## Singer profile

- On first launch, singers enter their name and choose a vocal part.
- The profile is saved in the browser on that device using local storage. It is not an online account and does not automatically sync between devices or browsers.
- Singers can change their name or vocal part at any time in Settings.

## App features

- Mobile-first song library with search.
- Persistent mini-player while switching between Practice, Sheet Music, Lyrics and Settings.
- Voice Mixer screen with per-part volume/mute controls, three quick mix presets, and per-song saved balances (requires generated isolated-part recordings).
- Concert/performance filtering alongside global song search; member-controlled practice statuses; recently opened songs; per-song and central bookmarks.
- Combined Lyrics and Sheet Music tabs on the Practice screen.
- Individual-song and performance-level offline downloads.
- Skip backward/forward, seek, adjustable playback speed, and A/B loop markers.
- Original score PDF and lyrics view when those files are provided.
- Installable web-app manifest and service worker shell caching.

## How independent vocal mixing works

The Windows builder exports an isolated track for each part from the MuseScore score. The app uses those files for independent part volume and mute controls. The code attempts to synchronise the part players to the main audio timeline during playback, seeking, tempo changes and looping. This path requires an actual Windows/MuseScore build and listening test before it can be considered verified. The build version has changed so existing song exports are regenerated on the next full build.

## Troubleshooting

- If the app says the library is not built, run `Make practice tracks.bat` and check for `site/pieces.json`.
- If a song appears but does not play, confirm its matching MP3 files exist in `site/audio/<song-folder>/` and that the uploaded `site` folder includes the complete `audio` directory.
- Test the published HTTPS link on a phone before sharing it with the choir.


## Concerts and performances

The song-library dropdown is organised by named concerts or performance programmes. Edit `songs/performances.json` before running `Make practice tracks.bat`. The file contains a top-level `performances` array. Each performance has a stable ID, display name, optional date, status and a list of songs.

Example structure (the draft below is intentionally unassigned and is not a real programme):

```json
{
  "performances": [
    {
      "id": "winter-concert-2027",
      "name": "Winter Concert 2027",
      "date": null,
      "status": "draft",
      "songs": []
    }
  ]
}
```

Use a unique lowercase ID with hyphens. Set `date` to `YYYY-MM-DD` or `null`. Status must be `draft`, `active` or `archived`; only active performances appear in the singers' dropdown. Draft and archived performances remain in the source configuration but are hidden from the main dropdown.

The `songs` array accepts the exact source `.mscz` filename without its extension, the cleaned song title, or the stable song ID. One song can be assigned to more than one performance. The build checks references against the available `.mscz` files and reports unknown or ambiguous song references. A song not assigned to any performance remains available under **All songs** and appears in the **Unassigned songs** filter. In **All songs**, each song also shows its performance name or an unassigned label. Every build prints a colour-coded assignment report listing assigned and unassigned songs.

After editing the file, run `Make practice tracks.bat` to regenerate `site/pieces.json`. The generated catalogue stores the performance list and a `performanceIds` array on each song. The offline download button downloads all songs when **All songs** is selected, or only songs assigned to the selected active performance.

## Branding asset note

`site/choir-logo.svg` and the PNG app icons currently contain a simple black-and-white Pro Musica placeholder mark. The previously shared Facebook-hosted official logo could not be retrieved in the build environment, so this is **not** a verified copy of the official choir logo. Replace it with the official local image before publishing if exact logo fidelity is required.

## Upgrade validation status

The upgraded source includes code-level changes for the Voice Mixer, per-song preferences, concert/performance filtering and downloads, bookmarks, practice status, combined lyrics/score tabs and playback controls. JavaScript syntax has been checked. Runtime browser, phone, offline-cache and Windows/MuseScore audio tests remain outstanding. Run the full test checklist in `AUDIT-REPORT.md` before publishing.
