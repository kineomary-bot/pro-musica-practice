# Choir practice app build-script audit

## Scope and test status

Reviewed `build.ps1`, `Make practice tracks.bat`, `README.md`, `site/index.html`, and the sample `Joy to the World.mscz` archive. The repaired script is versioned internally as `ps1-2` so existing cached builds are regenerated.

**Important limitation:** this environment does not have Windows PowerShell or MuseScore installed, so the repaired script has not been executed against MuseScore. Treat it as a code-level repair that still requires a Windows build and listening test before publication.

## Findings and changes

### 1. High priority — MuseScore JSON batch jobs were used for audio

The original script put MP3, PDF, and MIDI exports into one `-j` JSON batch. MuseScore's command-line documentation lists MP3 as a supported direct export format, but recent MuseScore 4 reports describe audio exports through JSON jobs as unreliable or unsupported. The old code only checked whether an output file existed and was non-empty, which could accept a silent MP3 as successful.

**Repair:** MP3 files are now exported one at a time using `MuseScore -o output.mp3 input.mscz`. JSON batch export is limited to PDF and MIDI, with individual-export fallback if batch outputs are missing. Non-zero exit codes for direct audio exports now stop the build.

**Still required:** listen to the generated `all.mp3`, `loud-*.mp3` and `only-*.mp3` files. File existence and exit status alone cannot prove that a recording is audible or that the part balance is correct.

References:
- MuseScore command-line usage: https://handbook.musescore.org/appendix/command-line-usage
- MuseScore issue discussing JSON CLI audio export limitations: https://github.com/musescore/MuseScore/issues/31644

### 2. High priority — MIDI running-status parsing could corrupt timing data

The original MIDI reader did not correctly consume the first data byte of events that use MIDI running status. Running status is common in MIDI files; misreading it can desynchronise the parser and produce incorrect tempo/time-signature events or a broken beat map.

**Repair:** rewrote the event parser to handle running status, meta events, system-exclusive events, variable-length values, track bounds, invalid headers and SMPTE timing explicitly. Tempo and time-signature metadata duplicated across tracks at the same tick are deduplicated.

### 3. Medium priority — pickup-measure lookup used the wrong XML path

The original XPath searched `/museScore/Score/Staff/Measure`, but MuseScore score data stores staves within parts. As a result, the script normally failed to find the first measure and could not calculate a pickup duration.

**Repair:** corrected the path to `/museScore/Score/Part/Staff/Measure[1]`. If a length attribute/element is absent, the script now estimates the first measure's duration by summing chord/rest durations in each voice. The beat-map generator includes clicks during the pickup and accents the first full-bar downbeat.

**Still required:** verify the beat map against songs with pickups, unusual tuplets, and changing time signatures. The duration estimate is a fallback and should be checked musically.

### 4. Medium priority — export failures were not reported reliably

The original wrapper did not capture MuseScore's process exit code. A failed export was only noticed if the expected file was absent or zero bytes.

**Repair:** the wrapper returns the process exit code, direct audio export checks it, and missing/empty outputs produce a clearer error.

### 5. Medium priority — ffmpeg compression could accept a failed output

The original compression function replaced the source MP3 whenever a temporary file existed, even if ffmpeg had failed.

**Repair:** compression now checks ffmpeg's exit code and requires a non-empty temporary file before replacing the original. A failed compression stops the build and preserves the original export.

### 6. Medium priority — song filename slugs could collide

Different filenames can normalise to the same slug (for example, punctuation differences). That could cause two songs to share an output folder and overwrite one another.

**Repair:** the build now detects duplicate slugs and asks for one filename to be renamed.

### 7. Output paths and catalogue

The app's expected paths are consistent in the supplied files: `pieces.json` is written to the `site` root, and song assets are written below `site/audio/<slug>/`. The website fetches `pieces.json` relative to its own root. No path change was necessary.

The batch launcher changes the working directory to the script directory, and the build script uses `$PSScriptRoot` for its default input/output paths. This is appropriate for a folder-based Windows workflow.

## Recommended Windows acceptance test

1. Install/update MuseScore 4 and open/save `Joy to the World.mscz` once.
2. Run `Make practice tracks.bat` from the extracted folder.
3. Confirm `site/pieces.json`, `site/audio/joy-to-the-world/all.mp3`, `score.pdf`, and all expected `loud-*` and `only-*` files exist.
4. Play every generated MP3. Confirm each vocal part is correct, “louder” actually emphasises that part, and “only” contains no other vocal parts.
5. Check the MP3s are not silent and have plausible durations. If ffmpeg is installed, confirm compressed files still play.
6. Open the deployed site and test the metronome against the recording, especially at the start, after seeking, and across tempo/time-signature changes.
7. Test a song with a pickup and another with changing time signatures before relying on metronome timing across the full repertoire.

## Mobile-first UI update (2026-10-28)

- Reworked `site/index.html` into phone-first Home, Practice, Vocal Parts, Loop, Tempo, Sheet Music, Lyrics and Settings screens.
- Added persistent mini-player so the audio element remains active when navigating between app screens.
- Added song search, skip back/forward, A/B looping, speed control, original PDF access, and responsive bottom navigation.
- Updated app manifest, app icons, and added a service worker for the app shell and cached `pieces.json`.
- Kept the existing MuseScore-based build pipeline and source materials.
- Important limitation: vocal mix options are pre-rendered (`loud`, `only`, `all`), not independent live volume sliders. The interface only exposes supported prebuilt mixes.
- Validation performed: JavaScript syntax check with Node.js; ZIP structure and key source files checked. Actual audio playback and mobile installation still need to be tested after `Make practice tracks.bat` generates `pieces.json` and audio, and after the site is published over HTTPS.


---

# Upgrade implementation update — 2026-10-28

## Code changes made

- Reworked the main screen styling to reduce rounded surfaces and simplify controls while retaining the teal/white palette.
- Added simple tag filtering and tag-filtered offline downloads. The builder reads `songs/tags.json`, validates tag IDs and song references, writes the tag list to the catalogue, and adds a `tagIds` array to each song. Songs can have multiple tags; untagged songs remain visible under All songs and in the Everything else filter.
- Added recently opened songs, member-controlled practice status, per-song playback-position bookmarks, named bookmarks, and a central bookmark list. These are stored locally in the browser.
- Added combined Lyrics/Sheet Music tabs to the Practice screen while retaining the existing separate navigation destinations as shortcuts into those tabs.
- Replaced the placeholder Playback & Vocal Parts screen with a Voice Mixer, including per-part controls, presets and per-song saved balances. The mixer uses the builder's isolated `files.only` / `files.stems` MP3s and synchronises them against the main audio element.
- Improved A/B marker validation, loop boundary handling, seek-by-ten-second behaviour and the no-song warning.
- Updated service-worker shell cache version and app icons.

## Checks performed in this environment

- JavaScript parsed successfully with Node.js `--check`.
- No duplicate HTML IDs were found.
- All statically referenced `$('#...')` IDs in the script were found in the HTML.
- A headless browser interaction test was attempted, but the environment blocks navigation to both local HTTP and file URLs (`ERR_BLOCKED_BY_ADMINISTRATOR`). Therefore this is not a successful runtime test.
- Windows PowerShell and MuseScore build execution was not available. Generated audio has not been listened to or verified.

## Known limitations / follow-up required

- The official logo URL could not be retrieved from this environment. The bundled `choir-logo.svg` and PNG app icons are temporary black-and-white musical-note placeholders, not a verified copy of the official Pro Musica logo. Replace these assets with the actual logo before publishing.
- `songs/tags.json` assigns both existing songs to the `Christmas 2026` tag. Any other songs remain visible and untagged until the choir decides how to group them.
- Tag-filtered downloads and Cache API behaviour need real-browser testing, including quota failures, interrupted downloads, and offline access.
- The mixer requires generated isolated-part audio for each song. Its synchronization, volume balance and loop behaviour require testing on target browsers with real recordings.
- The `pieces.json` catalogue and generated audio are not included in the source ZIP; run `Make practice tracks.bat` on Windows with MuseScore 4 to build them.
- No app publishing/deployment was performed.


# Announcements and calendar update — 2026-10-29

## Code changes

- Added an Announcements section and the next three events to the Home screen.
- Added an Announcements & dates screen, opened through the Home links, that displays all current notices and upcoming events.
- Added editable `site/announcements.json` and `site/events.json` files. Announcements support a posted date, optional expiry date, and optional link. Events support a date, time, venue, category, details, and optional link.
- Seeded the calendar with the established Christmas concert date: 6 December 2026 at 16:00, NG Kerk Hermanus. Announcements intentionally start empty so no sample notice is mistaken for a real choir message.
- Past events are omitted from upcoming lists but remain in the source JSON. Announcements with an expiry date stop appearing after that date.
- Bumped the service-worker shell cache to v14 and included announcement/event JSON in network-first cache handling, with cached fallback when offline.

## Validation status

- Inline app JavaScript syntax passed a parser check.
- New JSON configuration files parse, and the event data contains the Christmas concert entry.
- No duplicate HTML IDs were found.
- The existing Windows/MuseScore build was not run, and live browser, mobile and offline interactions have not yet been tested. These require acceptance testing after deployment.


# Choir dates and noticeboard update — 2026-10-29

- Added Year-End Function (14 November 2026, 11:30), Kerssangdiens (29 November 2026, 18:00, NG Kerk Hermanus), Hospital Performances (5 December 2026, 15:00), retaining Christmas in Music and Song (6 December 2026, 16:00, NG Kerk Hermanus).
- Added an Extra practice announcement for Wednesday 4 November, posted 29 October and set to expire after 4 November.
- Styled the Home announcement block with a pale coral background and the upcoming dates block with a pale teal background. Home event cards use compact spacing to keep the summary prominent without taking over the song library layout.
- Bumped the service-worker shell cache to v15.
- Static syntax/data checks remain the available validation; browser/mobile visual acceptance testing is still required.
