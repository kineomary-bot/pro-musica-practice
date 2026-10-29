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
- Prepared-recording playback modes: all parts together, My part loudest (other voices 30 dB quieter), and My part only. Playback switches between pre-rendered MP3 files; there is no live browser mixer.
- Concert/collection filtering alongside global song search; member-controlled practice statuses; recently opened songs; per-song and central bookmarks.
- Combined Lyrics and Sheet Music tabs on the Practice screen.
- Individual-song and collection-level offline downloads.
- Skip backward/forward, seek, adjustable playback speed, and A/B loop markers.
- Original score PDF and lyrics view when those files are provided.
- Installable web-app manifest and service worker shell caching.

## How prepared vocal playback works

The Windows builder exports recordings ahead of time. The app selects one prepared MP3 for the full choir, one for the selected part with the other voices quieter, or one for the selected part alone. The browser does not mix stems live.

The prepared `loud-<part>.mp3` recordings keep the selected part at normal level and place each background part 30 dB lower. The current recordings are regenerated from the prepared `only-<part>.mp3` stems; the standard Windows build now also defaults to `-BackgroundDb -30`. Run `Make practice tracks.bat` to rebuild from the MuseScore source scores.
## Troubleshooting

- If the app says the library is not built, run `Make practice tracks.bat` and check for `site/pieces.json`.
- If a song appears but does not play, confirm its matching MP3 files exist in `site/audio/<song-folder>/` and that the uploaded `site` folder includes the complete `audio` directory.
- Test the published HTTPS link on a phone before sharing it with the choir.


## Collections / concerts

The app now supports collection filters. To group songs, edit `songs/collections.json` before running `Make practice tracks.bat`. The file is a JSON object mapping the source `.mscz` filename (without its extension) or the cleaned song title to a collection name. For example:

```json
{
  "Joy to the World": "Christmas Concert 2026",
  "O Holy Night": "Christmas Concert 2026"
}
```

Songs not listed appear under `Uncategorised`. The sample file is intentionally empty because the intended concert groupings have not been supplied.

## Branding asset note

`site/choir-logo.svg` and the PNG app icons currently contain a simple black-and-white Pro Musica placeholder mark. The previously shared Facebook-hosted official logo could not be retrieved in the build environment, so this is **not** a verified copy of the official choir logo. Replace it with the official local image before publishing if exact logo fidelity is required.

## Upgrade validation status

The upgraded source includes code-level changes for the Voice Mixer, per-song preferences, collection filtering/downloads, bookmarks, practice status, combined lyrics/score tabs and playback controls. JavaScript syntax and HTML ID consistency have been checked. Runtime browser, phone, offline-cache and Windows/MuseScore audio tests remain outstanding. Run the full test checklist in `AUDIT-REPORT.md` before publishing.
