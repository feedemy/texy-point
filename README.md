# TexyPoint

Distribution and one-line installer for the TexyPoint **access point** firmware —
NFC / QR / BLE door access, IP-camera (WebRTC + license-plate recognition), and
GPIO / Modbus relay control on a single cross-platform binary.

> This repository ships **release artifacts and the installer only** — no source code.
> Every release is **signed** (p256); the installer verifies the signature before installing.

---

## Install (one line)

### Linux — x86_64, or ARM (Raspberry Pi 5 / Pi Zero 2W)

```bash
curl -fsSL https://raw.githubusercontent.com/feedemy/texy-point/main/install.sh | bash
```

### Windows — x86_64

```powershell
irm https://raw.githubusercontent.com/feedemy/texy-point/main/install.ps1 | iex
```

The installer detects your platform, downloads the latest release, **verifies its
p256 signature against an embedded public key**, then installs it (slot layout +
service registration + adds `texpass-ap` to PATH). Re-running it upgrades in place.

After install, open a new terminal:

```bash
texpass-ap --help
```

---

## Choosing a build (variants)

The default build is the lightweight core (safe for Pi Zero). Pick a variant if your
hardware needs it:

```bash
# Linux — camera/ANPR (Pi 5 / x86_64) OR on-board NFC+QR reader (Pi Zero / Pi 5)
curl -fsSL https://raw.githubusercontent.com/feedemy/texy-point/main/install.sh | bash -s -- --variant camera
curl -fsSL https://raw.githubusercontent.com/feedemy/texy-point/main/install.sh | bash -s -- --variant internal-reader
```

```powershell
# Windows — camera/ANPR
$env:TEXYPOINT_VARIANT='camera'; irm https://raw.githubusercontent.com/feedemy/texy-point/main/install.ps1 | iex
```

| Variant | What it adds | Where it runs |
|---|---|---|
| **default** | Core: WiFi reader (TCP+AES), Modbus-TCP relay, BLE, pairing, hub, access engine, OTA. | All platforms (Pi Zero-safe). |
| **camera** | RTSP cameras (ONVIF discovery + decode), motion detection, **WebRTC** live view, **license-plate recognition (ANPR)**. | Linux x86_64 / Pi 5, Windows. **Not** Pi Zero. |
| **internal-reader** | On-board **NFC (PN532)** + **QR (GM67)** + RGB status LED + buzzer wired to the device. | **Linux only** (hardware drivers). |

---

## What each capability does

- **WiFi reader (TexyW, TCP+AES)** — talks to Pico W door readers over an encrypted TCP protocol. *(all platforms)*
- **BLE** — scans Bluetooth Low Energy for proximity/credential beacons; drives per-door BLE lifecycle. *(Linux)*
- **On-board reader (internal-reader)** — NFC tap + QR scan + LED/buzzer feedback directly on the unit, no external reader. *(Linux)*
- **Relay control** — unlocks doors via **GPIO** (wired, Linux) or **Modbus-TCP** (networked relay board, all platforms).
- **Camera / WebRTC / ANPR** — pulls RTSP streams, gates on motion, serves low-latency WebRTC, and reads license plates on the edge. *(Linux/Windows, not Pi Zero)*
- **Pairing / hub / access engine / OTA** — backend pairing, real-time hub link, online access decisions, and signed blue-green over-the-air updates. *(all platforms)*

---

## Platform support

| Capability | Linux x86_64 | Linux ARM — Pi 5 | Linux ARM — Pi Zero 2W | Windows x86_64 |
|---|:---:|:---:|:---:|:---:|
| Core (WiFi reader, hub, access, OTA) | ✅ | ✅ | ✅ | ✅ |
| BLE scanning | ✅ | ✅ | ✅ | ❌ (stub / no scan) |
| On-board NFC + QR + LED (`internal-reader`) | ✅ | ✅ | ✅ | ❌ (Linux-only HW) |
| GPIO relay | ✅ | ✅ | ✅ | ❌ |
| Modbus-TCP relay | ✅ | ✅ | ✅ | ✅ |
| Camera / WebRTC / ANPR (`camera`) | ✅ | ✅ | ❌ (too heavy) | ✅ |

**Not available on Windows:** BLE scanning (no-op stub), the on-board `internal-reader`
hardware (drivers are Linux-only), and GPIO relays — use a **Modbus-TCP** relay instead.
Everything else (WiFi readers, camera/WebRTC/ANPR, hub, access, OTA) works on Windows.

> macOS is **not** a supported deployment target.

---

## Verifying a download yourself

Each release archive contains `SHA256SUMS`, its detached p256 signature `SHA256SUMS.sig`,
and the public keys under `release-pubkeys/`. The signing **private key is kept offline**
and never leaves the build machine, so a signature cannot be forged.

```bash
# integrity
sha256sum -c SHA256SUMS
# authenticity (signature)
openssl dgst -sha256 -verify release-pubkeys/prod.pem -signature SHA256SUMS.sig SHA256SUMS
```

The bundled installer and the OTA updater both verify this signature automatically;
installation/updates are refused if it does not check out.

---

## Uninstall

```bash
texpass-ap uninstall            # remove service + PATH entry
texpass-ap uninstall --purge    # also remove local state/config
```

---

## Releases

See the [Releases](https://github.com/feedemy/texy-point/releases) page for versioned
archives per platform and variant (`.tar.gz` for Linux, `.zip` for Windows).
