# LinkedIn Read-All installer / updater for Windows (Chrome, Edge, Brave, Chromium).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/woojinjeon820-ui/linkedin-read-all/main/install.ps1 | iex"
#
# Works from PowerShell, cmd, Git Bash, or an AI agent's shell. It:
#   1. downloads the latest release to %USERPROFILE%\LinkedIn-Read-All (replacing an older copy),
#   2. opens your browser's Extensions page,
#   3. does the clicks for you through Windows UI Automation: turns on Developer mode, clicks
#      "Load unpacked" and fills in the folder picker. If the extension is already loaded from
#      that folder, it presses the extension's Reload button instead.
# If a click can't be automated (non-English browser, a policy blocks Developer mode, ...), it
# says which step is left and puts the folder path on your clipboard.
#
# Re-run it any time to update. The last line of output is LNRA_RESULT=<value>:
#   loaded          freshly loaded into the browser
#   reloaded        it was already loaded from the install folder; files updated and reloaded
#   other-copy      a "LinkedIn Read-All" from a different folder is already loaded; nothing loaded
#   manual          files are installed, but the browser step has to be done by hand (see output)
#   failed          something went wrong (see output)
#
# Options (environment variables):
#   LNRA_DIR=C:\path       install somewhere else (default: %USERPROFILE%\LinkedIn-Read-All)
#   LNRA_BROWSER=name      chrome | edge | brave | chromium (default: the open one, else Chrome, Brave, Edge)
#   LNRA_NO_AUTOMATE=1     don't click anything; print the manual steps
#   LNRA_NO_OPEN=1         don't open the browser (implies LNRA_NO_AUTOMATE)
#   LNRA_NO_CLIPBOARD=1    don't touch the clipboard
#   LNRA_USER_DATA_DIR=    start the browser with this --user-data-dir (for testing)

& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repo = 'woojinjeon820-ui/linkedin-read-all'
$Name = 'LinkedIn Read-All'
if ($env:LNRA_DIR) { $Dest = $env:LNRA_DIR } else { $Dest = Join-Path $env:USERPROFILE 'LinkedIn-Read-All' }
$Dest = [IO.Path]::GetFullPath($Dest).TrimEnd('\')
$St = @{ Version = ''; Action = '' }   # shared state (keeps iex runs from leaking globals)

function Say([string]$msg) { Write-Host $msg }
function Finish([string]$result) { Write-Host ''; Write-Host "LNRA_RESULT=$result" }

function Test-OurManifest([string]$dir) {
  $m = Join-Path $dir 'manifest.json'
  if (-not (Test-Path -LiteralPath $m)) { return $false }
  try { return ((Get-Content -LiteralPath $m -Raw | ConvertFrom-Json).name -eq $Name) } catch { return $false }
}

# --- 1. Download the latest release ----------------------------------------------------------
function Install-Files {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
  Say "Finding the latest release of $Name..."
  $api = "https://api.github.com/repos/$Repo/releases/latest"
  $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'linkedin-read-all-installer' }
  $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' })[0]
  if (-not $asset) { throw "no .zip found in the latest release of $Repo." }
  $St.Version = ($rel.tag_name -replace '^v', '')

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lnra-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'ext.zip'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'ext')
    if (-not (Test-OurManifest (Join-Path $tmp 'ext'))) { throw "the download doesn't look like $Name." }

    if (Test-Path -LiteralPath $Dest) {
      if (-not (Test-OurManifest $Dest)) { throw "$Dest already exists and isn't $Name. Move it, or set LNRA_DIR to another folder." }
      $St.Action = 'Updated'
    } else {
      $St.Action = 'Installed'
    }
    $parent = Split-Path -Parent $Dest
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    # Swap in the new copy. The folder path stays the same, so the extension keeps its ID and data.
    $old = "$Dest.old"
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
    if (Test-Path -LiteralPath $Dest) { Rename-Item -LiteralPath $Dest -NewName (Split-Path -Leaf $old) }
    Move-Item -LiteralPath (Join-Path $tmp 'ext') -Destination $Dest
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
  Say "$($St.Action) $Name v$($St.Version) in: $Dest"
}

# --- 2. Pick the browser ---------------------------------------------------------------------
function Get-AppPath([string]$exe) {
  foreach ($hive in 'HKCU:', 'HKLM:') {
    try {
      $p = (Get-ItemProperty -LiteralPath "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction Stop).'(default)'
      if ($p) { return $p.Trim('"') }
    } catch {}
  }
}
$Browsers = [ordered]@{
  chrome   = @{ Label = 'Google Chrome';  Proc = 'chrome'; Frag = '\Google\Chrome\';  Page = 'chrome://extensions/'
                Paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe", (Get-AppPath 'chrome.exe'))
                Data  = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
  edge     = @{ Label = 'Microsoft Edge'; Proc = 'msedge'; Frag = '\Microsoft\Edge\'; Page = 'edge://extensions/'
                Paths = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", (Get-AppPath 'msedge.exe'))
                Data  = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
  brave    = @{ Label = 'Brave';          Proc = 'brave';  Frag = '\BraveSoftware\';  Page = 'brave://extensions/'
                Paths = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe", (Get-AppPath 'brave.exe'))
                Data  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }
  chromium = @{ Label = 'Chromium';       Proc = 'chrome'; Frag = '\Chromium\';       Page = 'chrome://extensions/'
                Paths = @("$env:LOCALAPPDATA\Chromium\Application\chrome.exe")
                Data  = "$env:LOCALAPPDATA\Chromium\User Data" }
}

function Get-BrowserProcs($b) {
  @(Get-Process -Name $b.Proc -ErrorAction SilentlyContinue | Where-Object { (-not $_.Path) -or ($_.Path -like "*$($b.Frag)*") })
}
function Get-BrowserExe($b) {
  $running = @(Get-BrowserProcs $b | Where-Object { $_.Path })[0]
  if ($running) { return $running.Path }
  foreach ($p in $b.Paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
}
function Test-BrowserOpen($b) { [bool](@(Get-BrowserProcs $b | Where-Object { $_.MainWindowHandle -ne 0 }).Count) }

function Select-Browser {
  if ($env:LNRA_BROWSER) {
    $k = $env:LNRA_BROWSER.ToLower()
    if (-not $Browsers.Contains($k)) { throw "LNRA_BROWSER must be one of: $($Browsers.Keys -join ', ')." }
    return $k
  }
  # Prefer a browser with an open window (Edge often runs in the background without one).
  foreach ($k in 'chrome', 'brave', 'edge', 'chromium') { if ((Get-BrowserExe $Browsers[$k]) -and (Test-BrowserOpen $Browsers[$k])) { return $k } }
  foreach ($k in 'chrome', 'brave', 'edge', 'chromium') { if (Get-BrowserExe $Browsers[$k]) { return $k } }
}

# Read-only look at the browser's profile files: folders this extension is loaded unpacked from.
# Returns $null if no profile could be read.
function Get-LoadedCopies($b) {
  $data = $b.Data
  if ($env:LNRA_USER_DATA_DIR) { $data = $env:LNRA_USER_DATA_DIR }
  if (-not $data -or -not (Test-Path -LiteralPath $data)) { return $null }
  $re = New-Object Text.RegularExpressions.Regex('"path":\s*"((?:[^"\\]|\\.)*)"')
  $readAny = $false
  $dirs = @()
  foreach ($prof in Get-ChildItem -LiteralPath $data -Directory -ErrorAction SilentlyContinue) {
    foreach ($f in 'Secure Preferences', 'Preferences') {
      $file = Join-Path $prof.FullName $f
      if (-not (Test-Path -LiteralPath $file)) { continue }
      try { $text = [IO.File]::ReadAllText($file); $readAny = $true } catch { continue }
      foreach ($m in $re.Matches($text)) {
        $dir = $m.Groups[1].Value -replace '\\\\', '\'
        if ([IO.Path]::IsPathRooted($dir) -and (Test-OurManifest $dir)) { $dirs += $dir.TrimEnd('\') }
      }
    }
  }
  if (-not $readAny) { return $null }
  return ,@($dirs | Sort-Object -Unique)
}

# $true / $false, or $null if no profile could be read.
function Test-LoadedFromDest($b) {
  $copies = Get-LoadedCopies $b
  if ($null -eq $copies) { return $null }
  return [bool](@($copies | Where-Object { $_ -eq $Dest }).Count)
}

function Test-InGitRepo([string]$dir) {
  $d = $dir
  while ($d) {
    if (Test-Path -LiteralPath (Join-Path $d '.git')) { return $true }
    $d = Split-Path -Parent $d
  }
  return $false
}

# --- 3. UI Automation ------------------------------------------------------------------------
function Wait-For([scriptblock]$probe, [int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  do {
    $r = $null
    try { $r = & $probe } catch {}
    if ($r) { return $r }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Test-Alive($el) { try { [void]$el.Current.Name; return $true } catch { return $false } }

function Get-Pattern($el, $pattern) {
  [object]$p = $null
  if ($el.TryGetCurrentPattern($pattern, [ref]$p)) { return $p }
  return $null
}

function Find-Named($el, [string]$text, $type) {
  $c = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, $text)
  if ($type) {
    $c = New-Object System.Windows.Automation.AndCondition($c, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $type)))
  }
  $found = $el.FindAll($Scope::Descendants, $c)
  $out = @(); foreach ($x in $found) { $out += $x }
  return ,$out
}

function Get-TopWindows($b) {
  $ids = @(Get-BrowserProcs $b | ForEach-Object { $_.Id })
  $out = @()
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($ids -contains $w.Current.ProcessId) { $out += $w } } catch {}
  }
  return ,$out
}

function Get-ExtWindow($b) {
  foreach ($w in (Get-TopWindows $b)) {
    $n = ''; try { $n = $w.Current.Name } catch {}
    if ($n -like 'Extensions*') { return $w }
  }
}

function Set-Foreground($window) {
  $h = [IntPtr]$window.Current.NativeWindowHandle
  if ([LNRA.Native]::GetForegroundWindow() -eq $h) { return $true }
  try { $window.SetFocus() } catch {}
  [void][LNRA.Native]::ShowWindow($h, 9)  # SW_RESTORE, in case it's minimized
  # Windows only lets the foreground app hand over focus; a tap of Alt counts as input from us.
  [LNRA.Native]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [LNRA.Native]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  [void][LNRA.Native]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 300
  return ([LNRA.Native]::GetForegroundWindow() -eq $h)
}

# Chrome ignores chrome:// addresses passed on its command line, so type it in the address bar.
# Reuses an empty New Tab (the one Chrome just opened for us), otherwise opens a new tab, so the
# tab you were looking at is left alone.
function Open-ExtPageByTyping($b) {
  $win = @(Get-TopWindows $b | Where-Object { $_.Current.ClassName -like 'Chrome_WidgetWin*' -and $_.Current.Name })[0]
  if (-not $win) { return $false }
  if (-not (Set-Foreground $win)) { return $false }
  if ($win.Current.Name -like 'New Tab*') { $keys = '^l' } else { $keys = '^t' }
  [System.Windows.Forms.SendKeys]::SendWait($keys)
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait($b.Page)
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  return $true
}

function Invoke-Click($el, $window) {
  $inv = Get-Pattern $el ([System.Windows.Automation.InvokePattern]::Pattern)
  if ($inv) { $inv.Invoke(); return }
  $tog = Get-Pattern $el ([System.Windows.Automation.TogglePattern]::Pattern)
  if ($tog) { $tog.Toggle(); return }
  # Last resort: a real mouse click on the element.
  if ($window) { try { [void][LNRA.Native]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle) } catch {} }
  Start-Sleep -Milliseconds 300
  $pt = $el.GetClickablePoint()
  [void][LNRA.Native]::SetCursorPos([int]$pt.X, [int]$pt.Y)
  [LNRA.Native]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [LNRA.Native]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

# The web page itself, so we never match the browser's own toolbar (its Reload button, a pinned
# extension button, ...).
function Get-PageDoc($win) {
  $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Document)
  foreach ($d in $win.FindAll($Scope::Descendants, $cond)) {
    try { if (@(Find-Named $d 'Developer mode').Count) { return $d } } catch {}
  }
}

function Get-LoadButton($win) {
  @(Find-Named $win 'Load unpacked' $CT::Button | Where-Object { -not $_.Current.IsOffscreen })[0]
}

function Enable-DevMode($page, $win) {
  $toggle = Wait-For {
    @(Find-Named $page 'Developer mode' | Where-Object { $_.Current.ControlType -ne $CT::Text })[0]
  } 10
  if (-not $toggle) { return 'no-toggle' }
  if (Get-LoadButton $page) { return 'on' }
  $tog = Get-Pattern $toggle ([System.Windows.Automation.TogglePattern]::Pattern)
  if ($tog -and $tog.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
    if (Wait-For { Get-LoadButton $page } 3) { return 'on' }
  }
  if (-not $toggle.Current.IsEnabled) { return 'blocked' }
  Say 'Turning on Developer mode...'
  Invoke-Click $toggle $win
  if (Wait-For { Get-LoadButton $page } 8) { return 'on' }
  return 'failed'
}

function Get-FolderDialog($b) {
  $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, '#32770')
  foreach ($w in (Get-TopWindows $b)) {
    try { if ($w.Current.ClassName -eq '#32770') { return $w } } catch {}
    $d = $w.FindFirst($Scope::Children, $cond)
    if ($d) { return $d }
  }
}

function Complete-FolderDialog($dlg, $win) {
  $editCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Edit)
  $edits = @(); foreach ($e in $dlg.FindAll($Scope::Descendants, $editCond)) { $edits += $e }
  $edit = @($edits | Where-Object { @('1148', '1152') -contains $_.Current.AutomationId -or $_.Current.Name -match '^(Folder|File name)' })[0]
  # Without the folder box we'd confirm whatever folder the dialog happens to show, so stop.
  if (-not $edit) { return $false }
  $okCond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, '1')
  for ($i = 0; $i -lt 3 -and (Test-Alive $dlg); $i++) {
    if ($i -eq 0) {
      $val = Get-Pattern $edit ([System.Windows.Automation.ValuePattern]::Pattern)
      if ($val) {
        $val.SetValue($Dest)
      } else {
        $edit.SetFocus()
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait(($Dest -replace '([+^%~(){}\[\]])', '{$1}'))
      }
    }
    $ok = $dlg.FindFirst($Scope::Descendants, $okCond)
    if ($ok) { Invoke-Click $ok $dlg } else { $edit.SetFocus(); [System.Windows.Forms.SendKeys]::SendWait('{ENTER}') }
    # If Windows only navigated into the folder, the next press selects it.
    [void](Wait-For { -not (Test-Alive $dlg) } 3)
  }
  return -not (Test-Alive $dlg)
}

# Press the Reload button on our extension's card (the closest ancestor with exactly one Reload).
function Invoke-CardReload($page, $win) {
  $label = @(Find-Named $page $Name)[0]
  if (-not $label) { return $false }
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $node = $label
  for ($i = 0; $i -lt 8 -and $node; $i++) {
    $node = $walker.GetParent($node)
    if (-not $node -or $node -eq $page) { break }
    $reloads = Find-Named $node 'Reload' $CT::Button
    if ($reloads.Count -gt 1) { return $false }
    if ($reloads.Count -eq 1) { Invoke-Click $reloads[0] $win; return $true }
  }
  return $false
}

# Does the whole browser step. Returns: loaded | reloaded | other-copy | a reason it stopped.
function Invoke-BrowserStep($b) {
  try {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
  } catch {
    Say "(Windows UI Automation isn't available here: $($_.Exception.Message))"
    return 'no-uia'
  }
  try {
    Add-Type -Namespace LNRA -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
'@
  } catch {}  # already defined by an earlier run in this session
  # Seen by the helper functions through PowerShell's dynamic scoping.
  $AE = [System.Windows.Automation.AutomationElement]
  $Scope = [System.Windows.Automation.TreeScope]
  $CT = [System.Windows.Automation.ControlType]

  Say "Doing the browser clicks for you. Please don't use the mouse or keyboard for a few seconds..."
  $win = Wait-For { Get-ExtWindow $b } 6
  if (-not $win) {
    # Give the browser a moment to finish starting, then type the address in.
    [void](Wait-For { @(Get-TopWindows $b | Where-Object { $_.Current.Name }).Count } 20)
    Start-Sleep -Seconds 1
    Say "Opening $($b.Page)..."
    if (Open-ExtPageByTyping $b) { $win = Wait-For { Get-ExtWindow $b } 10 }
  }
  if (-not $win) {
    Say "Waiting for the Extensions page. If it isn't open, type $($b.Page) into $($b.Label)'s address bar."
    $win = Wait-For { Get-ExtWindow $b } 90
  }
  if (-not $win) { return 'no-window' }
  $page = Wait-For { Get-PageDoc $win } 20
  if (-not $page) { return 'no-page' }
  Say 'Found the Extensions page.'

  $dev = Enable-DevMode $page $win
  if ($dev -eq 'blocked') { return 'devmode-blocked' }
  if ($dev -ne 'on') { return "devmode-$dev" }
  Start-Sleep -Milliseconds 800  # let the extension list render

  if (@(Find-Named $page $Name).Count) {
    $ours = Test-LoadedFromDest $b
    if ($ours -eq $false) { return 'other-copy' }
    if (Invoke-CardReload $page $win) { Start-Sleep -Seconds 1; return 'reloaded' }
    return 'reload-failed'
  }

  $btn = Get-LoadButton $page
  if (-not $btn) { return 'no-load-button' }
  Say 'Clicking Load unpacked...'
  Invoke-Click $btn $win
  $dlg = Wait-For { Get-FolderDialog $b } 10
  if (-not $dlg) { return 'no-dialog' }
  Say "Choosing $Dest in the folder picker..."
  if (-not (Complete-FolderDialog $dlg $win)) { return 'dialog-stuck' }
  if (Wait-For { @(Find-Named $page $Name).Count } 15) { return 'loaded' }
  if (Wait-For { Test-LoadedFromDest $b } 10) { return 'loaded' }
  return 'not-listed'
}

# --- Main ------------------------------------------------------------------------------------
try {
  $key = Select-Browser
  $b = $null; if ($key) { $b = $Browsers[$key] }

  # Already loaded by hand from another folder (say, an unzipped download)? Update that copy in
  # place so the browser keeps the same extension, with its read / unread state. Never a git
  # checkout, though: that's someone developing the extension.
  if ($b -and -not $env:LNRA_DIR) {
    $copies = Get-LoadedCopies $b
    if ($copies -and -not ($copies -contains $Dest)) {
      $adopt = @($copies | Where-Object { -not (Test-InGitRepo $_) })[0]
      if ($adopt) {
        Say "$Name is already loaded in $($b.Label) from $adopt. Updating that copy."
        $Dest = $adopt
      }
    }
  }

  Install-Files
} catch {
  Say "Error: $($_.Exception.Message)"
  Finish 'failed'
  return
}

$copied = $false
if (-not $env:LNRA_NO_CLIPBOARD) { try { Set-Clipboard -Value $Dest; $copied = $true } catch {} }

$opened = $false
if ($b -and -not $env:LNRA_NO_OPEN) {
  $exe = Get-BrowserExe $b
  $argv = @()
  if ($env:LNRA_USER_DATA_DIR) { $argv += "--user-data-dir=`"$($env:LNRA_USER_DATA_DIR)`"", '--no-first-run', '--no-default-browser-check' }
  $argv += $b.Page
  try { Start-Process -FilePath $exe -ArgumentList $argv; $opened = $true; Say "Opened $($b.Page) in $($b.Label)." } catch { Say "Couldn't start $($b.Label): $($_.Exception.Message)" }
}

$outcome = 'skipped'
if ($opened -and -not $env:LNRA_NO_AUTOMATE) {
  try { $outcome = Invoke-BrowserStep $b } catch { $outcome = "error: $($_.Exception.Message)" }
}

switch ($outcome) {
  'loaded' {
    Say "Loaded $Name into $($b.Label)."
    Say 'Open https://www.linkedin.com/notifications/ - a dark bar with "Mark all as read" appears at the bottom.'
    Finish 'loaded'; return
  }
  'reloaded' {
    Say "$Name was already loaded from $Dest. Updated it to v$($St.Version) and reloaded it."
    Say 'Refresh any open LinkedIn tabs to pick up the new version.'
    Finish 'reloaded'; return
  }
  'other-copy' {
    Say "$($b.Label) already has a copy of $Name loaded from a different folder (a git checkout, or one this"
    Say "installer can't update). Two copies conflict, so nothing was loaded. To use this install instead, remove"
    Say "the old one on $($b.Page) (its card's Remove button), then run this installer again."
    Finish 'other-copy'; return
  }
}

# Anything else: the files are in place, the browser step is left.
if ($outcome -ne 'skipped') {
  $why = @{
    'no-uia'          = "Windows UI Automation isn't available in this shell."
    'no-window'       = "couldn't find the browser's Extensions page."
    'no-page'         = "couldn't read the Extensions page (its accessibility tree didn't load)."
    'devmode-blocked' = 'Developer mode is turned off by a policy (school or work managed browser). Ask your admin, or use another browser.'
    'no-load-button'  = "couldn't find the Load unpacked button."
    'no-dialog'       = "the folder picker didn't open."
    'dialog-stuck'    = "couldn't fill in the folder picker."
    'reload-failed'   = "couldn't press the extension's Reload button."
    'not-listed'      = "the extension didn't show up after loading (the page may show an error)."
  }[$outcome]
  if (-not $why) {
    if ($outcome -like 'devmode-*') { $why = "couldn't turn on Developer mode (an English browser UI is needed for the automatic clicks)." }
    else { $why = $outcome }
  }
  Say ''
  Say "Couldn't finish automatically: $why"
}
if ($b) { $where = "$($b.Page) in $($b.Label)" } else { $where = 'chrome://extensions (edge://extensions in Edge) in your browser' }
if ($copied) { $pathHint = "$Dest (it's on your clipboard, so Ctrl+V)" } else { $pathHint = $Dest }
Say ''
if ($outcome -eq 'reload-failed' -or ($St.Action -eq 'Updated' -and $outcome -eq 'skipped')) {
  Say "If $Name is already loaded: on $where, press the reload icon on its card. Done."
  Say 'First time loading it? Follow the steps below.'
}
Say "To finish, on ${where}:"
Say '  1. Turn on Developer mode'
Say "  2. Click Load unpacked, then choose the folder $pathHint and click Select Folder"
Say '  3. Open https://www.linkedin.com/notifications/ (the bar appears at the bottom)'
Finish 'manual'
}
