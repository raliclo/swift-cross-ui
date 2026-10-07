# Elevation shim for gpu_select.zsh. It does nothing else.
#
# ASCII only, for the reason given in enable_input.ps1: Windows PowerShell 5.1
# reads a file with no BOM as ANSI, and non-ASCII comments broke the parse.
# The explanation, in both languages, is in gpu_select.zsh.
#
# Why it exists: enabling or disabling a display adapter with pnputil needs
# administrator rights. Why it holds no logic: script logic in this project is
# zsh; a .ps1 is allowed only as a minimal self-elevating launcher.

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$self = $MyInvocation.MyCommand.Path
$here = Split-Path -Parent $self
$target = Join-Path $here 'gpu_select.zsh'

if (-not $isElevated) {
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $self) + $args
    Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Verb RunAs -Wait
    exit $LASTEXITCODE
}

# Elevated from here. Hand straight off to zsh with the same arguments.
& 'C:\Users\lowei\scoop\shims\zsh.exe' $target @args
exit $LASTEXITCODE
