<#
.SYNOPSIS
    TexyPoint — one-line installer (Windows x86_64).

.DESCRIPTION
    Run:
        irm https://raw.githubusercontent.com/feedemy/texy-point/main/install.ps1 | iex

    Pick a variant (camera/ANPR) before piping:
        $env:TEXYPOINT_VARIANT='camera'; irm https://raw.githubusercontent.com/feedemy/texy-point/main/install.ps1 | iex

    Served over HTTPS (raw.githubusercontent) — that is the trust root. Downloads the
    latest release, VERIFIES its signature (p256) against the EMBEDDED public key, and
    installs it. Requires administrator (the bundled installer registers a service).
#>
$ErrorActionPreference = 'Stop'

$Repo    = 'feedemy/texy-point'
$Variant = if ($env:TEXYPOINT_VARIANT) { $env:TEXYPOINT_VARIANT } else { 'default' }

# ── Trust root: prod release public key (SPKI PEM) ────────────────────────────
# Used only to VERIFY signatures — it cannot PRODUCE them (private key is offline).
# Since this script is HTTPS-served, the trust root lives here; the downloaded
# package's signature is checked against it before anything is installed.
$ProdPubkeyPem = @'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEY61dkq1+/awxVJhauo6doSg1+xr4
1lj/rbw5If5YLFJwXg4M+U6iFqtfYUasgDqiTJ2zwOk/4SjGJPs+QMuaNQ==
-----END PUBLIC KEY-----
'@

function Info { param($m) Write-Host ":: $m" -ForegroundColor Cyan }
function Warn { param($m) Write-Host "WARNING: $m" -ForegroundColor Yellow }
function Die  { param($m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# The camera variant decodes RTSP via the system `ffmpeg` binary (subprocess). We do
# NOT bundle ffmpeg (keeps the distribution license-clean); install it via winget if
# missing. If winget is unavailable we warn (camera won't decode until ffmpeg is added).
function Install-Ffmpeg {
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { Info "ffmpeg already present"; return }
    Info "camera variant requires ffmpeg — installing via winget..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --exact --id Gyan.FFmpeg --silent `
                --accept-source-agreements --accept-package-agreements | Out-Null
        } catch { Warn "winget install failed: $_" }
        if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { Info "ffmpeg ready" }
        else { Warn "ffmpeg installed but not on PATH in this session — available after a new terminal / service restart" }
    } else {
        Warn "winget not available — install ffmpeg manually (https://ffmpeg.org); the camera variant will not decode until then"
    }
}

# ── Privilege check (up front, before downloading) ────────────────────────────
# Installing registers a Windows service and writes to machine paths, so it
# requires administrator. Check now so we fail with clear guidance BEFORE
# downloading, instead of midway through the bundled installer.
$principal = [System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "administrator required. Open PowerShell as Administrator (right-click -> 'Run as administrator'), then run the one-liner again."
}

# ── Platform → target triple ──────────────────────────────────────────────────
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne 'AMD64') { Die "unsupported architecture: $arch (x86_64/AMD64 supported)" }
$target = 'x86_64-pc-windows-msvc'
$suffix = if ($Variant -ne 'default') { "-$Variant" } else { '' }

# ── Resolve latest release + download ─────────────────────────────────────────
Info "querying latest release ($Repo)..."
try {
    $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'texypoint-installer' }
} catch { Die "failed to query latest release (network?): $_" }
$tag = $rel.tag_name
if (-not $tag) { Die "no latest release found — none may be published yet" }

$asset = "texpass-ap-$tag-$target$suffix.zip"
$url    = "https://github.com/$Repo/releases/download/$tag/$asset"
$tmp    = Join-Path $env:TEMP ("texypoint-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    Info "downloading: $asset  ($tag)"
    try { Invoke-WebRequest $url -OutFile (Join-Path $tmp $asset) -Headers @{ 'User-Agent' = 'texypoint-installer' } }
    catch { Die "download failed: $url  (does variant '$Variant' exist in this release?)" }

    Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath $tmp -Force
    $dir = Join-Path $tmp "texpass-ap-$tag-$target$suffix"
    if (-not (Test-Path $dir)) {
        $dir = (Get-ChildItem -Path $tmp -Directory -Filter 'texpass-ap-*' | Select-Object -First 1).FullName
    }
    $sumsFile = Join-Path $dir 'SHA256SUMS'
    $sigFile  = Join-Path $dir 'SHA256SUMS.sig'
    if (-not ((Test-Path $sumsFile) -and (Test-Path $sigFile))) {
        Die "package contents incomplete (missing SHA256SUMS / .sig) — corrupt or unsigned release"
    }

    # ── Verify signature (embedded trust root) ────────────────────────────────
    Info "verifying signature (p256, embedded public key)..."
    $sums = [System.IO.File]::ReadAllBytes($sumsFile)
    $sig  = [System.IO.File]::ReadAllBytes($sigFile)
    $sigOk = $false
    # Method 1: .NET 5+ (PowerShell 7) — ImportFromPem + DER signature format.
    try {
        $ec = [System.Security.Cryptography.ECDsa]::Create()
        $ec.ImportFromPem($ProdPubkeyPem)
        $alg = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        $fmt = [System.Security.Cryptography.DSASignatureFormat]::Rfc3279DerSequence
        $sigOk = $ec.VerifyData($sums, $sig, $alg, $fmt)
    } catch {
        # Method 2 (Windows PowerShell 5.1 — APIs above unavailable): openssl fallback.
        if (Get-Command openssl -ErrorAction SilentlyContinue) {
            $pemPath = Join-Path $tmp 'trust.pem'
            [System.IO.File]::WriteAllText($pemPath, $ProdPubkeyPem)
            & openssl dgst -sha256 -verify $pemPath -signature $sigFile $sumsFile *> $null
            if ($LASTEXITCODE -eq 0) { $sigOk = $true }
        } else {
            Die "cannot verify signature: PowerShell 7+ or openssl required (you are on $($PSVersionTable.PSVersion))"
        }
    }
    if (-not $sigOk) { Die "SIGNATURE VERIFICATION FAILED — package is not trusted (tampered/forged), aborting" }
    Info "signature verified"

    # Camera variant needs ffmpeg at runtime — ensure it before handing off.
    if ($Variant -eq 'camera') { Install-Ffmpeg }

    # ── Install (delegate to bundled installer: checksum + slot + service) ────
    Info "installing (requires administrator)..."
    & (Join-Path $dir 'install.ps1')
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { Die "bundled installer failed (exit $LASTEXITCODE)" }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Info "Installation complete. Open a new PowerShell window → 'texpass-ap --help'"
