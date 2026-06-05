# SshFree

**[中文](README.md) | [English](README_EN.md)**

A small PowerShell script for Windows that configures **passwordless SSH login
from Windows to a Linux host** using only the OpenSSH client that already ships
with Windows 10 1809+ / Windows 11 / Server 2019+.

No third-party tools. No `ssh-copy-id` (which is not on Windows). No `sshpass`.

## What it does

- generates a key pair (ed25519 by default, or rsa 4096)
- pushes the public key to a remote Linux host (ssh prompts for the password
  once, then it's done forever)
- writes a host entry to `~/.ssh/config` so you can connect with a short alias
  like `ssh mybox`
- verifies the passwordless connection afterwards

## Requirements

- Windows 10 1809+, Windows 11, or Windows Server 2019+ with the
  **OpenSSH Client** optional feature installed
  (`Settings -> Apps -> Optional features -> OpenSSH Client`)
- **PowerShell 7.0+** (run `pwsh -v` to check). Windows PowerShell 5.1
  (the `powershell.exe` shipped with Windows) is **not** supported.

Install PowerShell 7 if needed:
```powershell
winget install Microsoft.PowerShell
```

Quick check:

```powershell
ssh -V
$PSVersionTable.PSVersion   # Major should be 7 or higher
```

## Usage

### Interactive (recommended the first time)

```powershell
.\sshfree.ps1
```

The script shows a menu:

```
SshFree - Windows -> Linux passwordless SSH
What do you want to do?
  1) generate  - create a key pair
  2) push      - install the public key on a Linux host
  3) config    - write an alias to ~/.ssh/config
  4) test      - verify passwordless login works
  5) all       - do 1 -> 2 -> 3 -> 4 in order
```

### One-shot: do everything for one host

```powershell
.\sshfree.ps1 -Action all `
              -RemoteUser ubuntu `
              -RemoteHost 192.168.1.10 `
              -Alias mybox
```

You will be prompted **once** for the Linux password, then:

- `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub` are created
- the public key is appended to `ubuntu@192.168.1.10:~/.ssh/authorized_keys`
- a `mybox` block is added to `~/.ssh/config`
- the connection is tested with `BatchMode=yes` to confirm no password is needed

From then on:

```powershell
ssh mybox
```

### Pick an algorithm

```powershell
# RSA 4096, e.g. for older servers that don't support ed25519
.\sshfree.ps1 -Action all -KeyType rsa -RemoteUser root -RemoteHost 10.0.0.5 -Alias oldbox
```

### Custom key path

```powershell
.\sshfree.ps1 -Action generate -KeyType ed25519 -KeyPath D:\keys\work_ed25519
```

### Sub-actions

| Action    | What it does                                             | Required args                                  |
|-----------|----------------------------------------------------------|------------------------------------------------|
| generate  | runs `ssh-keygen`, prints the public key + fingerprint   | none                                           |
| push      | appends the public key to the server's `authorized_keys`| `-RemoteUser`, `-RemoteHost`                   |
| config    | writes a block to `~/.ssh/config`                        | `-RemoteUser`, `-RemoteHost`, `-Alias`         |
| test      | runs `ssh ... 'echo OK'` with `BatchMode=yes`            | `-Alias` **or** `-RemoteUser` + `-RemoteHost`  |
| all       | generate -> push -> config -> test                       | `-RemoteUser`, `-RemoteHost`, `-Alias`         |

### All parameters

```
-Action       generate | push | config | test | all
-KeyType      ed25519 (default) | rsa
-KeyPath      full path to the private key (default: ~/.ssh/id_<type>)
-RemoteUser   Linux login user
-RemoteHost   Linux host name or IP
-RemotePort   SSH port (default 22)
-Alias        short name for ~/.ssh/config
-Passphrase   optional passphrase for the new key
```

## Idempotency

- `generate`: refuses to overwrite an existing key unless you answer `y`
- `push`: uses `grep -qxF` to skip the public key if it's already installed
- `config`: any previous `sshfree: <alias>` block for the same alias is removed
  before the new one is written
- `test`: safe to re-run anytime

## Files touched

- `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub` (or `id_rsa*`)
- `~/.ssh/config` — only inside `# >>> sshfree: <alias> >>> ... # <<< sshfree: <alias> <<<` markers
- nothing in the repository directory

## Notes

- The `push` step relies on `ssh.exe` itself prompting for the password
  interactively. The password is **never** passed as a command-line argument,
  so it won't leak into shell history or process listings.
- The remote `authorized_keys` is created with `umask 077` and explicit
  `chmod 700` / `chmod 600`, which is what sshd requires.
- For host key verification, the script uses `StrictHostKeyChecking=accept-new`
  on the push step (asks only on the first connection to a new host).
