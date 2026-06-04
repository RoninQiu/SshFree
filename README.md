# SshFree

A small PowerShell script for Windows that configures **passwordless SSH login
from Windows to a Linux host** using only the OpenSSH client that already ships
with Windows 10 1809+ / Windows 11 / Server 2019+.

No third-party tools. No `ssh-copy-id` (which is not on Windows). No `sshpass`.

> **Language / 语言** — click to switch:
> - **🇬🇧 English** (open by default, below)
> - **🇨🇳 中文** (click to expand)

---

<details open>
<summary><strong>🇬🇧 English documentation</strong> (click to collapse)</summary>

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

</details>

---

<details>
<summary><strong>🇨🇳 中文文档（点击展开）</strong></summary>

## 功能

- 生成密钥对（默认 ed25519，可选 rsa 4096）
- 把公钥推送到远程 Linux（密码由 `ssh.exe` 自己交互式提示，**只输一次**）
- 往 `~/.ssh/config` 写一条别名配置，以后直接 `ssh mybox` 就能连
- 推送完后自动验证免密连接是否真的可用

## 环境要求

- Windows 10 1809+ / Windows 11 / Windows Server 2019+
- **OpenSSH 客户端** 已在系统里启用
  （设置 -> 应用 -> 可选功能 -> OpenSSH 客户端）
- **PowerShell 7.0+**（运行 `pwsh -v` 查看）。Windows 自带的
  PowerShell 5.1（也就是 `powershell.exe`）**不支持**。

如果还没装 PowerShell 7：
```powershell
winget install Microsoft.PowerShell
```

快速自检：

```powershell
ssh -V
$PSVersionTable.PSVersion   # Major 应大于等于 7
```

## 用法

### 交互式（首次使用推荐）

```powershell
.\sshfree.ps1
```

脚本会显示菜单：

```
SshFree - Windows -> Linux passwordless SSH
What do you want to do?
  1) generate  - 创建密钥对
  2) push      - 把公钥装到 Linux 上
  3) config    - 往 ~/.ssh/config 写一条别名
  4) test      - 验证免密连接
  5) all       - 依次跑 1 -> 2 -> 3 -> 4
```

### 一行命令搞定一台机器

```powershell
.\sshfree.ps1 -Action all `
              -RemoteUser ubuntu `
              -RemoteHost 192.168.1.10 `
              -Alias mybox
```

过程中**只会提示一次** Linux 密码，然后：

- 在 `~/.ssh/id_ed25519` 和 `~/.ssh/id_ed25519.pub` 创建密钥
- 公钥被追加到 `ubuntu@192.168.1.10:~/.ssh/authorized_keys`
- `~/.ssh/config` 中新增 `mybox` 区块
- 用 `BatchMode=yes` 测试连接，确认免密已生效

之后就可以这样连：

```powershell
ssh mybox
```

### 选算法

```powershell
# RSA 4096，比如老服务器不支持 ed25519 时
.\sshfree.ps1 -Action all -KeyType rsa -RemoteUser root -RemoteHost 10.0.0.5 -Alias oldbox
```

### 自定义密钥路径

```powershell
.\sshfree.ps1 -Action generate -KeyType ed25519 -KeyPath D:\keys\work_ed25519
```

### 子动作一览

| Action    | 作用                                              | 必填参数                                   |
|-----------|---------------------------------------------------|--------------------------------------------|
| generate  | 跑 `ssh-keygen`，打印公钥和指纹                  | 无                                         |
| push      | 把公钥追加到服务器的 `authorized_keys`           | `-RemoteUser`、`-RemoteHost`               |
| config    | 往 `~/.ssh/config` 写一个区块                    | `-RemoteUser`、`-RemoteHost`、`-Alias`     |
| test      | `BatchMode=yes` 跑 `ssh ... 'echo OK'`           | `-Alias` **或** `-RemoteUser` + `-RemoteHost` |
| all       | generate -> push -> config -> test               | `-RemoteUser`、`-RemoteHost`、`-Alias`     |

### 全部参数

```
-Action       generate | push | config | test | all
-KeyType      ed25519（默认）| rsa
-KeyPath      私钥的完整路径（默认：~/.ssh/id_<type>）
-RemoteUser   Linux 登录用户名
-RemoteHost   Linux 主机名或 IP
-RemotePort   SSH 端口（默认 22）
-Alias        ~/.ssh/config 里的短别名
-Passphrase   新密钥的口令（可选）
```

## 幂等性

- `generate`：已有密钥时不覆盖，除非你输入 `y`
- `push`：用 `grep -qxF` 判断公钥是否已存在，存在就跳过
- `config`：再次运行会先移除同名的旧 `sshfree: <alias>` 区块，再写新的
- `test`：随时可以重跑

## 涉及的文件

- `~/.ssh/id_ed25519` 和 `~/.ssh/id_ed25519.pub`（或 `id_rsa*`）
- `~/.ssh/config` —— 只在 `# >>> sshfree: <alias> >>> ... # <<< sshfree: <alias> <<<` 标记之间写入
- 仓库目录里**不会**留下任何东西

## 注意事项

- `push` 时密码由 `ssh.exe` 自己交互式提示，**绝不会**作为命令行参数传入，
  所以不会泄漏到 shell 历史或进程列表里。
- 远端 `authorized_keys` 由 `umask 077` 创建，并显式 `chmod 700` / `chmod 600`，
  这是 sshd 要求的权限。
- 主机密钥校验用 `StrictHostKeyChecking=accept-new`（第一次连新机器时才会问）。

## 常见问题

**Q: 双击 `sshfree.ps1` 没反应？**
A: 必须从 PowerShell 里执行。如果脚本被执行策略拦截：
```powershell
powershell -ExecutionPolicy Bypass -File .\sshfree.ps1
```
或者放宽当前用户的策略：
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

**Q: `push` 报 `Permission denied (publickey,password)`？**
A: 三种可能，按顺序排查：
1. 公钥没真的写进远端 `~/.ssh/authorized_keys`（这条脚本现在会自动复核
   并直接报错，不会再像之前那样假报成功）。先 ssh 上去看一眼：
   `cat ~/.ssh/authorized_keys` —— 里面应该有类似
   `ssh-ed25519 AAAA...` 的一行。
2. 远端 sshd 不允许密码登录（脚本第一步需要密码）。检查
   `/etc/ssh/sshd_config` 里的 `PasswordAuthentication` 是否被关掉。
3. 远端 sshd 不允许该用户用公钥登录。检查 `PubkeyAuthentication`，
   以及 `AllowUsers` / `AllowGroups`。

</details>
