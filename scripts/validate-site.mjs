import { access, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve('site');
const errors = [];
const requiredFiles = [
  'index.html',
  'pieces.json',
  'announcements.json',
  'events.json',
  'sw.js',
  'manifest.webmanifest',
  'icon-192.png',
  'icon-512.png',
  'apple-touch-icon.png',
  'choir-logo.svg',
];

async function fileExists(relativePath, requireNonEmpty = true) {
  const fullPath = path.resolve(root, relativePath);
  if (!fullPath.startsWith(root + path.sep)) {
    errors.push(`Unsafe path outside site/: ${relativePath}`);
    return false;
  }
  try {
    const info = await stat(fullPath);
    if (!info.isFile()) {
      errors.push(`Expected a file: site/${relativePath}`);
      return false;
    }
    if (requireNonEmpty && info.size === 0) {
      errors.push(`File is empty: site/${relativePath}`);
      return false;
    }
    await access(fullPath);
    return true;
  } catch {
    errors.push(`Missing required file: site/${relativePath}`);
    return false;
  }
}

async function readJson(relativePath) {
  if (!(await fileExists(relativePath))) return null;
  try {
    return JSON.parse(await readFile(path.join(root, relativePath), 'utf8'));
  } catch (error) {
    errors.push(`Invalid JSON in site/${relativePath}: ${error.message}`);
    return null;
  }
}

for (const file of requiredFiles) await fileExists(file);

const intervalRecordingFiles = [
  'do-re.mp3', 're-do.mp3',
  'do-mi.mp3', 'mi-do.mp3',
  'do-fa.mp3', 'fa-do.mp3',
  'do-sol.mp3', 'sol-do.mp3',
  'do-la.mp3', 'la-do.mp3',
  'do-ti.mp3', 'ti-do.mp3',
  'do-high-do.mp3', 'high-do-low-do.mp3',
  'do-me.mp3', 'me-do.mp3',
  'do-le.mp3', 'le-do.mp3',
  'do-te.mp3', 'te-do.mp3',
];
for (const file of intervalRecordingFiles) await fileExists(path.posix.join('audio', 'pitch-intervals', file));


const piecesData = await readJson('pieces.json');
const announcementsData = await readJson('announcements.json');
const eventsData = await readJson('events.json');
await readJson('manifest.webmanifest');

let tagConfig = null;
try {
  tagConfig = JSON.parse(await readFile(path.resolve('songs/tags.json'), 'utf8'));
} catch (error) {
  errors.push(`Could not read songs/tags.json: ${error.message}`);
}
if (!tagConfig || !Array.isArray(tagConfig.tags)) {
  errors.push('songs/tags.json must contain a tags array.');
}

if (!piecesData || !Array.isArray(piecesData.pieces) || piecesData.pieces.length === 0) {
  errors.push('site/pieces.json must contain a non-empty pieces array; the app must not be published without its song catalogue.');
}

if (piecesData && Array.isArray(piecesData.pieces) && tagConfig && Array.isArray(tagConfig.tags)) {
  const piecesById = new Map(piecesData.pieces.map(piece => [piece.id, piece]));
  const expectedTagsBySong = new Map();
  const siteTagsById = new Map((piecesData.tags || []).map(tag => [tag.id, tag]));

  for (const tag of tagConfig.tags) {
    if (!tag || typeof tag.id !== 'string' || typeof tag.name !== 'string' || !Array.isArray(tag.songs)) {
      errors.push('Every entry in songs/tags.json must have an id, name and songs array.');
      continue;
    }
    const siteTag = siteTagsById.get(tag.id);
    if (!siteTag || siteTag.name !== tag.name) {
      errors.push(`site/pieces.json is missing the configured tag "${tag.name}" (${tag.id}).`);
    }
    for (const songId of tag.songs) {
      const piece = piecesById.get(songId);
      if (!piece) {
        errors.push(`Tag "${tag.name}" refers to unknown song id "${songId}".`);
        continue;
      }
      const expected = expectedTagsBySong.get(songId) || [];
      if (!expected.includes(tag.id)) expected.push(tag.id);
      expectedTagsBySong.set(songId, expected);
      if (!Array.isArray(piece.tagIds) || !piece.tagIds.includes(tag.id)) {
        errors.push(`Song "${piece.title}" is missing configured tag "${tag.name}" in site/pieces.json.`);
      }
    }
    if (siteTag && Array.isArray(siteTag.songs)) {
      const configuredSongs = [...new Set(tag.songs)].sort();
      const builtSongs = [...new Set(siteTag.songs)].sort();
      if (JSON.stringify(configuredSongs) !== JSON.stringify(builtSongs)) {
        errors.push(`Tag "${tag.name}" has different song assignments in songs/tags.json and site/pieces.json.`);
      }
    }
  }

  for (const piece of piecesData.pieces) {
    const expected = expectedTagsBySong.get(piece.id) || [];
    for (const tagId of Array.isArray(piece.tagIds) ? piece.tagIds : []) {
      if (!expected.includes(tagId)) {
        errors.push(`Song "${piece.title}" has tag "${tagId}" in site/pieces.json but not in songs/tags.json.`);
      }
    }
  }
}

if (!announcementsData || !Array.isArray(announcementsData.announcements)) {
  errors.push('site/announcements.json must contain an announcements array.');
}
if (!eventsData || !Array.isArray(eventsData.events)) {
  errors.push('site/events.json must contain an events array.');
}

const html = await readFile(path.join(root, 'index.html'), 'utf8').catch(() => '');
const requiredHtmlMarkers = [
  'id="welcomeBackdrop"',
  'id="welcomeForm"',
  'id="welcomeName"',
  'id="welcomeVoice"',
  'id="songList"',
  'id="announcementList"',
  'id="announcementsSection"',
  'id="homeCalendarLink"',
  'id="allEvents"',
  'id="addBookmark"',

  'id="breathingDuration"',
  'id="breathingDurationValue"',
  'id="breathingInDuration"',
  'id="breathingOutDuration"',
  'id="screen-interval-game"',
  'id="intervalGameModeListen"',
  'id="intervalGameModeSing"',
  'id="intervalGameStart"',
  'id="intervalGameExit"',
  'id="intervalGameOptions"',
  'id="intervalGameRoot"',
  'id="intervalGameSingStart"',
  'id="intervalGameSingCheck"',
  'id="intervalGameHighScoreList"',
  'id="intervalGameAudio"',
];
for (const marker of requiredHtmlMarkers) {
  if (!html.includes(marker)) errors.push(`site/index.html is missing required startup/app markup: ${marker}`);
}

if (!html.includes('function intervalGameEstimateMidi') ||
    !html.includes('function intervalGameSaveScore') ||
    !html.includes("store.set('intervalGameScores',intervalGameScores)") ||
    !html.includes('navigator.mediaDevices.getUserMedia') ||
    !html.includes("$$('#intervalGameOptions .interval-game-answer').forEach(")) {
  errors.push('The interval challenge must include in-browser pitch detection and locally saved high scores.');
}

const intervalGameLevelBindings = (html.match(/\$\$\('\.interval-game-level'\)\.forEach\(/g) || []).length;
if (intervalGameLevelBindings !== 2 || /(?<!\$)\$\('\.interval-game-level'\)\.forEach\(/.test(html)) {
  errors.push('All three interval game difficulty buttons must be initialised in both the level display and event handler.');
}

const intervalQuestionFactoryStart = html.indexOf('function intervalGameMakeQuestions(){');
const intervalQuestionFactoryEnd = html.indexOf('function intervalGameRenderQuestion(){', intervalQuestionFactoryStart);
const intervalQuestionFactory = intervalQuestionFactoryStart >= 0 && intervalQuestionFactoryEnd > intervalQuestionFactoryStart
  ? html.slice(intervalQuestionFactoryStart, intervalQuestionFactoryEnd) : '';
if (!intervalQuestionFactory.includes('if(pool.length>1&&deck[0].id===lastId)') ||
    !intervalQuestionFactory.includes("Math.random()<0.5?'up':'down'") ||
    !intervalQuestionFactory.includes('lastId=definition.id')) {
  errors.push('Listening rounds must shuffle intervals in separate decks, avoid repeating the same interval at a deck boundary, and randomise direction.');
}

const intervalGameExitControls = html.includes("id=\"intervalGameExit\"") &&
  html.includes("$('#intervalGameExit').addEventListener('click',intervalGameReturnToSetup)") &&
  html.includes('function intervalGameReturnToSetup(){');
if (!intervalGameExitControls) {
  errors.push('An active interval game must provide a working way to return to the game and difficulty settings.');
}
const singingRetryStart = html.indexOf('async function intervalGameStartSinging(){');
const singingRetryEnd = html.indexOf('function intervalGameStopCapture(){', singingRetryStart);
const singingRetryFinishStart = html.indexOf('function intervalGameFinishSinging(){');
const singingRetryFinishEnd = html.indexOf('function intervalGameCheckSinging(){', singingRetryFinishStart);
const singingRetryCode = singingRetryStart >= 0 && singingRetryEnd > singingRetryStart &&
  singingRetryFinishStart >= 0 && singingRetryFinishEnd > singingRetryFinishStart
  ? html.slice(singingRetryStart, singingRetryEnd) + html.slice(singingRetryFinishStart, singingRetryFinishEnd) : '';
if (!singingRetryCode.includes("$('#intervalGameRoot').disabled=false;") ||
    !singingRetryCode.includes("$('#intervalGameSingStart').textContent='Try again'") ||
    !singingRetryCode.includes('intervalGameState.singingAttempted=true;') ||
    !singingRetryCode.includes("$('#intervalGameNext').classList.remove('hidden')")) {
  errors.push('The singing challenge must let singers replay Do, retry an incorrect note, and move on when they choose.');
}

if (!html.includes('Back 5 seconds') ||
    !html.includes('Forward 5 seconds') ||
    !html.includes('Jump back 5 seconds') ||
    !html.includes('Jump forward 5 seconds') ||
    !html.includes("$('#miniRewind').addEventListener('click',()=>seekBy(-5))") ||
    !html.includes("$('#miniForward').addEventListener('click',()=>seekBy(5))") ||
    !html.includes("$('#rewind').addEventListener('click',()=>seekBy(-5))") ||
    !html.includes("$('#forward').addEventListener('click',()=>seekBy(5))")) {
  errors.push('Practice playback and mini-player skip controls must move in five-second increments.');
}

const bookmarkSaveStart = html.indexOf('function saveBookmark(){');
const bookmarkSaveEnd = html.indexOf("$('#addBookmark').addEventListener('click',saveBookmark)", bookmarkSaveStart);
if (bookmarkSaveStart < 0 || bookmarkSaveEnd < 0 ||
    html.includes('id="addSectionBookmark"') ||
    !html.slice(bookmarkSaveStart, bookmarkSaveEnd).includes('optional') ||
    !html.includes("$('#addBookmark').addEventListener('click',saveBookmark)")) {
  errors.push('Bookmarks must use one action that saves the current position and allows an optional name.');
}

if (!html.includes("const seen=new Map(),excluded=new Set(['soprano','solo','descant']);")) {
  errors.push('Singer profile choices must not include generic Soprano, Solo or Descant.');
}
if (!html.includes('function pieceVoiceId(p){') ||
    !html.includes("(voice==='soprano-1'||voice==='soprano-2')&&ids.has('soprano')") ||
    !html.includes('const voiceId=pieceVoiceId(piece);')) {
  errors.push('Soprano 1 and Soprano 2 must continue to share the single Soprano audio and starting-note data.');
}

if (!html.includes("$$('#warmupExerciseList li').forEach(")) {
  errors.push('Warm-up exercise list updates must use querySelectorAll for every list item.');
}
if (html.includes('A short vocal warm-up. Follow the piano at a comfortable volume.') ||
    html.includes('Choose from 10 seconds to 10 minutes in 10-second steps.') ||
    html.includes('aria-describedby="breathingDurationHelp"')) {
  errors.push('Removed warm-up copy must not reappear or leave a dangling help-text reference.');
}
if (!html.includes("Breathe in through your nose") ||
    !html.includes("Breathe out through your mouth") ||
    !html.includes(".breathing-controls .primarybtn,.breathing-controls .smallbtn") ||
    !html.includes(".tab{font-size:12px;line-height:1.2}") ||
    !html.includes(".controlhint{font-size:12px;line-height:1.3}")) {
  errors.push('Breathing prompts and readable app-wide button styles must be present.');
}
const breathingSectionCollapsed = html.includes('<details class="warmup-breath-exercise panel warmup-collapsible" id="breathingSection">');
const vocalSectionCollapsed = html.includes('<details class="warmup-vocal-section panel warmup-collapsible" id="quickVocalSection">');
if (!breathingSectionCollapsed || !vocalSectionCollapsed ||
    !html.includes("if(name==='warmups'){const breathing=$('#breathingSection');if(breathing)breathing.open=false;const vocal=$('#quickVocalSection');if(vocal)vocal.open=false;}")) {
  errors.push('Breathing and Quick vocal warm-up sections must be collapsed by default and when the Warm-ups screen is reopened.');
}
if (!/id="breathingDuration"[^>]*type="range"[^>]*min="10"[^>]*max="600"[^>]*step="10"/.test(html)) {
  errors.push('Breathing duration must be adjustable from 10 seconds to 10 minutes in 10-second steps.');
}
if (!/id="breathingInDuration"[^>]*aria-label="Inhale duration"/.test(html) ||
    !/id="breathingOutDuration"[^>]*aria-label="Exhale duration"/.test(html) ||
    !html.includes("store.get('breathingInSeconds',4)") ||
    !html.includes("store.get('breathingOutSeconds',6)") ||
    !html.includes("const inhaleMs=breathingInSeconds*1000,exhaleMs=breathingOutSeconds*1000;") ||
    !html.includes("$('#breathingInDuration').addEventListener('change',event=>breathingSetRhythm(event.target.value,breathingOutSeconds))") ||
    !html.includes("$('#breathingOutDuration').addEventListener('change',event=>breathingSetRhythm(breathingInSeconds,event.target.value))") ||
    !html.includes('value="8"')) {
  errors.push('The breathing exercise must let users choose and save independent inhale and exhale durations from 1 to 8 seconds.');
}
if (!html.includes('id="warmupRestart" aria-label="Restart vocal warm-up"') ||
    !html.includes('id="warmupNext" aria-label="Next exercise">Next</button>') ||
    !html.includes("$('#warmupNext').textContent=isLastWarmup?'Finish':'Next'")) {
  errors.push('Vocal warm-up controls must use short visible labels with clear accessible names.');
}
const showScreenStart = html.indexOf('function showScreen(');
const paintNavStart = html.indexOf('function paintNav(', showScreenStart);
const showScreenSource = showScreenStart >= 0 && paintNavStart > showScreenStart
  ? html.slice(showScreenStart, paintNavStart)
  : '';
if (!/(^|[^$])\$\$\('\.screen'\)\.forEach\(/.test(showScreenSource)) {
  errors.push('Screen navigation must use the querySelectorAll helper ($$) to activate Practice, Bookmarks and Loop screens.');
}

const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)];
let inlineScriptCount = 0;
for (const [index, match] of scripts.entries()) {
  const attributes = match[1] || '';
  const source = match[2] || '';
  if (/\bsrc\s*=/.test(attributes) || !source.trim()) continue;
  inlineScriptCount++;
  try {
    new vm.Script(source, { filename: `site/index.html inline script ${index + 1}` });
  } catch (error) {
    errors.push(`JavaScript syntax error in site/index.html inline script ${index + 1}: ${error.message}`);
  }
}
if (inlineScriptCount === 0) errors.push('No inline app script was found in site/index.html.');

const sw = await readFile(path.join(root, 'sw.js'), 'utf8').catch(() => '');
try {
  new vm.Script(sw, { filename: 'site/sw.js' });
} catch (error) {
  errors.push(`JavaScript syntax error in site/sw.js: ${error.message}`);
}
if (!/function\s+respondWithByteRange/.test(sw) ||
    !/request\.headers\.get\(['"]range['"]\)/.test(sw) ||
    !/status:\s*206/.test(sw)) {
  errors.push('site/sw.js must honour byte-range requests for cached audio and PDF files so seeking works.');
}
if (!sw.includes("if (req.headers.has('range')") ||
    !sw.includes("mp3|m4a|wav|ogg|aac|flac|pdf") ||
    !sw.includes("return respondWithByteRange(req, response)")) {
  errors.push('site/sw.js must convert ignored network Range requests into partial media responses, including when the server returns application/octet-stream.');
}
if (!errors.some(error => error.startsWith('JavaScript syntax error in site/sw.js'))) {
  try {
    const workerListeners = {};
    const mockBytes = new Uint8Array([10, 20, 30, 40, 50, 60, 70, 80]);
    const workerContext = {
      URL,
      Request,
      Response,
      Headers,
      self: {
        location: { origin: 'https://choir.example' },
        clients: { claim: async () => {} },
        skipWaiting: async () => {},
        addEventListener: (name, handler) => { workerListeners[name] = handler; },
      },
      caches: {
        open: async () => ({ match: async () => null, put: async () => {}, addAll: async () => {} }),
        keys: async () => [],
      },
      fetch: async () => new Response(mockBytes, {
        status: 200,
        headers: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(mockBytes.length) },
      }),
    };
    vm.runInNewContext(sw, workerContext, { filename: 'site/sw.js range integration test' });
    const request = new Request('https://choir.example/audio/test.mp3', {
      headers: { Range: 'bytes=2-5' },
    });
    let networkResult = null;
    workerListeners.fetch({
      request,
      respondWith: responsePromise => { networkResult = responsePromise; },
    });
    const rangedResponse = await networkResult;
    const rangedBytes = [...new Uint8Array(await rangedResponse.arrayBuffer())];
    if (rangedResponse.status !== 206 ||
        rangedResponse.headers.get('content-range') !== 'bytes 2-5/8' ||
        JSON.stringify(rangedBytes) !== JSON.stringify([30, 40, 50, 60])) {
      errors.push('Service-worker integration test failed: network media Range requests must return the requested bytes as HTTP 206.');
    }
  } catch (error) {
    errors.push(`Service-worker Range integration test could not run: ${error.message}`);
  }
}
if (!html.includes("$('#seek').addEventListener('input',e=>{seeking=true;const d=seekDuration(),target=Number(e.target.value)/1000*d;$('#timeNow').textContent=fmt(target);if(d>0)seekTo(target)});") ||
    !html.includes("$('#miniSeek').addEventListener('input',e=>{miniSeeking=true;const d=seekDuration();const target=Number(e.target.value)/1000*d;$('#miniTime').textContent=fmt(target)+' · '+fmt(d);if(d>0)seekTo(target)});") ||
    !html.includes("audio.addEventListener('seeked',paintTime);") ||
    !html.includes("$('#rewind').addEventListener('click',()=>seekBy(-5));") ||
    !html.includes("$('#forward').addEventListener('click',()=>seekBy(5));") ||
    !html.includes("$('#miniRewind').addEventListener('click',()=>seekBy(-5));") ||
    !html.includes("$('#miniForward').addEventListener('click',()=>seekBy(5));")) {
  errors.push('Both sliders and all skip buttons must route through the audio seek functions and update after seeking finishes.');
}
if (!html.includes("$('#mini').classList.toggle('visible',!!piece&&['practice','loop','tempo','bookmarks'].includes(currentScreen));") ||
    !html.includes("window.scrollTo({top:0,behavior:'instant'});paintTime();") ||
    !html.includes('<button class="home-dates-link" type="button" id="homeCalendarLink" data-goto="calendar" aria-label="Open choir announcements and upcoming dates">') ||
    html.includes('id="homeEventsSection"') ||
    !html.includes("section.classList.toggle('hidden',!items.length&&!announcementsLoadFailed)") ||
    !html.includes("if(section)section.classList.remove('hidden')") ||
    html.includes("meta.textContent=(p.voices||[]).map(v=>v.name).join(' · ')")) {
  errors.push('Home must use a compact link to the full announcements-and-dates screen, omit the large upcoming-dates block and vocal-part inventory, and hide empty announcements.');
}

if (!html.includes("const wasWelcomeOpen=!$('#welcomeBackdrop').classList.contains('hidden')") ||
    !html.includes("if(wasWelcomeOpen)window.scrollTo({top:0,behavior:'instant'});") ||
    !html.includes("if('scrollRestoration'in history)history.scrollRestoration='manual';")) {
  errors.push('First load and first-time profile setup must return the Home page to the top.');
}
const practiceNavUsesQuerySelectorAll =
  html.includes("$('.tab').forEach(b=>{if(b.dataset.tab===activeTab)b.setAttribute('aria-current','page')") ||
  html.includes("document.querySelectorAll('.tab').forEach(b=>{if(b.dataset.tab===activeTab)b.setAttribute('aria-current','page')");
if (!html.includes("function paintNav(name){const activeTab=['bookmarks','loop','tempo','score','lyrics'].includes(name)?'practice':name;") ||
    !practiceNavUsesQuerySelectorAll) {
  errors.push('Practice navigation must use querySelectorAll and remain selected on Bookmarks, Loop, Tempo, Lyrics and Score sub-screens.');
}
if (!html.includes("function jumpToLoopStart(restart=false){if(!loopActive())return;seekTo(aPoint);") ||
    !html.includes("go.onclick=()=>seekTo(b.time)") ||
    html.includes("go.onclick=()=>{showScreen('practice');seekTo(b.time)}")) {
  errors.push('Loop restart and bookmark Go must use the shared audio seek function without leaving the Bookmarks screen.');
}
if (!/const\s+SHELL_CACHE\s*=\s*['"]pro-musica-shell-v\d+['"]/.test(sw)) {
  errors.push('site/sw.js must declare a versioned app-shell cache.');
}
if (!/['"]\.\/index\.html['"]/.test(sw)) {
  errors.push('site/sw.js must precache index.html as part of the app shell.');
}
if (!/['"]\.\/pieces\.json['"]/.test(sw)) {
  errors.push('site/sw.js must precache pieces.json so the song catalogue is available for an offline launch.');
}
const offlineCacheName = 'pro-musica-offline-songs-v1';
if (!html.includes(`const OFFLINE_CACHE='${offlineCacheName}';`) || !sw.includes(`const OFFLINE_CACHE = '${offlineCacheName}';`)) {
  errors.push('The app and service worker must use the same offline-song cache name.');
}

const collectStrings = value => {
  if (typeof value === 'string') return [value];
  if (Array.isArray(value)) return value.flatMap(collectStrings);
  if (value && typeof value === 'object') return Object.values(value).flatMap(collectStrings);
  return [];
};

if (piecesData && Array.isArray(piecesData.pieces)) {
  for (const piece of piecesData.pieces) {
    if (Array.isArray(piece?.voices) && piece.voices.some(v => v?.id === 'soprano')) {
      if (typeof piece.files?.only?.soprano !== 'string' || typeof piece.files?.loud?.soprano !== 'string') {
        errors.push(`Song "${piece.title}" has a single Soprano part but is missing the shared Soprano audio tracks.`);
      }
    }
    if (piece && (typeof piece.lyrics !== 'string' || !piece.lyrics.trim())) {
      errors.push(`Song "${piece.title}" must have one non-empty shared lyrics text.`);
    }
    if (piece && Object.prototype.hasOwnProperty.call(piece, 'lyricsByVoice')) {
      errors.push(`Song "${piece.title}" must not contain part-specific lyrics.`);
    }
    if (!piece || typeof piece.title !== 'string' || !piece.title.trim()) {
      errors.push('Each song entry in pieces.json must have a title.');
      continue;
    }
    if (typeof piece.dir !== 'string' || !piece.dir.trim()) {
      errors.push(`Song "${piece.title}" has no asset directory.`);
      continue;
    }
    const dir = piece.dir.replace(/\\/g, '/');
    const fileNames = [
      ...collectStrings(piece.files),
      ...(typeof piece.score === 'string' ? [piece.score] : []),
      ...(typeof piece.original === 'string' ? [piece.original] : []),
    ];
    const uniqueFiles = [...new Set(fileNames)];
    if (!uniqueFiles.length) errors.push(`Song "${piece.title}" has no audio or score files listed.`);
    for (const fileName of uniqueFiles) {
      if (fileName.startsWith('http://') || fileName.startsWith('https://')) continue;
      await fileExists(path.posix.join(dir, fileName));
    }
  }
}

if (errors.length) {
  console.error('SITE VALIDATION FAILED. Do not publish this site bundle.\n');
  for (const error of errors) console.error(`- ${error}`);
  process.exitCode = 1;
} else {
  console.log('SITE VALIDATION PASSED.');
  console.log(`Songs checked: ${piecesData.pieces.length}`);
  console.log(`Announcements loaded from JSON: ${announcementsData.announcements.length}`);
  console.log(`Events loaded from JSON: ${eventsData.events.length}`);
  console.log('Required app files, song assets, JSON data and JavaScript syntax are present.');
}
