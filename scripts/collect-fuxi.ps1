$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $workspaceRoot 'device-info'
$outputFile = Join-Path $outputDirectory 'fuxi-kernel-info.txt'

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'Không tìm thấy adb trong PATH.'
}

$deviceLines = @(adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\S' })
$readyDevices = @($deviceLines | Where-Object { $_ -match "\tdevice$" })

if ($readyDevices.Count -ne 1) {
    throw "Cần đúng một thiết bị ADB ở trạng thái 'device'. Hiện tìm thấy: $($readyDevices.Count)."
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

function Add-Section {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Command
    )

    Add-Content -LiteralPath $outputFile -Value "`n## $Title"
    Add-Content -LiteralPath $outputFile -Value (adb shell $Command 2>&1)
}

Set-Content -LiteralPath $outputFile -Value @(
    '# Xiaomi 13 (fuxi) kernel information'
    "# Collected: $([DateTimeOffset]::Now.ToString('o'))"
)

Add-Section -Title 'adb identity' -Command 'getprop ro.product.device; getprop ro.product.model'
Add-Section -Title 'build fingerprint' -Command 'getprop ro.build.fingerprint'
Add-Section -Title 'incremental build' -Command 'getprop ro.build.version.incremental'
Add-Section -Title 'Android SDK/version' -Command 'getprop ro.build.version.sdk; getprop ro.build.version.release'
Add-Section -Title 'uname' -Command 'uname -a'
Add-Section -Title 'kernel release' -Command 'uname -r'
Add-Section -Title 'kernel version' -Command 'cat /proc/version'
Add-Section -Title 'bootconfig' -Command 'cat /proc/bootconfig 2>/dev/null || true'
Add-Section -Title 'selected kernel config' -Command "zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_(KPROBES|KPROBE_EVENTS|MODULES|MODVERSIONS|MODULE_SIG|MODULE_SIG_FORCE|KALLSYMS|IKCONFIG|IKCONFIG_PROC|KSU|KSU_SUSFS)=' || true"
$moduleVermagicCommand = @'
for f in /vendor_dlkm/lib/modules/*.ko /vendor/lib/modules/*.ko; do [ -f "$f" ] || continue; modinfo "$f" 2>/dev/null | sed -n 's/^vermagic:[[:space:]]*//p'; done | sort -u
'@
Add-Section -Title 'module vermagic values' -Command $moduleVermagicCommand
Add-Section -Title 'module directories' -Command 'ls -ld /vendor_dlkm/lib/modules /vendor/lib/modules 2>/dev/null || true'

Write-Host "Đã ghi thông tin vào $outputFile"
