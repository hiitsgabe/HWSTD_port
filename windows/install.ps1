# Copies Hot Wheels Stunt Track Driver from your own CD image (.iso) into .\game
# and adds cnc-ddraw, which runs the game's 8-bit DirectDraw on modern Windows.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dst = Join-Path $here 'game'

$iso = Get-ChildItem -Path $here -Filter *.iso | Select-Object -First 1
if ($iso) {
  $isoPath = $iso.FullName
} else {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    Filter = 'CD image (*.iso)|*.iso'
    Title  = 'Select your Hot Wheels Stunt Track Driver CD image'
  }
  if ($dlg.ShowDialog() -ne 'OK') { Write-Host 'Cancelled.'; exit 1 }
  $isoPath = $dlg.FileName
}

Write-Host "Copying the game from $isoPath ..."
$img = Mount-DiskImage -ImagePath $isoPath -PassThru
try {
  $drive = ($img | Get-Volume).DriveLetter
  $src = "${drive}:\setup\hot98"
  if (-not (Test-Path "$src\stunt.exe")) { throw "setup\hot98\stunt.exe not found in $isoPath" }
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force
} finally {
  Dismount-DiskImage -ImagePath $isoPath | Out-Null
}

# Files copied off a CD stay read-only; the game writes its saves next to the exe.
Get-ChildItem -Path $dst -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
Copy-Item -Path (Join-Path $here 'cnc-ddraw\ddraw.dll'), (Join-Path $here 'cnc-ddraw\ddraw.ini') -Destination $dst -Force

Write-Host 'Done. Start the game with Play.cmd.'
