$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$source = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/branding/app_icon.png'))
function Get-IconPng([int]$size) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $stream = [System.IO.MemoryStream]::new()
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($source, 0, 0, $size, $size)
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally { $stream.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
}
try {
    $targets = @{}
    $densities = @{ mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192 }
    foreach ($density in $densities.Keys) {
        $targets["android/app/src/main/res/mipmap-$density/ic_launcher.png"] = $densities[$density]
    }
    foreach ($platform in @('ios','macos')) {
        $folder = "$platform/Runner/Assets.xcassets/AppIcon.appiconset"
        $catalog = Get-Content (Join-Path $projectRoot "$folder/Contents.json") -Raw | ConvertFrom-Json
        foreach ($entry in $catalog.images) {
            $targets["$folder/$($entry.filename)"] = [int]([double]($entry.size.Split('x')[0]) * [double]($entry.scale.TrimEnd('x')))
        }
    }
    $targets['web/favicon.png'] = 32
    foreach ($size in @(192,512)) {
        $targets["web/icons/Icon-$size.png"] = $size
        $targets["web/icons/Icon-maskable-$size.png"] = $size
    }
    foreach ($path in $targets.Keys) {
        [System.IO.File]::WriteAllBytes((Join-Path $projectRoot $path), (Get-IconPng $targets[$path]))
    }
    # ICO directory with one PNG frame per Windows shell size.
    $sizes = @(16,24,32,48,64,128,256)
    $frames = @($sizes | ForEach-Object { ,(Get-IconPng $_) })
    $ico = [System.IO.File]::Create((Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'))
    $writer = [System.IO.BinaryWriter]::new($ico)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i=0; $i -lt $sizes.Count; $i++) {
            $dimension = [byte]($sizes[$i] % 256)
            $writer.Write($dimension); $writer.Write($dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$i].Length); $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    } finally { $writer.Dispose() }
    Write-Output "Updated $($targets.Count) PNG icons and Windows ICO (7 sizes)."
} finally { $source.Dispose() }
