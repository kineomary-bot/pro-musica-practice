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

const piecesData = await readJson('pieces.json');
const announcementsData = await readJson('announcements.json');
const eventsData = await readJson('events.json');
await readJson('manifest.webmanifest');

if (!piecesData || !Array.isArray(piecesData.pieces) || piecesData.pieces.length === 0) {
  errors.push('site/pieces.json must contain a non-empty pieces array; the app must not be published without its song catalogue.');
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
  'id="homeEvents"',
];
for (const marker of requiredHtmlMarkers) {
  if (!html.includes(marker)) errors.push(`site/index.html is missing required startup/app markup: ${marker}`);
}

const showScreenStart = html.indexOf('function showScreen(');
const paintNavStart = html.indexOf('function paintNav(', showScreenStart);
const showScreenSource = showScreenStart >= 0 && paintNavStart > showScreenStart
  ? html.slice(showScreenStart, paintNavStart)
  : '';
if (!showScreenSource.includes("$('.screen').forEach(")) {
  errors.push('Screen navigation must use querySelectorAll ( $ ) to activate the Practice, Bookmarks and Loop screens.');
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
if (!html.includes("$('#seek').addEventListener('input',e=>{seeking=true;const d=seekDuration(),target=Number(e.target.value)/1000*d;$('#timeNow').textContent=fmt(target);if(d>0)seekTo(target)});") ||
    !html.includes("$('#miniSeek').addEventListener('input',e=>{miniSeeking=true;const d=seekDuration();const target=Number(e.target.value)/1000*d;$('#miniTime').textContent=fmt(target)+' · '+fmt(d);if(d>0)seekTo(target)});")) {
  errors.push('Both player sliders must seek audio during dragging.');
}
if (!html.includes("!['bookmarks','loop','tempo'].includes(currentScreen)") ||
    !html.includes("window.scrollTo({top:0,behavior:'instant'});paintTime();")) {
  errors.push('The floating player must not cover the Bookmarks, Loop or Tempo controls and must update visibility on navigation.');
}
if (!html.includes("function jumpToLoopStart(restart=false){if(!loopActive())return;seekTo(aPoint);") ||
    !html.includes("go.onclick=()=>{showScreen('practice');seekTo(b.time)}")) {
  errors.push('Loop restart and bookmark navigation must use the shared audio seek function.');
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
