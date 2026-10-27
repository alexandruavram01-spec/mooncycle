# App Store header and search-results image: one 16:9 picture (5244 x 2950,
# PNG, no transparency) that Apple accepts for both places. The logo, the
# MoonCycle wordmark with its crescent C, and the subtitle, on the cream.
#
# Run (PowerShell):
#   powershell -ExecutionPolicy Bypass -File C:\src\mooncycle_app\tool\store_header.ps1
# Writes C:\src\mooncycle-store\appstore-header-5244x2950.png
param(
  [string]$Out = 'C:\src\mooncycle-store\appstore-header-5244x2950.png',
  [string]$LogoPath = 'C:\src\mooncycle_app\assets\brand\logo_mark.png',
  [string]$Subtitle = 'Your cycle, shared your way'
)

Add-Type -AssemblyName System.Drawing

$pageW = 5244
$pageH = 2950
$cream = [System.Drawing.ColorTranslator]::FromHtml('#FAEDE3')
$ink = [System.Drawing.ColorTranslator]::FromHtml('#3A2E3F')
$soft = [System.Drawing.ColorTranslator]::FromHtml('#7A6670')

$bmp = New-Object System.Drawing.Bitmap($pageW, $pageH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.InterpolationMode = 'HighQualityBicubic'
$g.PixelOffsetMode = 'HighQuality'
$g.TextRenderingHint = 'AntiAlias'
$g.Clear($cream)

# Everything sits in the middle, well inside any crop Apple makes.
# (PowerShell names ignore case: the path and the picture need different names.)
$logo = [System.Drawing.Image]::FromFile($LogoPath)
$logoH = 1250
$logoW = [int]($logo.Width * $logoH / $logo.Height)
$g.DrawImage($logo, [int](($pageW - $logoW) / 2), 380, $logoW, $logoH)

# Wordmark: "Moon", a crescent in place of the C, "ycle" (as in the app).
$px = 300
$font = New-Object System.Drawing.Font('Georgia', $px, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$brush = New-Object System.Drawing.SolidBrush($ink)
$w1 = $g.MeasureString('Moon', $font, 10000, $fmt).Width
$w2 = $g.MeasureString('ycle', $font, 10000, $fmt).Width
$cw = $px * 0.5; $padL = $px * 0.04; $padR = $px * 0.02; $r = $px * 0.39
$x = ($pageW - ($w1 + $padL + $cw + $padR + $w2)) / 2
$y = 1760
$g.DrawString('Moon', $font, $brush, [single]$x, [single]$y, $fmt)
$asc = $font.FontFamily.GetCellAscent('Regular') / $font.FontFamily.GetEmHeight('Regular') * $px
$cy = $y + $asc - 0.345 * $px
$cx = $x + $w1 + $padL + $r
$g.FillEllipse($brush, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
$sr = 0.9 * $r; $sx = $cx + 0.42 * $r
$g.FillEllipse((New-Object System.Drawing.SolidBrush($cream)), [single]($sx - $sr), [single]($cy - $sr), [single](2 * $sr), [single](2 * $sr))
$g.DrawString('ycle', $font, $brush, [single]($x + $w1 + $padL + $cw + $padR), [single]$y, $fmt)

# Subtitle under it.
$subFont = New-Object System.Drawing.Font('Georgia', 140, [System.Drawing.FontStyle]::Italic, [System.Drawing.GraphicsUnit]::Pixel)
$center = New-Object System.Drawing.StringFormat
$center.Alignment = 'Center'
$g.DrawString($Subtitle, $subFont, (New-Object System.Drawing.SolidBrush($soft)), (New-Object System.Drawing.RectangleF(0, 2250, $pageW, 260)), $center)

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $logo.Dispose()
Write-Host "Done: $Out"
