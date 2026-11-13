# 打包 OneCast 插件 zip（结构与 GitHub release 一致：单一 OneCast/ 目录）
# 用法:
#   .\pack.ps1
#   .\pack.ps1 -Committed          # 仅打包已提交内容（等同 git archive）
#   .\pack.ps1 -OutDir "D:\ProgramData\World of Warcraft\_forever_\Interface\AddOns"
param(
    [switch]$Committed,
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$toc = Join-Path $root "OneCast.toc"
if (-not (Test-Path $toc)) {
    throw "找不到 OneCast.toc：$toc"
}

$versionLine = Select-String -Path $toc -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) {
    throw "OneCast.toc 中没有 ## Version:"
}
$version = $versionLine.Matches[0].Groups[1].Value.Trim()

$dist = Join-Path $root "dist"
$zipName = "OneCast-$version.zip"
$zipPath = Join-Path $dist $zipName

# 与 .gitattributes 的 export-ignore 一致，并排除本地杂项
$excludeNames = @(
    ".git",
    ".github",
    ".gitignore",
    ".gitattributes",
    ".vscode",
    ".idea",
    "dist",
    "AutoFisher",
    "DEVELOPMENT.md",
    "UPSTREAM.md",
    "pack.ps1",
    "release-notes.md"
)

Write-Host "版本: $version"
Write-Host "输出: $zipPath"

if (Test-Path $dist) {
    Remove-Item $dist -Recurse -Force
}
New-Item -ItemType Directory -Path $dist -Force | Out-Null

if ($Committed) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "未找到 git，无法使用 -Committed"
    }
    Push-Location $root
    try {
        $null = git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "当前目录不是 git 仓库"
        }
        & git archive --format=zip --prefix=OneCast/ -o $zipPath HEAD
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zipPath)) {
            throw "git archive 失败"
        }
        Write-Host "模式: git archive（仅已提交内容）"
    } finally {
        Pop-Location
    }
} else {
    Write-Host "模式: 工作区文件（含未提交更改）"
    $stage = Join-Path $dist "stage"
    $addonRoot = Join-Path $stage "OneCast"
    New-Item -ItemType Directory -Path $addonRoot -Force | Out-Null

    Get-ChildItem -Path $root -Force | ForEach-Object {
        if ($excludeNames -contains $_.Name) { return }
        if (-not $_.PSIsContainer -and $_.Extension -eq ".zip") { return }
        $dest = Join-Path $addonRoot $_.Name
        if ($_.PSIsContainer) {
            Copy-Item $_.FullName $dest -Recurse -Force
        } else {
            Copy-Item $_.FullName $dest -Force
        }
    }

    if (-not (Test-Path (Join-Path $addonRoot "OneCast.toc"))) {
        throw "打包失败：stage 中没有 OneCast.toc"
    }

    Compress-Archive -Path $addonRoot -DestinationPath $zipPath -Force
    Remove-Item $stage -Recurse -Force
}

if (-not (Test-Path $zipPath)) {
    throw "打包失败：未生成 $zipPath"
}

Write-Host ""
Write-Host "已生成: $zipPath"
Get-Item $zipPath | Format-List FullName, Length, LastWriteTime

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($zip.Entries | Where-Object { $_.FullName -ne "OneCast/" } | Select-Object -ExpandProperty FullName)
    Write-Host "包内文件数: $($entries.Count)"
    $entries | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }
    if ($entries.Count -gt 25) {
        Write-Host "  ..."
    }
} finally {
    $zip.Dispose()
}

if ($OutDir) {
    $destAddon = Join-Path $OutDir "OneCast"
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    if (Test-Path $destAddon) {
        Remove-Item $destAddon -Recurse -Force
    }
    Expand-Archive -Path $zipPath -DestinationPath $OutDir -Force
    Write-Host ""
    Write-Host "已安装到: $destAddon"
}

Write-Host ""
Write-Host "解压后放到: World of Warcraft\_forever_\Interface\AddOns\OneCast"
