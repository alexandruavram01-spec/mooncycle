<#
.SYNOPSIS
Turns the chosen icon artwork into MoonCycle's app icons, with a preview.

.DESCRIPTION
The artwork (assets\icon\source\icon_art.webp, or icon_art.png if present)
is drawn as an icon on a purple background, with its own rounded corners.
Phones add their own corners, so this script:

- iPhone, Play and web (icon.png): crops just inside the drawn frame, to a
  full square. iOS rounds the corners itself.
- Android shaped icons (icon_background.png + an empty icon_foreground.png):
  the same square, sized so the whole crescent fits in what Android shows
  (about the middle two thirds of the layer), on the artwork's own purple.
- Play Console's store icon: play_icon_512.png.

Without -Apply: writes everything and preview.png to -OutDir. The preview
shows the current icon and the new one at home-screen size, as an iPhone
icon and Android round and rounded-square icons, on light and dark
wallpapers.

With -Apply: copies the new icons into assets\icon (the old ones stay in
assets\icon\original). Then run:  dart run flutter_launcher_icons

-Inset trims each side of the artwork by that share of its width, to cut off
the drawn frame. Raise it if a frame line still shows, lower it if the
crescent is cut.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tool\app_icon.ps1
powershell -ExecutionPolicy Bypass -File tool\app_icon.ps1 -Inset 0.09
powershell -ExecutionPolicy Bypass -File tool\app_icon.ps1 -Apply
#>
param(
  [switch]$Apply,
  [double]$Inset = 0.078,
  [double]$AndroidShare = 0.69,
  [string]$OutDir = 'C:\src\mooncycle-store\icon-preview'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore, WindowsBase

$repo = Split-Path -Parent $PSScriptRoot
$iconDir = Join-Path $repo 'assets\icon'
$origDir = Join-Path $iconDir 'original'
$sourceDir = Join-Path $iconDir 'source'

if (-not (Test-Path $origDir)) {
  New-Item -ItemType Directory -Path $origDir | Out-Null
  Copy-Item (Join-Path $iconDir 'icon.png') (Join-Path $origDir 'icon.png')
  Copy-Item (Join-Path $iconDir 'icon_foreground.png') (Join-Path $origDir 'icon_foreground.png')
}

if ($Apply) {
  foreach ($name in @('icon.png', 'icon_background.png', 'icon_foreground.png')) {
    $from = Join-Path $OutDir "new_$name"
    if (-not (Test-Path $from)) { throw 'Run the script once without -Apply first.' }
    Copy-Item $from (Join-Path $iconDir $name) -Force
  }
  Write-Host 'New icon copied into assets\icon. The old one is in assets\icon\original.'
  Write-Host 'Next:  dart run flutter_launcher_icons'
  return
}

function New-Canvas([int]$width, [int]$height) {
  New-Object System.Drawing.Bitmap $width, $height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Get-Colour([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

function Start-Drawing([System.Drawing.Bitmap]$bmp) {
  $gfx = [System.Drawing.Graphics]::FromImage($bmp)
  $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $gfx
}

function Save-Png($bmp, [string]$path) {
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# Reads PNG, JPEG or WebP. WebP goes through Windows' own image codecs.
function Read-Picture([string]$path) {
  $stream = [System.IO.File]::OpenRead($path)
  try {
    $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create($stream,
      [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
      [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($decoder.Frames[0]))
    $memory = New-Object System.IO.MemoryStream
    $encoder.Save($memory)
    $memory.Position = 0
    $loaded = [System.Drawing.Bitmap]::FromStream($memory)
    $copy = New-Object System.Drawing.Bitmap $loaded
    $loaded.Dispose(); $memory.Dispose()
    return $copy
  } catch {
    throw "Windows could not read $path. Save the picture as PNG named icon_art.png in assets\icon\source and run again."
  } finally {
    $stream.Dispose()
  }
}

$sourcePath = Join-Path $sourceDir 'icon_art.png'
if (-not (Test-Path $sourcePath)) { $sourcePath = Join-Path $sourceDir 'icon_art.webp' }
$art = Read-Picture $sourcePath
Write-Host "Artwork: $sourcePath ($($art.Width) x $($art.Height))"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$size = 1024

# The square inside the drawn frame.
$cut = [int]($art.Width * $Inset)
$square = New-Object System.Drawing.Rectangle $cut, $cut, ($art.Width - 2 * $cut), ($art.Height - 2 * $cut)

# 1. iPhone, Play and web: the square, full size, no transparency.
$icon = New-Canvas $size $size
$gfx = Start-Drawing $icon
$gfx.DrawImage($art, (New-Object System.Drawing.Rectangle 0, 0, $size, $size),
  $square.X, $square.Y, $square.Width, $square.Height, [System.Drawing.GraphicsUnit]::Pixel)
$gfx.Dispose()
$icon.Save((Join-Path $OutDir 'new_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# Play Console's store icon.
$play = New-Canvas 512 512
$gfx = Start-Drawing $play
$gfx.DrawImage($icon, 0, 0, 512, 512)
$gfx.Dispose()
Save-Png $play (Join-Path $OutDir 'play_icon_512.png')

# 2. Android shaped icon. Background layer: the artwork's own purple (from
# the top and bottom edges of the picture), with the square in the middle.
$topColour = $art.GetPixel([int]($art.Width / 2), 12)
$bottomColour = $art.GetPixel([int]($art.Width / 2), $art.Height - 12)
$back = New-Canvas $size $size
$gfx = Start-Drawing $back
$area = New-Object System.Drawing.Rectangle 0, 0, $size, $size
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $area, $topColour, $bottomColour, 90.0
$gfx.FillRectangle($brush, $area)
$brush.Dispose()
$side = [int]($size * $AndroidShare)
$at = [int](($size - $side) / 2)
$gfx.DrawImage($art, (New-Object System.Drawing.Rectangle $at, $at, $side, $side),
  $square.X, $square.Y, $square.Width, $square.Height, [System.Drawing.GraphicsUnit]::Pixel)
$gfx.Dispose()
$back.Save((Join-Path $OutDir 'new_icon_background.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# Foreground layer: empty, since everything is in the background.
$fore = New-Canvas $size $size
$gfx = Start-Drawing $fore
$gfx.Clear([System.Drawing.Color]::Transparent)
$gfx.Dispose()
Save-Png $fore (Join-Path $OutDir 'new_icon_foreground.png')

# ---- Preview -------------------------------------------------------------------
# What Android shows: the middle 72/108 of the 108 dp layers, in a mask.
function New-AndroidIcon($backImg, $foreImg, [bool]$circle) {
  $shown = New-Canvas 512 512
  $g2 = Start-Drawing $shown
  $g2.Clear([System.Drawing.Color]::Transparent)
  $mask = New-Object System.Drawing.Drawing2D.GraphicsPath
  if ($circle) { $mask.AddEllipse(0, 0, 512, 512) }
  else {
    [single]$d = 512 * 0.6
    [single]$far = 512 - $d
    $mask.AddArc([single]0, [single]0, $d, $d, [single]180, [single]90)
    $mask.AddArc($far, [single]0, $d, $d, [single]270, [single]90)
    $mask.AddArc($far, $far, $d, $d, [single]0, [single]90)
    $mask.AddArc([single]0, $far, $d, $d, [single]90, [single]90)
    $mask.CloseFigure()
  }
  $g2.SetClip($mask)
  $whole = New-Object System.Drawing.Rectangle 0, 0, 512, 512
  foreach ($layer in @($backImg, $foreImg)) {
    $edge = [int]($layer.Width * 18 / 108)
    $g2.DrawImage($layer, $whole, $edge, $edge, ($layer.Width - 2 * $edge), ($layer.Height - 2 * $edge),
      [System.Drawing.GraphicsUnit]::Pixel)
  }
  $g2.Dispose(); $mask.Dispose()
  $shown
}

$currentBack = New-Canvas $size $size
$gfx = Start-Drawing $currentBack
$gfx.Clear((Get-Colour '#FAEDE3'))
$gfx.Dispose()

$oldIcon = [System.Drawing.Image]::FromFile((Join-Path $origDir 'icon.png'))
$oldFore = [System.Drawing.Image]::FromFile((Join-Path $origDir 'icon_foreground.png'))
$newFore = [System.Drawing.Image]::FromFile((Join-Path $OutDir 'new_icon_foreground.png'))
$rows = @(
  @{ Label = 'Current'; Icon = $oldIcon; Round = (New-AndroidIcon $currentBack $oldFore $true); Squircle = (New-AndroidIcon $currentBack $oldFore $false) },
  @{ Label = 'New'; Icon = $icon; Round = (New-AndroidIcon $back $newFore $true); Squircle = (New-AndroidIcon $back $newFore $false) }
)

$rowH = 230; $labelW = 150; $tileW = 600
$sheet = New-Canvas ($labelW + 2 * $tileW) ($rowH * $rows.Count + 50)
$gfx = Start-Drawing $sheet
$gfx.Clear((Get-Colour '#FFFFFF'))
$font = New-Object System.Drawing.Font 'Segoe UI', 15, ([System.Drawing.FontStyle]::Bold)
$small = New-Object System.Drawing.Font 'Segoe UI', 11
$ink = New-Object System.Drawing.SolidBrush (Get-Colour '#3B2A33')
$gfx.DrawString('Light wallpaper:  iPhone, iPhone small, Android round, Android rounded', $small, $ink, [single]($labelW + 16), [single]14)
$gfx.DrawString('Dark wallpaper', $small, $ink, [single]($labelW + $tileW + 16), [single]14)
$walls = @('#E7E2EE', '#1F2230')

for ($r = 0; $r -lt $rows.Count; $r++) {
  $row = $rows[$r]
  $top = 50 + $r * $rowH
  $gfx.DrawString($row.Label, $font, $ink, [single]16, [single]($top + $rowH / 2 - 14))
  for ($w = 0; $w -lt 2; $w++) {
    $left = $labelW + $w * $tileW
    $wall = New-Object System.Drawing.SolidBrush (Get-Colour $walls[$w])
    $gfx.FillRectangle($wall, [single]($left + 8), [single]($top + 6), [single]($tileW - 16), [single]($rowH - 12))
    $wall.Dispose()
    $x = $left + 26
    foreach ($px in @(150, 90)) {
      $y = $top + ($rowH - $px) / 2
      $path = New-Object System.Drawing.Drawing2D.GraphicsPath
      $radius = $px * 0.225
      $path.AddArc([single]$x, [single]$y, [single]($radius * 2), [single]($radius * 2), 180, 90)
      $path.AddArc([single]($x + $px - 2 * $radius), [single]$y, [single]($radius * 2), [single]($radius * 2), 270, 90)
      $path.AddArc([single]($x + $px - 2 * $radius), [single]($y + $px - 2 * $radius), [single]($radius * 2), [single]($radius * 2), 0, 90)
      $path.AddArc([single]$x, [single]($y + $px - 2 * $radius), [single]($radius * 2), [single]($radius * 2), 90, 90)
      $path.CloseFigure()
      $gfx.SetClip($path)
      $gfx.DrawImage($row.Icon, [single]$x, [single]$y, [single]$px, [single]$px)
      $gfx.ResetClip()
      $path.Dispose()
      $x += $px + 26
    }
    foreach ($shape in @($row.Round, $row.Squircle)) {
      $px = 130
      $gfx.DrawImage($shape, [single]$x, [single]($top + ($rowH - $px) / 2), [single]$px, [single]$px)
      $x += $px + 26
    }
  }
}
$gfx.Dispose()
$previewPath = Join-Path $OutDir 'preview_new.png'
Save-Png $sheet $previewPath
Write-Host "Preview: $previewPath"
Write-Host 'If it looks right:  powershell -ExecutionPolicy Bypass -File tool\app_icon.ps1 -Apply'
