<#
.SYNOPSIS
    Configure passwordless SSH login from Windows to a Linux host.

.DESCRIPTION
    SshFree automates the typical "ssh-copy-id" workflow on Windows using only the
    built-in OpenSSH client. It can:
      * generate a key pair (ed25519 by default, or rsa 4096)
      * push the public key to a remote Linux host (password prompted by ssh itself)
      * write a host entry to ~/.ssh/config so you can connect with a short alias
      * test the passwordless connection afterwards

    No third-party tools are required: PowerShell 7.0+ and the built-in
    ssh / ssh-keygen (shipped with Windows 10 1809+ / Windows 11 / Server 2019+).
    Windows PowerShell 5.1 is NOT supported.

.PARAMETER Action
    One of: generate, push, config, test, all. When omitted, an interactive menu
    is shown.

.PARAMETER KeyType
    ed25519 (default) or rsa.

.PARAMETER KeyPath
    Full path to the private key file. Defaults to
    $HOME\.ssh\id_ed25519 or $HOME\.ssh\id_rsa depending on -KeyType.

.PARAMETER RemoteUser
    Linux login user (e.g. "root", "ubuntu").

.PARAMETER RemoteHost
    Linux host name or IP address.

.PARAMETER RemotePort
    SSH port on the remote host. Default 22.

.PARAMETER Alias
    Friendly alias to write into ~/.ssh/config (push/config actions only).

.PARAMETER Passphrase
    Optional passphrase for the new key. If omitted, ssh-keygen will prompt.

.EXAMPLE
    .\sshfree.ps1 -Action all -RemoteUser ubuntu -RemoteHost 192.168.1.10 -Alias mybox

    Generate an ed25519 key, push it to ubuntu@192.168.1.10, write a
    config entry for "mybox", and verify the connection.

.EXAMPLE
    .\sshfree.ps1 -Action push -KeyType rsa -RemoteUser root -RemoteHost my.linux.lan

    Use an RSA 4096 key and push only the public key.

.EXAMPLE
    .\sshfree.ps1

    Interactive mode: walks you through every step.
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [ValidateSet('generate', 'push', 'config', 'test', 'all')]
    [string]$Action,

    [ValidateSet('ed25519', 'rsa')]
    [string]$KeyType = 'ed25519',

    [string]$KeyPath,

    [Parameter(Mandatory = $false)]
    [string]$RemoteUser,

    [Parameter(Mandatory = $false)]
    [string]$RemoteHost,

    [ValidateRange(1, 65535)]
    [int]$RemotePort = 22,

    [string]$Alias,

    [string]$Passphrase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- helpers ----------------------------------------------------------------

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('==[ {0} ]==' -f $Title) -ForegroundColor Cyan
}

function Test-OpenSshInstalled {
    $ssh      = (Get-Command ssh.exe      -ErrorAction SilentlyContinue)
    $keygen   = (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)
    if (-not $ssh -or -not $keygen) {
        throw "OpenSSH client is not installed. On Windows 11 / 10 1809+, enable it via 'Settings -> Apps -> Optional features -> OpenSSH Client'."
    }
}

function Resolve-KeyPath {
    param(
        [ValidateSet('ed25519', 'rsa')][string]$Type,
        [string]$Explicit
    )
    if ($Explicit) { return $Explicit }
    $name = if ($Type -eq 'rsa') { 'id_rsa' } else { 'id_ed25519' }
    return (Join-Path $HOME ".ssh\$name")
}

function Confirm-Overwrite {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $ans = Read-Host ("File '{0}' already exists. Overwrite? [y/N]" -f $Path)
        if ($ans -notin @('y', 'Y', 'yes', 'YES')) {
            throw "Aborted by user."
        }
    }
}

function Invoke-Generate {
    [CmdletBinding()]
    param(
        [ValidateSet('ed25519', 'rsa')][string]$KeyType,
        [string]$KeyPath,
        [string]$Passphrase
    )

    Write-Section "generate key ($KeyType)"
    $dir = Split-Path -Parent $KeyPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # Tighten permissions on the .ssh directory (best-effort on Windows).
    try { (Get-Item -LiteralPath $dir -Force).Attributes = 'Hidden' } catch { }

    if (-not (Test-Path -LiteralPath "$KeyPath.pub")) {
        # Public key missing. If the private key is also missing this is a fresh
        # generate, no need to ask. Only prompt if the private key actually
        # exists and would be overwritten.
        if (Test-Path -LiteralPath $KeyPath) { Confirm-Overwrite $KeyPath }
    } else {
        # Public key already there -> assume key exists, don't overwrite silently.
        Write-Host ("Key already exists at {0}, skipping ssh-keygen." -f $KeyPath) -ForegroundColor Yellow
    }

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        # PS7+ required (see #Requires -Version 7.0 at top), so ?? is available.
        $passArg = $Passphrase ?? ''
        $keygenArgs = @('-t', $KeyType, '-f', $KeyPath, '-N', $passArg, '-C', ("{0}@sshfree@{1}" -f $env:USERNAME, $env:COMPUTERNAME))
        if ($KeyType -eq 'rsa') { $keygenArgs += @('-b', '4096') }
        & ssh-keygen.exe @keygenArgs
        if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed with exit code $LASTEXITCODE." }
    }

    Write-Host ''
    Write-Host "Private key : $KeyPath"            -ForegroundColor Green
    Write-Host "Public  key : $KeyPath.pub"        -ForegroundColor Green
    Write-Host ''
    Write-Host '--- public key (copy/paste this to the server if you cannot push) ---' -ForegroundColor DarkGray
    Get-Content -LiteralPath "$KeyPath.pub" -Raw
    Write-Host '----------------------------------------------------------------------------' -ForegroundColor DarkGray

    $fp = (& ssh-keygen.exe -lf $KeyPath) 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Host ("Fingerprint: " + ($fp -join ' ')) -ForegroundColor Cyan }
}

function Invoke-Push {
    [CmdletBinding()]
    param(
        [string]$KeyPath,
        [Parameter(Mandatory)][string]$RemoteUser,
        [Parameter(Mandatory)][string]$RemoteHost,
        [int]$RemotePort = 22
    )

    Write-Section "push public key to $RemoteUser@$RemoteHost"
    $pub = "$KeyPath.pub"
    if (-not (Test-Path -LiteralPath $pub)) {
        throw "Public key '$pub' not found. Run -Action generate first."
    }

    # Read public key into memory. We embed it into the remote command on the
    # LOCAL side (this is a PowerShell string, not a remote shell variable),
    # so the key actually reaches the server.
    $pubText = (Get-Content -LiteralPath $pub -Raw).Trim()
    if (-not $pubText) { throw "Public key file '$pub' is empty." }

    # Defensive escape: a single-quoted POSIX string ends at the next '.
    # The pattern  '\”  (close, escaped quote, reopen) is safe for any content.
    $pubQuoted = "'" + ($pubText -replace "'", "'\\''") + "'"

    $remoteCmd = 'umask 077; mkdir -p ~/.ssh && chmod 700 ~/.ssh && ' +
                 'touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && ' +
                 'grep -qxF ' + $pubQuoted + ' ~/.ssh/authorized_keys || ' +
                 'echo ' + $pubQuoted + ' >> ~/.ssh/authorized_keys && ' +
                 'echo __SSHFREE_PUSH_OK__'

    # ssh.exe will prompt for the password interactively. (Note: $pubText is NOT
    # piped over stdin any more — the key is now inside the command itself, so
    # stdin is not consumed by the remote shell.)
    $sshArgs = @(
        '-p', $RemotePort,
        '-o', 'StrictHostKeyChecking=accept-new',
        "$RemoteUser@$RemoteHost",
        $remoteCmd
    )

    Write-Host "You will be prompted for the Linux password once." -ForegroundColor Yellow
    Write-Host "Pushing public key..." -ForegroundColor Cyan
    $output = & ssh.exe @sshArgs
    if ($LASTEXITCODE -ne 0) { throw "ssh failed with exit code $LASTEXITCODE." }
    if (($output -join "`n") -notmatch '__SSHFREE_PUSH_OK__') {
        throw "Push did not complete on the remote side. The remote command did not print the success marker. Check that the home directory is writable and that the user is not in a restricted shell."
    }

    # Post-push verification: ssh back with BatchMode=yes and confirm the key
    # is actually present in authorized_keys. This catches the case where the
    # remote shell silently dropped the appended line (e.g. read-only mount,
    # quota, restricted shell).
    $verifyArgs = @(
        '-p', $RemotePort,
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=10',
        "$RemoteUser@$RemoteHost",
        'grep -qxF ' + $pubQuoted + ' ~/.ssh/authorized_keys && echo __SSHFREE_VERIFY_OK__'
    )
    $v = & ssh.exe @verifyArgs
    if ($LASTEXITCODE -ne 0 -or (($v -join "`n") -notmatch '__SSHFREE_VERIFY_OK__')) {
        throw "Push reported success but the public key was NOT found in the remote authorized_keys afterwards. The remote likely refused the write (read-only mount, quota, or restrictive shell). Re-check after fixing the remote side."
    }
    Write-Host "Public key installed and verified on remote host." -ForegroundColor Green
}

function Invoke-WriteConfig {
    [CmdletBinding()]
    param(
        [string]$KeyPath,
        [Parameter(Mandatory)][string]$RemoteUser,
        [Parameter(Mandatory)][string]$RemoteHost,
        [int]$RemotePort = 22,
        [Parameter(Mandatory)][string]$Alias
    )

    Write-Section "write ssh config alias '$Alias'"
    $configPath = Join-Path $HOME '.ssh\config'
    $configDir  = Split-Path -Parent $configPath
    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Load existing config (if any), drop any previous block for this alias.
    $lines = @()
    if (Test-Path -LiteralPath $configPath) {
        $lines = Get-Content -LiteralPath $configPath
    }

    $startMarker = "# >>> sshfree: $Alias >>>"
    $endMarker   = "# <<< sshfree: $Alias <<<"
    $filtered    = New-Object System.Collections.Generic.List[string]
    $inBlock     = $false
    foreach ($l in $lines) {
        if ($l -eq $startMarker) { $inBlock = $true; continue }
        if ($l -eq $endMarker)   { $inBlock = $false; continue }
        if (-not $inBlock) { $filtered.Add($l) }
    }

    $block = @(
        $startMarker,
        "Host $Alias",
        "    HostName $RemoteHost",
        "    Port $RemotePort",
        "    User $RemoteUser",
        "    IdentityFile $KeyPath",
        "    IdentitiesOnly yes",
        "    ServerAliveInterval 30",
        $endMarker
    ) -join "`r`n"

    $newContent = (($filtered -join "`r`n").TrimEnd("`r","`n")) + "`r`n`r`n" + $block + "`r`n"
    Set-Content -LiteralPath $configPath -Value $newContent -Encoding UTF8

    Write-Host "Wrote entry to $configPath" -ForegroundColor Green
    Write-Host "Try: ssh $Alias" -ForegroundColor Cyan
}

function Invoke-Test {
    [CmdletBinding()]
    param(
        [string]$KeyPath,
        [string]$RemoteUser,
        [string]$RemoteHost,
        [int]$RemotePort = 22,
        [string]$Alias
    )

    Write-Section "test connection"

    $target = if ($Alias) { $Alias } else { "$RemoteUser@$RemoteHost" }
    $sshArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
    if (-not $Alias) { $sshArgs += @('-p', $RemotePort, '-i', $KeyPath) }

    Write-Host "ssh $target  (BatchMode=yes -> no password prompt, key-only)" -ForegroundColor Cyan
    & ssh.exe @sshArgs $target 'echo "[sshfree] OK from $(uname -a) as $(whoami)"'
    if ($LASTEXITCODE -ne 0) { throw "Test failed (exit $LASTEXITCODE). Check the public key on the server and ~/.ssh permissions." }
    Write-Host "Connection verified." -ForegroundColor Green
}

# ---- entry point ------------------------------------------------------------

Test-OpenSshInstalled
$KeyPath = Resolve-KeyPath -Type $KeyType -Explicit $KeyPath

if (-not $Action) {
    Write-Host ''
    Write-Host 'SshFree - Windows -> Linux passwordless SSH' -ForegroundColor Cyan
    Write-Host 'What do you want to do?'
    Write-Host '  1) generate  - create a key pair'
    Write-Host '  2) push      - install the public key on a Linux host'
    Write-Host '  3) config    - write an alias to ~/.ssh/config'
    Write-Host '  4) test      - verify passwordless login works'
    Write-Host '  5) all       - do 1 -> 2 -> 3 -> 4 in order'
    $pick = Read-Host 'Choose [1-5]'
    $Action = @{ '1' = 'generate'; '2' = 'push'; '3' = 'config'; '4' = 'test'; '5' = 'all' }[$pick]
    if (-not $Action) { throw "Invalid choice." }
}

switch ($Action) {
    'generate' { Invoke-Generate -KeyType $KeyType -KeyPath $KeyPath -Passphrase $Passphrase }
    'push' {
        if (-not $RemoteUser -or -not $RemoteHost) { throw "-RemoteUser and -RemoteHost are required for 'push'." }
        Invoke-Push -KeyPath $KeyPath -RemoteUser $RemoteUser -RemoteHost $RemoteHost -RemotePort $RemotePort
    }
    'config' {
        if (-not $RemoteUser -or -not $RemoteHost) { throw "-RemoteUser and -RemoteHost are required for 'config'." }
        if (-not $Alias) { $Alias = Read-Host 'Alias name (e.g. mybox)'; if (-not $Alias) { throw "Alias is required." } }
        Invoke-WriteConfig -KeyPath $KeyPath -RemoteUser $RemoteUser -RemoteHost $RemoteHost -RemotePort $RemotePort -Alias $Alias
    }
    'test' {
        if (-not $Alias -and (-not $RemoteUser -or -not $RemoteHost)) {
            throw "Provide either -Alias (with a configured entry) or -RemoteUser/-RemoteHost."
        }
        Invoke-Test -KeyPath $KeyPath -RemoteUser $RemoteUser -RemoteHost $RemoteHost -RemotePort $RemotePort -Alias $Alias
    }
    'all' {
        if (-not $RemoteUser -or -not $RemoteHost) { throw "-RemoteUser and -RemoteHost are required for 'all'." }
        if (-not $Alias) { $Alias = Read-Host 'Alias name (e.g. mybox)'; if (-not $Alias) { throw "Alias is required." } }
        Invoke-Generate   -KeyType $KeyType -KeyPath $KeyPath -Passphrase $Passphrase
        Invoke-Push       -KeyPath $KeyPath -RemoteUser $RemoteUser -RemoteHost $RemoteHost -RemotePort $RemotePort
        Invoke-WriteConfig -KeyPath $KeyPath -RemoteUser $RemoteUser -RemoteHost $RemoteHost -RemotePort $RemotePort -Alias $Alias
        Invoke-Test       -KeyPath $KeyPath -Alias $Alias
    }
}
