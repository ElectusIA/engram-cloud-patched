[CmdletBinding()]
param([string]$GoBinary = '')
$ErrorActionPreference = 'Continue' # Native Go progress uses stderr in Windows PowerShell 5.1; check exit codes explicitly.
$candidateRoot = $PSScriptRoot
$env:GOPATH = Join-Path $candidateRoot '.tools/gopath'
$env:GOCACHE = Join-Path $candidateRoot '.tools/gocache'
$env:GOTOOLCHAIN = 'local'
$env:ENGRAM_DATA_DIR = Join-Path $candidateRoot 'artifacts/data'
$env:CLOUDSTORE_TEST_DSN = ''
$env:ENGRAM_CLOUD_TOKEN = ''
$env:ENGRAM_CLOUD_SERVER = ''
$env:ENGRAM_CLOUD_AUTOSYNC = ''
$env:ENGRAM_DATABASE_URL = ''
if (-not $GoBinary) { $GoBinary = Join-Path $candidateRoot '.tools/go/bin/go.exe' }
if (-not (Test-Path -LiteralPath $GoBinary)) { throw 'Provide -GoBinary pointing to Go 1.25.10; see README toolchain checksum.' }
$goBinary = (Resolve-Path -LiteralPath $GoBinary).Path
if (-not (Test-Path (Join-Path $candidateRoot 'upstream/.git'))) {
    & git clone --depth 1 --branch v1.20.0 https://github.com/Gentleman-Programming/engram.git (Join-Path $candidateRoot 'upstream')
    if ($LASTEXITCODE -ne 0) { throw 'Upstream clone failed' }
}
$upstreamCommit = & git -C (Join-Path $candidateRoot 'upstream') rev-parse HEAD
if ($upstreamCommit -ne 'ba9e46ced152c37a7cb9e576153c41995873e2fc') { throw 'Unexpected upstream revision; preserved checkout' }
$patchFile = Join-Path $candidateRoot 'upstream/internal/cloud/cloudstore/identity.go'
$before = [IO.File]::ReadAllText($patchFile)
$after = $before.Replace('if key == "token_prefix" {', 'if key == "token_prefix" || key == "issued_token" {')
if (-not $after.Contains('if key == "token_prefix" || key == "issued_token" {')) { throw 'Patch precondition failed' }
[IO.File]::WriteAllText($patchFile, $after, (New-Object Text.UTF8Encoding $false))
Copy-Item -LiteralPath (Join-Path $candidateRoot 'tests/electus_patch_test.go') -Destination (Join-Path $candidateRoot 'upstream/internal/cloud/cloudstore/electus_patch_test.go') -ErrorAction Stop
Copy-Item -LiteralPath (Join-Path $candidateRoot 'tests/store_cleanup_test.go') -Destination (Join-Path $candidateRoot 'upstream/internal/store/electus_cleanup_test.go') -ErrorAction Stop
foreach ($overlay in @('relations-fixture.patch', 'store-constructor-cleanup.patch', 'windows-test-fixtures.patch')) {
$fixturePatch = Join-Path $candidateRoot "tests/$overlay"
& git -C (Join-Path $candidateRoot 'upstream') apply --check $fixturePatch 2>$null
if ($LASTEXITCODE -eq 0) {
    & git -C (Join-Path $candidateRoot 'upstream') apply $fixturePatch
    if ($LASTEXITCODE -ne 0) { throw 'Fixture patch failed' }
} else {
    & git -C (Join-Path $candidateRoot 'upstream') apply --reverse --check $fixturePatch 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Unexpected relation fixture; preserved checkout' }
}
}
New-Item -ItemType Directory -Path (Join-Path $candidateRoot 'artifacts') -Force -ErrorAction Stop | Out-Null
Push-Location (Join-Path $candidateRoot 'upstream')
try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    if (Test-Path ../artifacts/go-tests.jsonl) {
        Copy-Item ../artifacts/go-tests.jsonl ("../artifacts/go-tests.previous-{0}.jsonl" -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')) -ErrorAction Stop
    }
    & $goBinary test ./internal/cloud/... ./internal/store ./internal/mcp -count=1 -json *> ../artifacts/go-tests.jsonl
    if ($LASTEXITCODE -ne 0) { throw 'Go tests failed; see artifacts/go-tests.jsonl' }
    $env:CGO_ENABLED = '0'
    & $goBinary build '-ldflags=-s -w -X main.version=v1.20.0-electus-patch1' -o ../artifacts/engram-candidate.exe ./cmd/engram
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    & ../artifacts/engram-candidate.exe version
    if ($LASTEXITCODE -ne 0) { throw 'Candidate version probe failed' }
    $env:GOOS = 'linux'
    $env:GOARCH = 'amd64'
    & $goBinary build '-ldflags=-s -w -X main.version=v1.20.0-electus-patch1' -o ../artifacts/engram-linux-amd64 ./cmd/engram
    if ($LASTEXITCODE -ne 0) { throw 'Linux build failed' }
    Get-FileHash ../artifacts/engram-candidate.exe,../artifacts/engram-linux-amd64 -Algorithm SHA256 | Format-Table -AutoSize
} finally { Pop-Location }
