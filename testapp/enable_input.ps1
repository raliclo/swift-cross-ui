# Elevation shim for enable_input.zsh. It does nothing else.
#
# ASCII ONLY, AND THAT IS A REQUIREMENT RATHER THAN A STYLE. Windows PowerShell
# 5.1 reads a file with no BOM as ANSI, not UTF-8. An earlier version of this
# shim carried the same bilingual comments as the rest of the project; the
# Chinese bytes were mis-decoded, the parser swallowed the assignment that
# followed them, and Start-Process failed with "Cannot validate argument on
# parameter 'ArgumentList'. The argument is null or empty" -- pointing at a line
# that was correct. The explanation lives in enable_input.zsh, in both
# languages, where it is read correctly.
#
# Why this file exists at all: stopping a blocker that runs elevated needs UAC,
# and that was measured rather than assumed -- `taskkill -f -pid 644` from a
# medium-integrity shell printed "Access is denied" and still exited 0.
#
# Why it holds no logic: this project writes script logic in zsh. The only
# sanctioned use of a .ps1 is a minimal self-elevating launcher that hands off
# immediately.

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$self = $MyInvocation.MyCommand.Path
$here = Split-Path -Parent $self
$target = Join-Path $here 'enable_input.zsh'

if (-not $isElevated) {
    # One line. Backtick continuation broke here on the first attempt, and the
    # project's notes warn against it on this host.
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $self)
    Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Verb RunAs -Wait
    exit $LASTEXITCODE
}

# Elevated from here. Hand straight off to zsh.
& 'C:\Users\lowei\scoop\shims\zsh.exe' $target
exit $LASTEXITCODE
