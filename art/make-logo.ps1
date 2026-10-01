param(
    [string]$TgaPath = "",  # the in-game minimap icon (JourneyTracker\JT.tga)
    [string]$PngPath = "",  # a large square logo, e.g. for CurseForge
    [int]$PngSize = 1024,
    [switch]$NoRing         # large logo without the gold ring (bigger letters)
)
# Draws the Journey Tracker logo: "JT" in custom letterforms styled after the
# World of Warcraft logo (heavy strokes, pointed flared serifs, pale gold to
# orange gradient, thick dark outline).
#
#   powershell -ExecutionPolicy Bypass -File art\make-logo.ps1 -TgaPath JourneyTracker\JT.tga
#       The 64x64 in-game icon: drawn at 128px, then downsampled.
#   powershell -ExecutionPolicy Bypass -File art\make-logo.ps1 -PngPath art\curseforge-logo.png
#       The large logo: the letters in a gold ring, like the minimap button,
#       on a dark background. CurseForge wants a square PNG of at least
#       400x400.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"
if (-not $TgaPath -and -not $PngPath) {
    Write-Host "Usage: make-logo.ps1 [-TgaPath <icon.tga>] [-PngPath <logo.png> [-PngSize 1024] [-NoRing]]"
    exit 1
}

function P([double]$x, [double]$y) { return [System.Drawing.PointF]::new($x, $y) }
function C([int]$a, [int]$r, [int]$g, [int]$b) { return [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

# The two letters as one path, in their own units (about 130 wide, 109 tall).
function New-Letters {
    # J: top bar with a flared left serif, stem on the right, hooked foot
    # ending in a pointed terminal.
    $J = New-Object System.Drawing.Drawing2D.GraphicsPath
    $J.StartFigure()
    $J.AddLine((P 6 12), (P 62 12))
    $J.AddLine((P 62 12), (P 58 36))
    $J.AddLine((P 58 36), (P 58 84))
    $J.AddBezier((P 58 84), (P 58 106), (P 47 118), (P 31 118))
    $J.AddBezier((P 31 118), (P 17 118), (P 7 108), (P 4 93))
    $J.AddLine((P 4 93), (P 21 88))
    $J.AddBezier((P 21 88), (P 25 97), (P 37 99), (P 38 84))
    $J.AddLine((P 38 84), (P 38 36))
    $J.AddLine((P 38 36), (P 24 34))
    $J.AddLine((P 24 34), (P 12 44))
    $J.CloseFigure()

    # T: wide top bar whose ends flare down to points, stem ending in a
    # spiked foot. Shifted right to leave a gap after the J.
    $tx = 8
    $T = New-Object System.Drawing.Drawing2D.GraphicsPath
    $T.AddPolygon([System.Drawing.PointF[]]@(
        (P (60+$tx) 12), (P (126+$tx) 12), (P (121+$tx) 44), (P (113+$tx) 34), (P (103+$tx) 36),
        (P (103+$tx) 96), (P (111+$tx) 110), (P (93+$tx) 121), (P (75+$tx) 110), (P (83+$tx) 96),
        (P (83+$tx) 36), (P (73+$tx) 34), (P (65+$tx) 44)
    ))

    $glyphs = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glyphs.AddPath($J, $false)
    $glyphs.AddPath($T, $false)
    return $glyphs
}

# Scale the letters to fit a $fit-pixel square and center them on ($cx, $cy).
function Set-LetterFit($glyphs, [double]$fit, [double]$cx, [double]$cy) {
    $b = $glyphs.GetBounds()
    $scale = [Math]::Min($fit / $b.Width, $fit / $b.Height)
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(-($b.X + $b.Width / 2), -($b.Y + $b.Height / 2), [System.Drawing.Drawing2D.MatrixOrder]::Append)
    $m.Scale($scale, $scale, [System.Drawing.Drawing2D.MatrixOrder]::Append)
    $m.Translate($cx, $cy, [System.Drawing.Drawing2D.MatrixOrder]::Append)
    $glyphs.Transform($m)
}

# The logo's gold: pale gold at the top, gold, then orange at the base.
function New-GoldBrush([System.Drawing.RectangleF]$rect) {
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ($rect, (C 255 255 255 255), (C 255 0 0 0), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend 4
    $blend.Colors = [System.Drawing.Color[]]@((C 255 255 248 184), (C 255 255 212 58), (C 255 246 148 18), (C 255 196 78 4))
    $blend.Positions = [single[]]@(0, 0.38, 0.72, 1)
    $brush.InterpolationColors = $blend
    return $brush
}

# Outline, gold faces and bronze rim. $unit is the size of one pixel of the
# 128px icon drawing, so every size has the same proportions.
function Draw-Letters($g, $glyphs, [double]$unit) {
    # 1. Heavy dark outline with sharp corners.
    $outline = New-Object System.Drawing.Pen (C 255 34 16 4), (15 * $unit)
    $outline.LineJoin = [System.Drawing.Drawing2D.LineJoin]::MiterClipped
    $outline.MiterLimit = 2.5
    $g.DrawPath($outline, $glyphs)
    # 2. Gold gradient faces.
    $b = $glyphs.GetBounds()
    $rect = New-Object System.Drawing.RectangleF ($b.X - $unit), ($b.Y - $unit), ($b.Width + 2 * $unit), ($b.Height + 2 * $unit)
    $g.FillPath((New-GoldBrush $rect), $glyphs)
    # 3. A thin bronze rim inside the outline, for the logo's beveled edge.
    $rim = New-Object System.Drawing.Pen (C 210 140 62 6), (2.5 * $unit)
    $rim.LineJoin = [System.Drawing.Drawing2D.LineJoin]::MiterClipped
    $g.DrawPath($rim, $glyphs)
}

function New-Canvas([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return $bmp, $g
}

if ($TgaPath) {
    # Letters fill 106 of 128 pixels, leaving room for the outline.
    $S = 128
    $big, $g = New-Canvas $S
    $g.Clear([System.Drawing.Color]::Transparent)
    $glyphs = New-Letters
    Set-LetterFit $glyphs ($S - 22) ($S / 2) ($S / 2)
    Draw-Letters $g $glyphs 1
    $g.Dispose()

    # Downsample to the 64x64 texture.
    $tex = New-Object System.Drawing.Bitmap 64, 64, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($tex)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($big, 0, 0, 64, 64)
    $g.Dispose()

    # 32-bit uncompressed TGA, bottom-left origin, straight alpha.
    $w = $tex.Width; $h = $tex.Height
    $fs = [System.IO.File]::Create($TgaPath)
    $hdr = New-Object byte[] 18
    $hdr[2] = 2
    $hdr[12] = [byte]($w -band 0xFF); $hdr[13] = [byte](($w -shr 8) -band 0xFF)
    $hdr[14] = [byte]($h -band 0xFF); $hdr[15] = [byte](($h -shr 8) -band 0xFF)
    $hdr[16] = 32
    $hdr[17] = 8
    $fs.Write($hdr, 0, 18)
    $row = New-Object byte[] ($w * 4)
    for ($y = $h - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = $tex.GetPixel($x, $y)
            $i = $x * 4
            $row[$i] = $c.B; $row[$i + 1] = $c.G; $row[$i + 2] = $c.R; $row[$i + 3] = $c.A
        }
        $fs.Write($row, 0, $row.Length)
    }
    $fs.Close()
    Write-Host "Wrote $TgaPath"
}

if ($PngPath) {
    $L = $PngSize
    $logo, $g = New-Canvas $L

    # Dark background, warmer in the middle.
    $g.Clear((C 255 12 9 6))
    $glow = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glow.AddEllipse((-0.25 * $L), (-0.25 * $L), (1.5 * $L), (1.5 * $L))
    $warm = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
    $warm.CenterColor = C 255 58 42 26
    $warm.SurroundColors = [System.Drawing.Color[]]@((C 255 12 9 6))
    $g.FillPath($warm, $glow)

    if ($NoRing) {
        $fit = 0.70 * $L
    } else {
        # A gold ring like the minimap button's, letters inside it.
        $r = 0.44 * $L
        $gold = 0.026 * $L
        $circle = New-Object System.Drawing.RectangleF (($L / 2) - $r), (($L / 2) - $r), (2 * $r), (2 * $r)
        # The gradient covers the whole stroke, so its colors don't wrap
        # around at the ring's top and bottom edges.
        $span = New-Object System.Drawing.RectangleF ($circle.X - $gold), ($circle.Y - $gold), ($circle.Width + 2 * $gold), ($circle.Height + 2 * $gold)
        $g.DrawEllipse((New-Object System.Drawing.Pen (C 255 34 16 4), (0.05 * $L)), $circle)
        $g.DrawEllipse((New-Object System.Drawing.Pen (New-GoldBrush $span), $gold), $circle)
        $fit = 0.53 * $L
    }
    $glyphs = New-Letters
    Set-LetterFit $glyphs $fit ($L / 2) ($L / 2)
    Draw-Letters $g $glyphs ($fit / 106)
    $g.Dispose()
    $logo.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Wrote $PngPath ($L x $L)"
}
