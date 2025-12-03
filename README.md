# `acmeShellAuth.sh` — TrueNAS ACME DNS-01 Authenticator using acme.sh (multi-provider, GPLv3)

This script lets **TrueNAS CORE / SCALE (25.10+)** complete **Let’s Encrypt DNS-01 challenges** using **any acme.sh DNS provider plugin** (Dynu, Cloudflare, Hetzner, …).

TrueNAS handles the ACME flow itself. For DNS-01 validation it expects a **Shell ACME DNS Authenticator** script that:

- creates the `_acme-challenge` TXT record  
- deletes it again after validation  

This wrapper reuses acme.sh’s **dnsapi modules** and calls their functions directly, e.g.:

- `dns_dynu_add` / `dns_dynu_rm`  
- `dns_cf_add` / `dns_cf_rm`  
- `dns_hetzner_add` / `dns_hetzner_rm`  
- …any other acme.sh DNS provider.

---

## 📌 Features

- Uses **acme.sh dnsapi** provider scripts — no custom DNS logic.  
- **Multi-provider**: select Dynu / Cloudflare / Hetzner etc. via a simple `credentials` file.  
- TrueNAS calls a single shell script; acme.sh handles provider-specific details.  
- No Docker and no system-wide acme.sh installation required.

---

## 📦 Repository Layout & Clone Instructions

All examples below use a base directory:

    /path/to/

You should clone **acme.sh** and this repo into that same base directory.

### 1. Clone acme.sh

    cd /path/to
    git clone https://github.com/acmesh-official/acme.sh.git

### 2. Clone this repo

    cd /path/to
    git clone https://github.com/hansinator/truenas-acme-shell.git
    cd truenas-acme-shell
    chmod 755 acmeShellAuth.sh
    touch credentials
    chmod 600 credentials

### 3. Resulting layout

    /path/to/
      acme.sh/                 ← acme.sh git clone
        acme.sh                ← acme.sh main script
        dnsapi/                ← acme.sh DNS provider scripts
          dns_dynu.sh
          dns_cf.sh
          dns_hetzner.sh
          ...
      truenas-acme-shell/      ← this repo
        acmeShellAuth.sh       ← wrapper script
        credentials            ← provider config & secrets
        README.md

The wrapper automatically finds acme.sh based on this layout.

---

## ⚙️ How TrueNAS Calls the Script

TrueNAS Shell ACME DNS Authenticators call the script like this:

    acmeShellAuth.sh set   DOMAIN FQDN TOKEN
    acmeShellAuth.sh unset DOMAIN FQDN TOKEN

Example:

    /path/to/truenas-acme-shell/acmeShellAuth.sh \
      set example.com _acme-challenge.example.com abc123

The wrapper then:

1. Resolves acme.sh paths relative to its own directory.  
2. Loads `credentials` to determine:  
   - which provider to use (e.g. `dns_dynu`, `dns_cf`, `dns_hetzner`)  
   - provider-specific secrets (API tokens, OAuth client IDs, …)  
3. Sources `acme.sh` (for helper functions).  
4. Sources the provider script, e.g. `dns_dynu.sh`.  
5. Calls the correct function:  
   - on `set` → `${PROVIDER}_add "$FQDN" "$TOKEN"`  
   - on `unset` → `${PROVIDER}_rm "$FQDN" "$TOKEN"`  
6. Returns the provider function’s exit code to TrueNAS.

---

## 🔐 `credentials` File

The wrapper reads configuration & secrets from a file named:

    /path/to/truenas-acme-shell/credentials

This file must be **valid shell syntax** (it is sourced with `.`) and should be readable only by the user that runs the script (`chmod 600 credentials` is recommended).

### Dynu Example (dns_dynu)

    # /path/to/truenas-acme-shell/credentials

    PROVIDER="dns_dynu"

    # Required by acme.sh dns_dynu
    Dynu_ClientId="YOUR_DYNU_OAUTH_CLIENT_ID"
    Dynu_Secret="YOUR_DYNU_OAUTH_CLIENT_SECRET"

    # Optional:
    # Dynu_Token="..."
    # Dynu_EndPoint="https://api.dynu.com/v2"

### Cloudflare Example (dns_cf)

    PROVIDER="dns_cf"

    CF_Token="YOUR_CLOUDFLARE_API_TOKEN"

### Hetzner Example (dns_hetzner)

    PROVIDER="dns_hetzner"

    HETZNER_Token="YOUR_HETZNER_DNS_API_TOKEN"

For other providers, see the acme.sh dnsapi documentation:  
https://github.com/acmesh-official/acme.sh/wiki/dnsapi

---

## 👤 Recommended Service User (`acme`)

For security, it’s better **not** to run the script as `root` if you don’t have to.

### Option A (recommended): Dedicated `acme` user

1. Create a user in the TrueNAS UI (CORE/SCALE):  
   - **Name:** `acme`  
   - No SSH / no shell login required (service-style user).  

2. Make sure `acme` can read the wrapper and credentials:

    chown acme:acme /path/to/truenas-acme-shell/credentials
    chmod 600 /path/to/truenas-acme-shell/credentials

   The script itself can stay owned by any user as long as it’s executable:

    chmod 755 /path/to/truenas-acme-shell/acmeShellAuth.sh

3. Ensure `acme` has read/execute access to the acme.sh directory:

    # simplest: keep git clone with world-read/execute
    chmod -R a+rX /path/to/acme.sh

(You can tighten this further if desired, as long as the `acme` user can still read the needed files.)

You can then select `acme` as **Run As User** in the TrueNAS authenticator.

### Option B: Use `root`

If you don’t want to create a dedicated user:

- Set **Run As User:** `root` in the TrueNAS authenticator.  
- Make sure `credentials` is owned by and readable only for root:

    chown root:root /path/to/truenas-acme-shell/credentials
    chmod 600 /path/to/truenas-acme-shell/credentials

This is simpler but grants the script full root privileges.

---

## 🛠️ TrueNAS Setup

### 1. Add the Shell ACME DNS Authenticator

In the TrueNAS UI:

1. Open **ACME DNS-Authenticators → Add** (location and naming vary slightly between CORE and SCALE).  
2. Configure:
   - **Name:** e.g. `acmesh-shell`  
   - **Authenticator:** `Shell`  
   - **Script path:**  
     `/path/to/truenas-acme-shell/acmeShellAuth.sh`  
   - **Run As User:**  
     - recommended: `acme` (dedicated user as described above)  
     - alternative: `root`  
   - **Timeout:** `600`  
     - This is how long TrueNAS will wait for each `set`/`unset` call.  
     - 600 seconds (10 minutes) is a safe default; typical DNS API calls finish in a few seconds.  
   - **Propagation Delay:** `120` (or `180` if you want extra margin)  
     - This is how long TrueNAS waits *after* `set` returns before doing the DNS-01 check.  
     - 120–180 seconds avoids random validation failures when DNS propagation is slightly delayed.

No environment variables are required in the TrueNAS UI; the script reads everything from `credentials`.

---

### 2. Use the Authenticator in an ACME Certificate

1. Go to **Certificates**.  
2. Create a CSR if needed.  
3. Use the **Create ACME Certificate** option for that CSR.  
4. Configure:
   - ACME directory (Let’s Encrypt):  
     `https://acme-v02.api.letsencrypt.org/directory`  
   - Email, private key, etc.  
   - Domains: `example.com`, `*.example.com`, etc.  
5. For each domain entry, choose:
   - **DNS Authenticator → your Shell authenticator** (e.g. `acmesh-shell`)  
6. Save and run the task.

TrueNAS will call `acmeShellAuth.sh set` / `unset` as needed to complete the DNS-01 challenge.

---

## 🧪 Manual Testing (Optional)

You can test outside of TrueNAS:

    cd /path/to/truenas-acme-shell

    # TXT add
    ./acmeShellAuth.sh set example.com _acme-challenge.example.com testtoken123

    # Check via DNS:
    dig TXT _acme-challenge.example.com +short

    # TXT remove
    ./acmeShellAuth.sh unset example.com _acme-challenge.example.com testtoken123

If there’s a problem, check `acmeShellAuth.log` in the same directory.

---

## ❓ Why `source` acme.sh instead of executing it?

acme.sh serves two roles:

- Command-line client for issuing certificates.  
- Library of shell functions + dnsapi modules.  

TrueNAS already manages the certificate issuance; this wrapper only needs DNS TXT record manipulation.

So the script uses acme.sh in **library mode** (conceptually):

    . /path/to/acme.sh/acme.sh
    . /path/to/acme.sh/dnsapi/dns_dynu.sh   # or dns_cf.sh, dns_hetzner.sh, …

    dns_dynu_add "$FQDN" "$TOKEN"
    dns_dynu_rm  "$FQDN" "$TOKEN"

This is the same pattern used in community HOWTOs for TrueNAS + acme.sh.

---

## 📝 License

- **Wrapper script (`acmeShellAuth.sh`) and this repository:**  
  Licensed under the **GNU General Public License v3.0 (GPLv3)**.

- **acme.sh:**  
  A separate project under **GPLv3**, developed and maintained upstream:  
  https://github.com/acmesh-official/acme.sh

Review both licenses if you redistribute or modify this wrapper together with acme.sh.
