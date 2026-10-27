# Store screenshots: each app screenshot on MoonCycle's cream, rounded, with a
# soft shadow and a caption above it, at the exact sizes both stores accept.
#
#   C:\src\mooncycle-store\raw\          the screenshots + captions.txt
#   C:\src\mooncycle-store\play\         1080 x 1920 for Google Play
#   C:\src\mooncycle-store\appstore\     1320 x 2868 for the App Store (6.9")
#
# captions.txt, one line per screenshot, in store order:
#   1.png | Know where you are in your cycle
#
# Run (PowerShell):
#   powershell -ExecutionPolicy Bypass -File C:\src\mooncycle_app\tool\store_screenshots.ps1
# Android screenshots: add -CropTop 110 -CropBottom 140 (pixels) to cut the
# phone's status bar and navigation bar off.
param(
  [string]$Folder = 'C:\src\mooncycle-store',
  [int]$CropTop = 0,
  [int]$CropBottom = 0
)

Add-Type -AssemblyName System.Drawing

$raw = Join-Path $Folder 'raw'
$targets = @(
  @{ Name = 'play'; W = 1080; H = 1920 },
  @{ Name = 'appstore'; W = 1320; H = 2868 }
)
$cream = [System.Drawing.ColorTranslator]::FromHtml('#FAEDE3')
$ink = [System.Drawing.ColorTranslator]::FromHtml('#3A2E3F')

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

$lines = Get-Content -Encoding UTF8 (Join-Path $raw 'captions.txt') | Where-Object { $_ -match '\|' }
foreach ($line in $lines) {
  $parts = $line -split '\|', 2
  $file = $parts[0].Trim()
  $caption = $parts[1].Trim()
  # "1.png" in captions.txt also finds 1.jpg or 1.jpeg.
  $base = [System.IO.Path]::GetFileNameWithoutExtension($file)
  $path = @($file, "$base.png", "$base.jpg", "$base.jpeg") |
    ForEach-Object { Join-Path $raw $_ } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
  if (-not $path) {
    Write-Host "Skipped $file : no picture called $base in $raw"
    continue
  }
  $source = [System.Drawing.Image]::FromFile($path)

  # The app's background colour, from near the top-left of the screenshot.
  $screenBg = ([System.Drawing.Bitmap]$source).GetPixel(8, [Math]::Min($source.Height - 1, $CropTop + 8))

  # Cut the phone's own bars off, if asked.
  $srcRect = New-Object System.Drawing.RectangleF([single]0, [single]$CropTop, [single]$source.Width, [single]($source.Height - $CropTop - $CropBottom))

  foreach ($t in $targets) {
    # PowerShell names are not case-sensitive ($W is $w), so the page and the
    # screenshot get clearly different names.
    $pageW = [single]$t.W
    $pageH = [single]$t.H
    $bmp = New-Object System.Drawing.Bitmap([int]$pageW, [int]$pageH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.TextRenderingHint = 'AntiAlias'
    $g.Clear($cream)

    # Caption in the top 16% (Google asks for captions under 20%).
    $font = New-Object System.Drawing.Font('Georgia', [single]($pageW * 0.056), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'
    $fmt.LineAlignment = 'Center'
    $brush = New-Object System.Drawing.SolidBrush($ink)
    $capRect = New-Object System.Drawing.RectangleF([single]($pageW * 0.05), [single]($pageH * 0.025), [single]($pageW * 0.9), [single]($pageH * 0.135))
    $g.DrawString($caption, $font, $brush, $capRect, $fmt)

    # The screenshot fills the rest, centred.
    $areaTop = [single]($pageH * 0.18)
    $areaH = [single]($pageH * 0.79)
    $areaW = [single]($pageW * 0.86)
    # A little room above the screen's own title, in the app's background
    # colour, so the rounded corner never cuts into it.
    $pad = [single]($areaW * 0.05)
    $scale = [Math]::Min($areaW / $srcRect.Width, ($areaH - $pad) / $srcRect.Height)
    $shotW = [single]($srcRect.Width * $scale)
    $shotH = [single]($srcRect.Height * $scale)
    $cardH = $shotH + $pad
    $shotX = [single](($pageW - $shotW) / 2)
    $shotY = $areaTop
    $corner = [single]($shotW * 0.06)

    # Soft shadow, then the screenshot with rounded corners.
    for ($i = 8; $i -ge 1; $i--) {
      $shadow = New-RoundRect ($shotX - $i) ($shotY + $i * 0.5) ($shotW + 2 * $i) ($cardH + 2 * $i) ($corner + $i)
      $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(9, 58, 46, 63))), $shadow)
    }
    $card = New-RoundRect $shotX $shotY $shotW $cardH $corner
    $g.FillPath((New-Object System.Drawing.SolidBrush($screenBg)), $card)
    $g.SetClip($card)
    $g.DrawImage($source, (New-Object System.Drawing.RectangleF($shotX, ($shotY + $pad), $shotW, $shotH)), $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.ResetClip()

    $outDir = Join-Path $Folder $t.Name
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $out = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($file) + '.png')
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
  }
  $source.Dispose()
  Write-Host "Made $file"
}
Write-Host "Done: $Folder\play and $Folder\appstore"
