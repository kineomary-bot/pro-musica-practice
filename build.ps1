# Choir practice app builder (Windows PowerShell version - nothing to install).
#
# Put your MuseScore 4 files (.mscz) in the "songs" folder, then double-click
# "Make practice tracks.bat". For every piece this makes (using MuseScore itself):
#   - an "everyone" mix
#   - a separate isolated audio stem for each voice, plus optional practice mixes
#   - a PDF of the score
#   - a beat map for the app's metronome
# and writes site\pieces.json, which the app reads.
#
# Add a piece: put the .mscz in "songs" and run again (only new/changed files are redone).
# Remove a piece: delete the .mscz from "songs" and run again.
# Order: pieces are sorted by file name, so "01 Joy to the World.mscz" comes first.
# Choir name: put it in a text file called choir-name.txt next to this script.

param(
    [string]$Songs = (Join-Path $PSScriptRoot 'songs'),
    [string]$Site = (Join-Path $PSScriptRoot 'site'),
    [string]$MScore = '',
    [string]$Only = '',
    [double]$BackgroundDb = -20,   # how much quieter the other voices are in "my part louder"
    [switch]$NoOnly,               # skip the "my part only" tracks (smaller site)
    [string]$Bitrate = '64k',      # mp3 bitrate if ffmpeg is installed; 'off' keeps MuseScore's files
    [string]$ChoirName = ''
)

$ErrorActionPreference = 'Stop'
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$BuildVersion = 'ps1-9-quieter-background-voice-isolation'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# ------------------------------------------------------------ MuseScore

function Find-MuseScore {
    $c = New-Object System.Collections.Generic.List[string]
    if ($MScore) { $c.Add($MScore) }
    if ($env:MSCORE) { $c.Add($env:MSCORE) }
    if ($env:ProgramFiles) { $c.Add((Join-Path $env:ProgramFiles 'MuseScore 4\bin\MuseScore4.exe')) }
    if (${env:ProgramFiles(x86)}) { $c.Add((Join-Path ${env:ProgramFiles(x86)} 'MuseScore 4\bin\MuseScore4.exe')) }
    if ($env:LOCALAPPDATA) { $c.Add((Join-Path $env:LOCALAPPDATA 'Programs\MuseScore 4\bin\MuseScore4.exe')) }
    foreach ($n in 'MuseScore4', 'mscore4', 'mscore', 'musescore') {
        $g = Get-Command $n -ErrorAction SilentlyContinue
        if ($g) { $c.Add($g.Source) }
    }
    $c.Add('/Applications/MuseScore 4.app/Contents/MacOS/mscore')
    foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    throw ("Could not find MuseScore 4. Install it, or tell me where it is, for example:`n" +
           '  .\build.ps1 -MScore "C:\Program Files\MuseScore 4\bin\MuseScore4.exe"')
}

function Invoke-MuseScore([string[]]$ArgList) {
    # Start-Process needs one properly quoted argument string on Windows PowerShell 5.1.
    # Capture stdout/stderr separately for every CLI operation so a failed export can be
    # diagnosed from the preserved temporary build folder instead of relying on a generic error.
    $q = ($ArgList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $logDir = $script:DiagnosticDir
    if (-not $logDir -or -not (Test-Path -LiteralPath $logDir)) {
        $logDir = [IO.Path]::GetTempPath()
    }

    $name = 'command'
    if ($ArgList.Count -ge 2 -and ($ArgList[0] -eq '-o' -or $ArgList[0] -eq '--export-to')) {
        $name = [IO.Path]::GetFileName($ArgList[1])
    } elseif ($ArgList.Count -ge 2 -and $ArgList[0] -eq '-j') {
        $name = [IO.Path]::GetFileNameWithoutExtension($ArgList[1])
    }
    $name = $name -replace '[^a-zA-Z0-9._-]', '_'
    $prefix = Join-Path $logDir ('musescore-' + $name)
    $stdoutLog = $prefix + '.stdout.txt'
    $stderrLog = $prefix + '.stderr.txt'
    $commandLog = $prefix + '.command.txt'
    foreach ($log in @($stdoutLog, $stderrLog, $commandLog)) {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
    [IO.File]::WriteAllText($commandLog, ("Executable: " + $script:Mscore + "`r`nArguments: " + $q + "`r`n"), $Utf8)

    try {
        $proc = Start-Process -FilePath $script:Mscore -ArgumentList $q -Wait -NoNewWindow -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -ErrorAction Stop
        [IO.File]::AppendAllText($commandLog, ("Exit code: " + $proc.ExitCode + "`r`n"), $Utf8)
        return $proc.ExitCode
    } catch {
        [IO.File]::AppendAllText($commandLog, ("Start/export exception: " + $_.Exception.Message + "`r`n"), $Utf8)
        throw
    }
}

function Test-Output([string]$path) {
    return ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt 0))
}

# jobs: list of @{ In = ...; Out = ... }
function Invoke-Exports($jobs) {
    # Use MuseScore's JSON batch mode only for score formats such as PDF and MIDI.
    # Audio exports are deliberately done separately with -o: recent MuseScore 4 versions
    # have had problems with MP3/WAV exports requested through JSON jobs.
    $arr = @()
    foreach ($j in $jobs) { $arr += [ordered]@{ 'in' = $j.In; 'out' = $j.Out } }
    $jf = Join-Path ([IO.Path]::GetTempPath()) ('jobs-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($jf, (ConvertTo-Json -InputObject $arr -Depth 5), $Utf8)
    try {
        try { [void](Invoke-MuseScore @('-j', $jf)) }
        catch { Write-Warning ("MuseScore batch export failed; retrying individual exports. " + $_.Exception.Message) }
    } finally { Remove-Item -LiteralPath $jf -ErrorAction SilentlyContinue }

    foreach ($j in $jobs) {
        if (-not (Test-Output $j.Out)) {
            try { [void](Invoke-MuseScore @('-o', $j.Out, $j.In)) }
            catch { Write-Warning ("MuseScore export command failed for $($j.Out): " + $_.Exception.Message) }
        }
        if (-not (Test-Output $j.Out)) {
            throw ("MuseScore did not produce a non-empty file: " + $j.Out + "`n(from " + $j.In + "). Try opening that score in MuseScore 4 and saving it once, then run again.")
        }
    }
}

function Export-Audio([string]$inputScore, [string]$outputAudio) {
    if (Test-Path -LiteralPath $outputAudio) { Remove-Item -LiteralPath $outputAudio -Force }
    $exitCode = $null
    try { $exitCode = Invoke-MuseScore @('-o', $outputAudio, $inputScore) }
    catch { throw ("MuseScore could not start or complete audio export for ${outputAudio}: " + $_.Exception.Message) }
    if (-not (Test-Output $outputAudio)) {
        $stderrLog = Join-Path $script:DiagnosticDir ('musescore-' + ([IO.Path]::GetFileName($outputAudio) -replace '[^a-zA-Z0-9._-]', '_') + '.stderr.txt')
        throw ("MuseScore did not produce a non-empty audio file: " + $outputAudio + "`n(from " + $inputScore + "). See the MuseScore command/stderr logs in: " + $script:DiagnosticDir + "`nExpected stderr log: " + $stderrLog)
    }
    if ($exitCode -ne 0) {
        throw ("MuseScore returned exit code $exitCode while exporting ${outputAudio}. The file may be incomplete; fix the export error and run the build again.")
    }
}

# ------------------------------------------------------------ score info

function Get-Slug([string]$s) {
    $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '[^\x00-\x7F]', ''
    $s = ($s -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
    if (-not $s) { $s = 'x' }
    return $s
}

function Get-VoiceName([string]$raw) {
    $s = ($raw -replace '<[^>]+>', '').Trim()
    $s = $s -replace '(?<=[A-Za-z])(?=\d)', ' '
    $s = $s -replace '\s+', ' '
    if ($s.Length -gt 0) { $s = $s.Substring(0, 1).ToUpperInvariant() + $s.Substring(1) }
    return $s
}

function Get-MuseNoteName([int]$pitch, [int]$tpc) {
    # MuseScore tonal-pitch-class values preserve the score's enharmonic spelling.
    $spellings = @{
        '-1'='Fbb'; '0'='Cbb'; '1'='Gbb'; '2'='Dbb'; '3'='Abb'; '4'='Ebb'; '5'='Bbb'
        '6'='Fb'; '7'='Cb'; '8'='Gb'; '9'='Db'; '10'='Ab'; '11'='Eb'; '12'='Bb'
        '13'='F'; '14'='C'; '15'='G'; '16'='D'; '17'='A'; '18'='E'; '19'='B'
        '20'='F#'; '21'='C#'; '22'='G#'; '23'='D#'; '24'='A#'; '25'='E#'; '26'='B#'
    }
    if ($spellings.ContainsKey([string]$tpc)) {
        $spelling = [string]$spellings[[string]$tpc]
        if ($spelling -match '^([A-G])([#b]{0,2})$') {
            $letter = $Matches[1]
            $accidental = $Matches[2]
            $naturalPitches = @{ C=0; D=2; E=4; F=5; G=7; A=9; B=11 }
            $natural = $naturalPitches[$letter]
            $offset = ([regex]::Matches($accidental, '#').Count) - ([regex]::Matches($accidental, 'b').Count)
            $octave = [int][math]::Floor(($pitch - ($natural + $offset)) / 12) - 1
            return ($spelling + $octave)
        }
    }
    $chromatic = @('C','C#','D','D#','E','F','F#','G','G#','A','A#','B')
    return ($chromatic[$pitch % 12] + ([int][math]::Floor($pitch / 12) - 1))
}

function Get-ScoreInfo([string]$mscz) {
    $z = [IO.Compression.ZipFile]::OpenRead($mscz)
    try {
        $entry = $z.Entries | Where-Object { $_.FullName.EndsWith('.mscx') -and ($_.FullName -notlike '*/*') } | Select-Object -First 1
        if (-not $entry) { throw ((Split-Path $mscz -Leaf) + ': no score inside (is it a MuseScore 4 file?)') }
        $hasAudio = $z.Entries | Where-Object { $_.FullName -eq 'audiosettings.json' }
        if (-not $hasAudio) { throw ((Split-Path $mscz -Leaf) + ': open it in MuseScore 4 and save it once, then try again.') }
        $sr = New-Object IO.StreamReader($entry.Open(), $Utf8)
        try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $z.Dispose() }

    $xml = New-Object System.Xml.XmlDocument
    $xml.LoadXml($text)
    $parts = @()
    $staffNodes = @($xml.SelectNodes('/museScore/Score/Staff'))
    $partIndex = 0
    foreach ($p in $xml.SelectNodes('/museScore/Score/Part')) {
        $name = ''
        foreach ($tag in 'longName', 'shortName', 'trackName') {
            $n = $p.SelectSingleNode("Instrument/$tag")
            if ($n -and $n.InnerText.Trim()) { $name = $n.InnerText; break }
        }
        if (-not $name.Trim()) {
            $n = $p.SelectSingleNode('trackName')
            if ($n) { $name = $n.InnerText } else { $name = 'Part ' + $p.GetAttribute('id') }
        }

        # Use the first pitched note in the matching music staff, skipping opening rests.
        $partId = $p.GetAttribute('id')
        $staff = $xml.SelectSingleNode("/museScore/Score/Staff[@id='$partId']")
        if (-not $staff -and $partIndex -lt $staffNodes.Count) { $staff = $staffNodes[$partIndex] }
        $startingMidi = $null
        $startingNote = $null
        if ($staff) {
            $firstNote = $staff.SelectSingleNode('.//Chord/Note')
            if ($firstNote) {
                $pitchNode = $firstNote.SelectSingleNode('pitch')
                $tpcNode = $firstNote.SelectSingleNode('tpc')
                if ($pitchNode -and $pitchNode.InnerText -match '^\d+$') {
                    $startingMidi = [int]$pitchNode.InnerText
                    $tpc = 14
                    if ($tpcNode -and $tpcNode.InnerText -match '^-?\d+$') { $tpc = [int]$tpcNode.InnerText }
                    $startingNote = Get-MuseNoteName $startingMidi $tpc
                }
            }
        }
        $parts += [pscustomobject]@{
            Id = $partId
            Name = (Get-VoiceName $name)
            StartingMidi = $startingMidi
            StartingNote = $startingNote
        }
        $partIndex++
    }
    $first = $null
    $m = $xml.SelectSingleNode('/museScore/Score/Part/Staff/Measure[1]')
    if ($m) {
        $lenText = $m.GetAttribute('len')
        if (-not $lenText) {
            $lenNode = $m.SelectSingleNode('len')
            if ($lenNode) { $lenText = $lenNode.InnerText.Trim() }
        }
        if ($lenText -match '^\s*([0-9]+)\s*/\s*([0-9]+)\s*$' -and [double]$Matches[2] -ne 0) {
            $first = [double]$Matches[1] / [double]$Matches[2]
        } else {
            # MuseScore 4 commonly stores measure length in its contents rather than a len
            # attribute. Sum note/rest durations per voice as a fallback, which can identify
            # an anacrusis when the first measure is shorter than the notated bar.
            $voiceLengths = @()
            foreach ($voiceNode in $m.SelectNodes('voice')) {
                $voiceLength = 0.0
                foreach ($durationNode in $voiceNode.SelectNodes('.//Chord/duration | .//Rest/duration')) {
                    if ($durationNode.InnerText -match '^\s*([0-9]+)\s*/\s*([0-9]+)\s*$' -and [double]$Matches[2] -ne 0) {
                        $voiceLength += [double]$Matches[1] / [double]$Matches[2]
                    }
                }
                if ($voiceLength -gt 0) { $voiceLengths += $voiceLength }
            }
            if ($voiceLengths.Count -gt 0) { $first = ($voiceLengths | Measure-Object -Maximum).Maximum }
        }
    }
    return [pscustomobject]@{ Parts = $parts; FirstMeasure = $first }
}

function Set-Prop($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# Copy a .mscz and prepare its audio variant. Mode: all | loud | only
# MuseScore 4's CLI has a known bug: mixer mute states can be ignored during MP3 export.
# For "only", remove the other score parts and their staves from the temporary score itself.
function New-Variant([string]$src, [string]$dst, [string]$mode, [string]$targetId, [string[]]$partIds) {
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $z = [IO.Compression.ZipFile]::Open($dst, [IO.Compression.ZipArchiveMode]::Update)
    try {
        # Do not modify the score XML. MuseScore's own part/mixer data is retained;
        # isolated stems are created by lowering unwanted tracks' output volume.

        $e = $z.GetEntry('audiosettings.json')
        if (-not $e) { throw "Could not find audiosettings.json inside '$dst'." }
        $sr = New-Object IO.StreamReader($e.Open(), $Utf8)
        try { $json = $sr.ReadToEnd() } finally { $sr.Dispose() }
        $s = ConvertFrom-Json -InputObject $json
        $matchedParts = @{}
        $matchedTarget = $false
        foreach ($tr in @($s.tracks)) {
            $trackPartId = [string]$tr.partId
            if ($trackPartId -eq '999' -or [string]$tr.instrumentId -eq 'metronome') {
                if ($mode -eq 'only') {
                    if (-not $tr.out) { Set-Prop $tr 'out' ([pscustomobject]@{}) }
                    Set-Prop $tr.out 'volumeDb' -60
                    continue
                }
                if (-not $tr.soloMuteState) { Set-Prop $tr 'soloMuteState' ([pscustomobject]@{}) }
                Set-Prop $tr.soloMuteState 'mute' $true
                continue
            }
            if ($partIds -notcontains $trackPartId) { continue }
            $matchedParts[$trackPartId] = $true
            $mine = ($trackPartId -eq [string]$targetId)
            if ($mine) { $matchedTarget = $true }
            if (-not $tr.out) { Set-Prop $tr 'out' ([pscustomobject]@{}) }
            if (-not $tr.soloMuteState) { Set-Prop $tr 'soloMuteState' ([pscustomobject]@{}) }
            Set-Prop $tr.out 'volumeDb' 0
            Set-Prop $tr.soloMuteState 'mute' $false
            Set-Prop $tr.soloMuteState 'solo' $false
            if ($mode -eq 'loud' -and -not $mine) { Set-Prop $tr.out 'volumeDb' $BackgroundDb }
            elseif ($mode -eq 'only' -and -not $mine) {
                # CLI export may ignore mute/solo states, but changing output gain is an
                # established workaround. -60 dB makes the non-target voices effectively silent.
                Set-Prop $tr.out 'volumeDb' -60
                Set-Prop $tr.soloMuteState 'mute' $false
                Set-Prop $tr.soloMuteState 'solo' $false
            }
        }
        if ($mode -ne 'all' -and -not $matchedTarget) {
            throw ("Could not match requested voice part '$targetId' to a MuseScore audio track. Available audio track part IDs: " + (($s.tracks | ForEach-Object { [string]$_.partId } | Sort-Object -Unique) -join ', ') + ". No practice audio was exported.")
        }
        $missingParts = @($partIds | Where-Object { -not $matchedParts.ContainsKey([string]$_) })
        if ($mode -ne 'only' -and $missingParts.Count -gt 0) {
            throw ("These score part IDs were not found in audiosettings.json: " + ($missingParts -join ', ') + ". No practice audio was exported.")
        }
        $e.Delete()
        $ne = $z.CreateEntry('audiosettings.json')
        $sw = New-Object IO.StreamWriter($ne.Open(), $Utf8)
        try { $sw.Write((ConvertTo-Json -InputObject $s -Depth 50)) } finally { $sw.Dispose() }
    } finally { $z.Dispose() }
}

# ------------------------------------------------------------ MIDI -> beats

function Read-MidiTiming([string]$path) {
    $d = [IO.File]::ReadAllBytes($path)
    if ($d.Length -lt 14 -or [Text.Encoding]::ASCII.GetString($d, 0, 4) -ne 'MThd') { throw 'Invalid or truncated MIDI file (missing MThd header).' }
    $headerLen = ([int]$d[4] -shl 24) -bor ([int]$d[5] -shl 16) -bor ([int]$d[6] -shl 8) -bor [int]$d[7]
    if ($headerLen -lt 6 -or $d.Length -lt (8 + $headerLen)) { throw 'Invalid MIDI header length.' }
    $ntr = ([int]$d[10] -shl 8) -bor [int]$d[11]
    $division = ([int]$d[12] -shl 8) -bor [int]$d[13]
    if (($division -band 0x8000) -ne 0) { throw 'MIDI uses SMPTE timing; this beat-map builder currently requires ticks-per-quarter-note timing.' }
    $ppq = $division
    if ($ppq -le 0) { throw 'MIDI has an invalid ticks-per-quarter-note value.' }

    $pos = 8 + $headerLen
    $tempos = @(); $sigs = @(); $end = 0
    for ($t = 0; $t -lt $ntr; $t++) {
        if ($pos + 8 -gt $d.Length -or [Text.Encoding]::ASCII.GetString($d, $pos, 4) -ne 'MTrk') { throw "Invalid MIDI track header at byte $pos." }
        $len = ([int64]$d[$pos + 4] -shl 24) -bor ([int64]$d[$pos + 5] -shl 16) -bor ([int64]$d[$pos + 6] -shl 8) -bor [int64]$d[$pos + 7]
        $i = $pos + 8
        $stop = $i + $len
        if ($stop -gt $d.Length) { throw 'MIDI track extends beyond the end of the file.' }
        $pos = [int]$stop
        $tick = [int64]0; $status = 0
        while ($i -lt $stop) {
            $v = 0
            do {
                if ($i -ge $stop) { throw 'Truncated MIDI variable-length delta time.' }
                $c = [int]$d[$i]; $i++
                $v = ($v -shl 7) -bor ($c -band 0x7F)
            } while ($c -band 0x80)
            $tick += $v
            if ($i -ge $stop) { throw 'Truncated MIDI event.' }
            $b = [int]$d[$i]

            if ($b -eq 0xFF) {
                # Meta events cancel running status.
                $status = 0; $i++
                if ($i -ge $stop) { throw 'Truncated MIDI meta event.' }
                $typ = [int]$d[$i]; $i++
                $l = 0
                do {
                    if ($i -ge $stop) { throw 'Truncated MIDI meta-event length.' }
                    $c = [int]$d[$i]; $i++
                    $l = ($l -shl 7) -bor ($c -band 0x7F)
                } while ($c -band 0x80)
                if ($i + $l -gt $stop) { throw 'MIDI meta-event payload exceeds track boundary.' }
                if ($typ -eq 0x51 -and $l -ge 3) {
                    $us = ([int]$d[$i] -shl 16) -bor ([int]$d[$i + 1] -shl 8) -bor [int]$d[$i + 2]
                    if ($us -gt 0) { $tempos += [pscustomobject]@{ Tick = $tick; Us = $us } }
                } elseif ($typ -eq 0x58 -and $l -ge 2) {
                    $denPow = [int]$d[$i + 1]
                    if ($denPow -le 7) { $sigs += [pscustomobject]@{ Tick = $tick; Num = [int]$d[$i]; Den = [int][math]::Pow(2, $denPow) } }
                }
                $i += $l
                if ($typ -eq 0x2F) { break }
            } elseif ($b -eq 0xF0 -or $b -eq 0xF7) {
                $status = 0; $i++
                $l = 0
                do {
                    if ($i -ge $stop) { throw 'Truncated MIDI system-exclusive length.' }
                    $c = [int]$d[$i]; $i++
                    $l = ($l -shl 7) -bor ($c -band 0x7F)
                } while ($c -band 0x80)
                if ($i + $l -gt $stop) { throw 'MIDI system-exclusive payload exceeds track boundary.' }
                $i += $l
            } else {
                $data1Present = $false
                if ($b -band 0x80) {
                    $status = $b; $i++
                } else {
                    if ($status -eq 0) { throw 'MIDI running-status data encountered without a preceding channel status.' }
                    $data1Present = $true; $i++
                }
                # Only channel voice events are needed here. Account correctly for running-status
                # messages, where the first data byte has already been consumed above.
                if (($status -band 0xF0) -lt 0x80 -or ($status -band 0xF0) -gt 0xE0) { throw 'Unsupported MIDI event status in track.' }
                $dataCount = if ((($status -band 0xF0) -eq 0xC0) -or (($status -band 0xF0) -eq 0xD0)) { 1 } else { 2 }
                $remaining = $dataCount - [int]$data1Present
                if ($i + $remaining -gt $stop) { throw 'Truncated MIDI channel event.' }
                $i += $remaining
            }
        }
        if ($tick -gt $end) { $end = $tick }
    }
    if ($tempos.Count -eq 0) { $tempos = @([pscustomobject]@{ Tick = 0; Us = 500000 }) }
    if ($sigs.Count -eq 0) { $sigs = @([pscustomobject]@{ Tick = 0; Num = 4; Den = 4 }) }
    # Multiple tracks can contain duplicate metadata at the same tick. Keep the last event
    # at each tick so timing conversion does not create ambiguous zero-length segments.
    $tempos = @($tempos | Sort-Object Tick | Group-Object Tick | ForEach-Object { $_.Group[-1] } | Sort-Object Tick)
    $sigs = @($sigs | Sort-Object Tick | Group-Object Tick | ForEach-Object { $_.Group[-1] } | Sort-Object Tick)
    return [pscustomobject]@{ Ppq = $ppq; Tempos = $tempos; Sigs = $sigs; End = $end }
}

function Get-BeatMap([string]$midiPath, $firstMeasure) {
    $m = Read-MidiTiming $midiPath
    $ppq = $m.Ppq
    if ($ppq -le 0) { throw 'Cannot build beat map: MIDI ticks-per-quarter-note is invalid.' }
    $tempos = @($m.Tempos); $sigs = @($m.Sigs)
    if ($tempos.Count -eq 0 -or $tempos[0].Tick -gt 0) { $tempos = @([pscustomobject]@{ Tick = 0; Us = 500000 }) + $tempos }
    if ($sigs.Count -eq 0 -or $sigs[0].Tick -gt 0) { $sigs = @([pscustomobject]@{ Tick = 0; Num = 4; Den = 4 }) + $sigs }

    # tick -> seconds
    $segs = @(); $acc = 0.0
    for ($k = 0; $k -lt $tempos.Count; $k++) {
        $segs += [pscustomobject]@{ Tick = $tempos[$k].Tick; Sec = $acc; Us = $tempos[$k].Us }
        if ($k + 1 -lt $tempos.Count) {
            $acc += ($tempos[$k + 1].Tick - $tempos[$k].Tick) / $ppq * $tempos[$k].Us / 1e6
        }
    }
    $toSec = {
        param($tick)
        $s = $segs[0]
        foreach ($x in $segs) { if ($x.Tick -le $tick) { $s = $x } }
        return $s.Sec + ($tick - $s.Tick) / $ppq * $s.Us / 1e6
    }

    # pickup (anacrusis)
    $full0 = [int]($ppq * 4 * $sigs[0].Num / $sigs[0].Den)
    $pickup = 0
    if ($null -ne $firstMeasure) {
        $pk = [int][math]::Round($firstMeasure * $ppq * 4)
        if ($pk -gt 0 -and $pk -lt $full0) { $pickup = $pk }
    }

    $beats = New-Object System.Collections.Generic.List[object]
    for ($k = 0; $k -lt $sigs.Count; $k++) {
        $start = $sigs[$k].Tick; $num = $sigs[$k].Num; $den = $sigs[$k].Den
        if ($k + 1 -lt $sigs.Count) { $stop = $sigs[$k + 1].Tick } else { $stop = $m.End + 1 }
        $beat = [int]($ppq * 4 / $den)
        if ($den -eq 8 -and $num -ge 6 -and ($num % 3) -eq 0) { $beat = $beat * 3 }   # 6/8, 9/8, 12/8
        $bar = [int]($ppq * 4 * $num / $den)
        $anchor = $start
        if ($k -eq 0 -and $pickup -gt 0) {
            # Click through the pickup from its start, then mark the first full-bar downbeat.
            $anchor = $start + $pickup
            $pickupTick = $start
            while ($pickupTick -lt $anchor) {
                $beats.Add(@([math]::Round((& $toSec $pickupTick), 3), 0))
                $pickupTick += $beat
            }
        }
        $tick = $anchor
        while ($tick -lt $stop) {
            $down = 0
            if ($tick -ge $anchor -and (($tick - $anchor) % $bar) -eq 0) { $down = 1 }
            $sec = [math]::Round((& $toSec $tick), 3)
            $beats.Add(@($sec, $down))
            $tick += $beat
        }
    }
    return [pscustomobject]@{
        Bpm = [int][math]::Round(60e6 / $tempos[0].Us)
        Beats = $beats
        Duration = [math]::Round((& $toSec $m.End), 2)
    }
}

# ------------------------------------------------------------ build

$script:Ffmpeg = $null
$g = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($g) { $script:Ffmpeg = $g.Source }

function Compress-Mp3([string]$mp3) {
    $tmp = $mp3 + '.tmp.mp3'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $a = '-nostdin -y -loglevel error -i "' + $mp3 + '" -ac 1 -b:a ' + $Bitrate + ' "' + $tmp + '"'
    $proc = Start-Process -FilePath $script:Ffmpeg -ArgumentList $a -Wait -NoNewWindow -PassThru -ErrorAction Stop
    if ($proc.ExitCode -eq 0 -and (Test-Output $tmp)) {
        Move-Item -LiteralPath $tmp -Destination $mp3 -Force
    } else {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        throw "ffmpeg failed to compress '$mp3' (exit code $($proc.ExitCode)); original audio was kept."
    }
}

function Build-Piece([IO.FileInfo]$src, [string]$outdir) {
    $info = Get-ScoreInfo $src.FullName
    $voices = @(); $seen = @{}
    foreach ($p in $info.Parts) {
        $id = Get-Slug $p.Name
        $base = $id; $n = 2
        while ($seen.ContainsKey($id)) { $id = "$base-$n"; $n++ }
        $seen[$id] = $true
        $voices += [pscustomobject]@{
            Id = $id; Name = $p.Name; Part = $p.Id
            StartingMidi = $p.StartingMidi; StartingNote = $p.StartingNote
        }
    }

    $partIds = @($voices | ForEach-Object { [string]$_.Part })
    $opts = "$BuildVersion|$BackgroundDb|$($NoOnly.IsPresent)|$Bitrate|$([bool]$script:Ffmpeg)"
    $stamp = (Get-FileHash -LiteralPath $src.FullName -Algorithm SHA1).Hash + '|' + $opts
    $stampFile = Join-Path $outdir '.stamp'
    $infoFile = Join-Path $outdir 'info.json'
    if ((Test-Path -LiteralPath $stampFile) -and (Test-Path -LiteralPath $infoFile) -and
        ([IO.File]::ReadAllText($stampFile) -eq $stamp)) {
        # Audio exports are already valid and unchanged. Refresh score-derived metadata in
        # the cached info file without needlessly re-exporting every MP3.
        $cached = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($infoFile))
        foreach ($cachedVoice in @($cached.voices)) {
            $voiceDetails = $voices | Where-Object { $_.Id -eq [string]$cachedVoice.id } | Select-Object -First 1
            if ($voiceDetails) {
                Set-Prop $cachedVoice 'startingMidi' $voiceDetails.StartingMidi
                Set-Prop $cachedVoice 'startingNote' $voiceDetails.StartingNote
            }
        }
        [IO.File]::WriteAllText($infoFile, (ConvertTo-Json -InputObject $cached -Depth 10 -Compress), $Utf8)
        Write-Host '  audio unchanged; refreshed starting-note metadata'
        return $cached
    }

    if (Test-Path -LiteralPath $outdir) { Remove-Item -LiteralPath $outdir -Recurse -Force }
    New-Item -ItemType Directory -Path $outdir | Out-Null

    $td = Join-Path ([IO.Path]::GetTempPath()) ('choir-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $td | Out-Null
    $script:DiagnosticDir = $td
    $buildSucceeded = $false
    try {
        $jobs = @()
        $loud = [ordered]@{}; $only = [ordered]@{}
        $vAll = Join-Path $td 'all.mscz'
        New-Variant $src.FullName $vAll 'all' '' $partIds

        # Export every audio file individually. MuseScore 4 JSON batch jobs are not reliable
        # for audio exports; non-empty MP3s from a batch can even be silent, so checking only
        # whether a file exists is not enough to justify using that route.
        Export-Audio $vAll (Join-Path $outdir 'all.mp3')
        foreach ($v in $voices) {
            foreach ($mode in 'loud', 'only') {
                if ($mode -eq 'only' -and $NoOnly) { continue }
                $f = Join-Path $td ($mode + '-' + $v.Id + '.mscz')
                New-Variant $src.FullName $f $mode $v.Part $partIds
                $out = $mode + '-' + $v.Id + '.mp3'
                Export-Audio $f (Join-Path $outdir $out)
                if ($mode -eq 'loud') { $loud[$v.Id] = $out } else { $only[$v.Id] = $out }
            }
        }
        $mid = Join-Path $td 'beats.mid'
        $jobs += @{ In = $src.FullName; Out = (Join-Path $outdir 'score.pdf') }
        $jobs += @{ In = $src.FullName; Out = $mid }
        Invoke-Exports $jobs
        $bm = Get-BeatMap $mid $info.FirstMeasure
        $buildSucceeded = $true
    } catch {
        Write-Host "`nBuild failed while working with temporary score files. Diagnostics kept at: $td"
        Write-Host "Please keep this folder until the failure has been diagnosed."
        throw
    } finally {
        if ($buildSucceeded) {
            Remove-Item -LiteralPath $td -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($script:Ffmpeg -and $Bitrate -ne 'off') {
        foreach ($mp3 in (Get-ChildItem -LiteralPath $outdir -Filter '*.mp3')) { Compress-Mp3 $mp3.FullName }
    }

    # Never publish a nominally isolated voice file if MuseScore exported the full mix again.
    $allHash = (Get-FileHash -LiteralPath (Join-Path $outdir 'all.mp3') -Algorithm SHA256).Hash
    foreach ($v in $voices) {
        if ($NoOnly) { continue }
        $onlyFile = Join-Path $outdir ('only-' + $v.Id + '.mp3')
        if ((Get-FileHash -LiteralPath $onlyFile -Algorithm SHA256).Hash -eq $allHash) {
            throw ("The isolated track for '$($v.Name)' is byte-for-byte identical to all.mp3. The build has stopped rather than publishing a misleading voice track. Check the score's MuseScore mixer/audio settings and rebuild.")
        }
    }

    $voiceList = @()
    foreach ($v in $voices) {
        $voiceList += [ordered]@{
            id = $v.Id; name = $v.Name
            startingMidi = $v.StartingMidi; startingNote = $v.StartingNote
        }
    }
    $result = [ordered]@{
        voices = $voiceList
        files = [ordered]@{ all = 'all.mp3'; loud = $loud; only = $only; stems = $only }
        score = 'score.pdf'
        bpm = $bm.Bpm
        duration = $bm.Duration
        beats = $bm.Beats
    }
    [IO.File]::WriteAllText($infoFile, (ConvertTo-Json -InputObject $result -Depth 10 -Compress), $Utf8)
    [IO.File]::WriteAllText($stampFile, $stamp, $Utf8)
    return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($infoFile)))
}

# ------------------------------------------------------------ main

$script:Mscore = Find-MuseScore
if (-not $script:Ffmpeg) { Write-Host 'Note: ffmpeg not found, so audio files will be large. (Optional: install ffmpeg.)' }

if (-not (Test-Path -LiteralPath $Songs)) { New-Item -ItemType Directory -Path $Songs | Out-Null }
$audio = Join-Path $Site 'audio'
if (-not (Test-Path -LiteralPath $audio)) { New-Item -ItemType Directory -Path $audio -Force | Out-Null }

$files = @(Get-ChildItem -LiteralPath $Songs -Filter '*.mscz' | Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)
if ($files.Count -eq 0) { throw "No .mscz files found in $Songs" }

if (-not $ChoirName) {
    $cn = Join-Path $PSScriptRoot 'choir-name.txt'
    if (Test-Path -LiteralPath $cn) { $ChoirName = ([IO.File]::ReadAllText($cn)).Trim() }
}
if (-not $ChoirName) { $ChoirName = 'Choir Practice' }

$pieces = New-Object System.Collections.Generic.List[object]
$performances = New-Object System.Collections.Generic.List[object]
$performanceAssignments = @{}
$performanceIdsSeen = @{}

# Build aliases from source score filenames, cleaned titles and stable song IDs.
# This allows a performance to refer to a song by any of those readable identifiers.
$songAliasToId = @{}
$ambiguousSongAliases = @{}
foreach ($sourceFile in $files) {
    $sourceStem = [IO.Path]::GetFileNameWithoutExtension($sourceFile.Name)
    $sourceTitle = ($sourceStem -replace '^\s*\d+\s*[-_.)]*\s*', '').Trim()
    if (-not $sourceTitle) { $sourceTitle = $sourceStem }
    $sourceId = Get-Slug $sourceStem
    foreach ($alias in @($sourceStem, $sourceTitle, $sourceId)) {
        if ([string]::IsNullOrWhiteSpace([string]$alias)) { continue }
        if ($songAliasToId.ContainsKey([string]$alias) -and $songAliasToId[[string]$alias] -ne $sourceId) {
            $ambiguousSongAliases[[string]$alias] = $true
        } else {
            $songAliasToId[[string]$alias] = $sourceId
        }
    }
}

# songs/performances.json defines the actual programmes. Each programme lists one or
# more source song filenames, cleaned titles or stable song IDs. A song may belong to
# more than one performance; the generated catalogue stores those performance IDs on
# each song. No performance assignments are guessed by the build.
$performanceFile = Join-Path $Songs 'performances.json'
if (-not (Test-Path -LiteralPath $performanceFile)) {
    throw "Missing $performanceFile. Create it with a JSON object containing a 'performances' array (an empty array is valid)."
}
try {
    $parsedPerformanceConfig = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($performanceFile))
} catch {
    throw "Could not read $performanceFile. Use JSON with a top-level 'performances' array. Details: $($_.Exception.Message)"
}
if ($null -eq $parsedPerformanceConfig -or $parsedPerformanceConfig.PSObject.Properties.Name -notcontains 'performances') {
    throw "Could not read $performanceFile. It must contain a top-level 'performances' array."
}
foreach ($rawPerformance in @($parsedPerformanceConfig.performances)) {
    $performanceId = ([string]$rawPerformance.id).Trim().ToLowerInvariant()
    $performanceName = ([string]$rawPerformance.name).Trim()
    $performanceStatus = ([string]$rawPerformance.status).Trim().ToLowerInvariant()
    if ($performanceId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Invalid performance ID '$performanceId' in $performanceFile. Use lowercase letters, numbers and hyphens, for example 'winter-concert-2027'."
    }
    if ([string]::IsNullOrWhiteSpace($performanceName)) {
        throw "Performance '$performanceId' needs a non-empty name in $performanceFile."
    }
    if ($performanceIdsSeen.ContainsKey($performanceId)) {
        throw "Duplicate performance ID '$performanceId' in $performanceFile."
    }
    if ($performanceStatus -notin @('draft', 'active', 'archived')) {
        throw "Performance '$performanceId' has invalid status '$performanceStatus'. Use draft, active or archived."
    }

    $performanceDate = $null
    if ($null -ne $rawPerformance.date -and -not [string]::IsNullOrWhiteSpace([string]$rawPerformance.date)) {
        $dateText = ([string]$rawPerformance.date).Trim()
        try {
            $parsedDate = [DateTime]::ParseExact($dateText, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            $performanceDate = $parsedDate.ToString('yyyy-MM-dd')
        } catch {
            throw "Performance '$performanceId' has invalid date '$dateText'. Use YYYY-MM-DD or null."
        }
    }
    if ($null -eq $rawPerformance.songs -or $rawPerformance.songs -isnot [Array]) {
        throw "Performance '$performanceId' must have a 'songs' array. Use an empty array if the programme is not assigned yet."
    }

    $assignedSongIds = New-Object System.Collections.Generic.List[string]
    foreach ($songReferenceValue in @($rawPerformance.songs)) {
        $songReference = ([string]$songReferenceValue).Trim()
        if ([string]::IsNullOrWhiteSpace($songReference)) {
            throw "Performance '$performanceId' contains a blank song reference in $performanceFile."
        }
        if ($ambiguousSongAliases.ContainsKey($songReference)) {
            throw "Song reference '$songReference' is ambiguous. Use the exact source filename or stable song ID in $performanceFile."
        }
        if (-not $songAliasToId.ContainsKey($songReference)) {
            throw "Performance '$performanceId' references '$songReference', but no matching .mscz file exists in $Songs."
        }
        $songId = [string]$songAliasToId[$songReference]
        if (-not $assignedSongIds.Contains($songId)) { $assignedSongIds.Add($songId) }
        if (-not $performanceAssignments.ContainsKey($songId)) {
            $performanceAssignments[$songId] = New-Object System.Collections.Generic.List[string]
        }
        if (-not $performanceAssignments[$songId].Contains($performanceId)) {
            $performanceAssignments[$songId].Add($performanceId)
        }
    }

    $performanceIdsSeen[$performanceId] = $true
    $performances.Add([ordered]@{
        id = $performanceId
        name = $performanceName
        date = $performanceDate
        status = $performanceStatus
        songs = @($assignedSongIds.ToArray())
    })
}
$keep = @{}
$slugOwners = @{}
foreach ($f in $files) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $title = ($stem -replace '^\s*\d+\s*[-_.)]*\s*', '').Trim()
    if (-not $title) { $title = $stem }
    $pid2 = Get-Slug $stem
    if ($keep.ContainsKey($pid2)) {
        throw ("Song filename collision: '$stem' and '$($slugOwners[$pid2])' both map to '$pid2'. Rename one file so each song has a unique slug.")
    }
    $keep[$pid2] = $true
    $slugOwners[$pid2] = $stem
    Write-Host $f.Name
    $dir = Join-Path $audio $pid2
    if ($Only -and ($f.Name.IndexOf($Only, [StringComparison]::OrdinalIgnoreCase) -lt 0)) {
        $inf = Join-Path $dir 'info.json'
        if (-not (Test-Path -LiteralPath $inf)) { Write-Host '  (skipped, not built yet)'; continue }
        $info = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($inf))
    } else {
        $info = Build-Piece $f $dir
    }
    $songPerformanceIds = @()
    if ($performanceAssignments.ContainsKey($pid2)) {
        $songPerformanceIds = @($performanceAssignments[$pid2].ToArray())
    }
    $entry = [ordered]@{ id = $pid2; title = $title; dir = "audio/$pid2/"; performanceIds = $songPerformanceIds }
    foreach ($p in $info.PSObject.Properties) { $entry[$p.Name] = $p.Value }
    # optional extras next to the .mscz: <name>.pdf = the original score, <name>.txt = the words
    $origSrc = Join-Path $Songs ($stem + '.pdf')
    $origDst = Join-Path $dir 'original.pdf'
    if (Test-Path -LiteralPath $origSrc) {
        Copy-Item -LiteralPath $origSrc -Destination $origDst -Force
        $entry['original'] = 'original.pdf'
    } elseif (Test-Path -LiteralPath $origDst) { Remove-Item -LiteralPath $origDst }
    # Shared lyrics remain supported as <score filename>.txt or <clean song title>.txt.
    $sharedLyricsCandidates = @(
        (Join-Path $Songs ($stem + '.txt')),
        (Join-Path $Songs ($title + '.txt'))
    )
    foreach ($txtSrc in $sharedLyricsCandidates) {
        if (Test-Path -LiteralPath $txtSrc) {
            $sharedText = ([IO.File]::ReadAllText($txtSrc)).Trim()
            if ($sharedText) { $entry['lyrics'] = $sharedText }
            break
        }
    }

    # Optional part-specific lyrics override the shared lyrics for that singer.
    # Preferred filenames: "<clean song title> - <part name>.txt", for example
    # "Joy to the World - Alto.txt" or "Joy to the World - Soprano 1.txt".
    # Also accept the exact score filename stem for songs that include an ordering prefix.
    $lyricsByVoice = [ordered]@{}
    foreach ($v in @($info.voices)) {
        $partName = [string]$v.name
        $partLyricsCandidates = @(
            (Join-Path $Songs ($title + ' - ' + $partName + '.txt')),
            (Join-Path $Songs ($stem + ' - ' + $partName + '.txt'))
        )
        foreach ($partLyricsSrc in $partLyricsCandidates) {
            if (Test-Path -LiteralPath $partLyricsSrc) {
                $partText = ([IO.File]::ReadAllText($partLyricsSrc)).Trim()
                if ($partText) { $lyricsByVoice[[string]$v.id] = $partText }
                break
            }
        }
    }
    if ($lyricsByVoice.Count -gt 0) { $entry['lyricsByVoice'] = $lyricsByVoice }
    $pieces.Add($entry)
}

foreach ($d in (Get-ChildItem -LiteralPath $audio -Directory)) {
    if (-not $keep.ContainsKey($d.Name)) {
        Write-Host ('Removing ' + $d.Name)
        Remove-Item -LiteralPath $d.FullName -Recurse -Force
    }
}

$out = [ordered]@{ title = $ChoirName; built = [int][double]::Parse((Get-Date -UFormat %s)); performances = @($performances.ToArray()); pieces = $pieces }
[IO.File]::WriteAllText((Join-Path $Site 'pieces.json'), (ConvertTo-Json -InputObject $out -Depth 12 -Compress), $Utf8)
$total = (Get-ChildItem -LiteralPath $audio -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("`nDone: {0} pieces, {1:N0} MB. Upload the 'site' folder." -f $pieces.Count, $total)
