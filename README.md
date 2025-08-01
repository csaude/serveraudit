# HIS HF Linux Server Compliance Kit

This repository bundles **the necessary files to run an HF Linux Server audit** to run a CIS Level 1 audit compliant (HIS HF server profile) on Ubuntu 22.04 LTS or 24.04 LTS, with a
small head-less customization file.

| File | Purpose |
|------|---------|
| `auditar_servidor.sh` | Bash script that installs OpenSCAP + Lynis, picks the correct DataStream, applies the customization and saves a ZIP with the results to be sent back. |
| `ssg-ubuntu2204-ds-tailoring.xml`  | XCCDF 1.2 compliant tailoring – inherits from the CIS Level 1 **Server** profile and  customize HIS HF profile. |
| `ssg-ubuntu2204-ds.xml` / `ssg-ubuntu2404-ds.xml` | Official SCAP Security Guide DataStreams (v 0.1.76). |

**No internet connection is required** on the target server; the script uses the local DataStream files shipped in this repository.

---

## 1 — Prerequisites

* Ubuntu 22.04 LTS (Jammy) or 24.04 LTS (Noble)
* `sudo` access
* Basic outbound e-mail or file-transfer mechanism to send the resulting ZIP
  back to the security team

The script will install, if missing:

```bash
libopenscap8  lynis  zip  curl
```

## 2 - Quick start (for system administrators)
```bash
# 1. Clone or copy this repo to the server
$ git clone https://github.com/csaude/serveraudit.git
$ cd serveraudit

# 2. Allow execution
$ chmod +x auditar_servidor.sh

# 3. Run the audit (requires sudo)
$ sudo ./auditar_servidor.sh
```

Runtime: ±3–6 minutes on a typical Linux system.
After completion you will see:

```bash
ZIP created: ./auditoria-<hostname>-<timestamp>.zip
Send this file to the security team.
```
## 3 - What's inside the ZIP?

```bash
auditoria-<host>-<date>.zip
├── relatorio-cis-<host>-<date>.html     # Full OpenSCAP HTML report (customized CIS L1)
├── checks-custom-<host>-<date>.txt      # OS simple checks Disk encryption, generic accounts, DB SSL
├── lynis-<host>-<date>.txt              # Lynis quick scan
└── SHA-256 embedded inside the ZIP      # To chek cif files were tampered during transmission
```
Only the three last reports are kept in the same folder where the script is executed. Older reports will be deleted automatically by the script.

## 4- Troubleshooting

If there is any trouble running the script please report to it.sec.support@csaude.org.mz

## 5 - Contributing

Pull requests are welcome!
Please keep changes backwards-compatible with OpenSCAP 1.2.x (default on Ubuntu 22.04/24.04) and XCCDF 1.2 syntax.

© 2025 C-Saude Security Team


