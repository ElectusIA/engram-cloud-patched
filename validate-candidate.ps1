[CmdletBinding()]
param([string]$GoBinary = '')
$ErrorActionPreference = 'Continue' # Native Go progress uses stderr in Windows PowerShell 5.1; check exit codes explicitly.
$candidateRoot = $PSScriptRoot
$env:GOPATH = Join-Path $candidateRoot '.tools/gopath'
$env:GOCACHE = Join-Path $candidateRoot '.tools/gocache'
$env:GOTOOLCHAIN = 'local'
$env:ENGRAM_DATA_DIR = Join-Path $candidateRoot 'artifacts/data'
# t.TempDir() follows TMP/TEMP. GitHub Windows runners expose TEMP in 8.3 form (RUNNER~1 instead of runneradmin) while v3
# canonicalizes paths with filepath.EvalSymlinks (long form), so path assertions would compare two spellings.
# RUNNER_TEMP is a long path outside any git checkout (v3 project detection walks up to the git root).
if ($env:RUNNER_TEMP) {
    $env:TMP = $env:RUNNER_TEMP
    $env:TEMP = $env:RUNNER_TEMP
}
foreach ($tempVar in @('TMP', 'TEMP')) {
    $tempValue = [Environment]::GetEnvironmentVariable($tempVar)
    if ($tempValue -and $tempValue.Contains('~')) { throw "$tempVar is an 8.3 short path; point TMP and TEMP to a long path outside any git checkout" }
}
$env:CLOUDSTORE_TEST_DSN = ''
$env:ENGRAM_CLOUD_TOKEN = ''
$env:ENGRAM_CLOUD_SERVER = ''
$env:ENGRAM_CLOUD_AUTOSYNC = ''
$env:ENGRAM_DATABASE_URL = ''
if (-not $GoBinary) { $GoBinary = Join-Path $candidateRoot '.tools/go/bin/go.exe' }
if (-not (Test-Path -LiteralPath $GoBinary)) { throw 'Provide -GoBinary pointing to Go 1.25.10; see README toolchain checksum.' }
$goBinary = (Resolve-Path -LiteralPath $GoBinary).Path
if (-not (Test-Path (Join-Path $candidateRoot 'upstream/.git'))) {
    & git clone --depth 1 --branch v3.0.0 https://github.com/Gentleman-Programming/engram.git (Join-Path $candidateRoot 'upstream')
    if ($LASTEXITCODE -ne 0) { throw 'Upstream clone failed' }
}
$upstreamCommit = & git -C (Join-Path $candidateRoot 'upstream') rev-parse HEAD
if ($upstreamCommit -ne '15a2f78885d7ad8ced23b2d1d88383e9bb472c17') { throw 'Unexpected upstream revision; preserved checkout' }
# v3.0.0 admits the boolean issued_token upstream (auditKeyValueExempt): no source patch; electus_patch_test.go is a regression.
Copy-Item -LiteralPath (Join-Path $candidateRoot 'tests/electus_patch_test.go') -Destination (Join-Path $candidateRoot 'upstream/internal/cloud/cloudstore/electus_patch_test.go') -ErrorAction Stop
Copy-Item -LiteralPath (Join-Path $candidateRoot 'tests/store_cleanup_test.go') -Destination (Join-Path $candidateRoot 'upstream/internal/store/electus_cleanup_test.go') -ErrorAction Stop
Copy-Item -LiteralPath (Join-Path $candidateRoot 'tests/health_metadata.go') -Destination (Join-Path $candidateRoot 'upstream/internal/cloud/cloudserver/electus_metadata.go') -ErrorAction Stop
Copy-Item -LiteralPath (Join-Path $candidateRoot 'tests/health_metadata_test.go') -Destination (Join-Path $candidateRoot 'upstream/internal/cloud/cloudserver/electus_metadata_test.go') -ErrorAction Stop
# relations-fixture, store-constructor-cleanup and windows-test-fixtures left: v3.0.0 ships equivalent upstream code.
foreach ($overlay in @('health-metadata.patch')) {
$fixturePatch = Join-Path $candidateRoot "tests/$overlay"
& git -C (Join-Path $candidateRoot 'upstream') apply --check $fixturePatch 2>$null
if ($LASTEXITCODE -eq 0) {
    & git -C (Join-Path $candidateRoot 'upstream') apply $fixturePatch
    if ($LASTEXITCODE -ne 0) { throw 'Fixture patch failed' }
} else {
    & git -C (Join-Path $candidateRoot 'upstream') apply --reverse --check $fixturePatch 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Unexpected overlay state; preserved checkout' }
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
    # v3 store and mcp suites are much larger than in 1.20 (about 5 and 3 minutes on a GitHub Windows runner).
    & $goBinary test ./internal/cloud/... ./internal/store ./internal/mcp -count=1 -timeout 20m -json *> ../artifacts/go-tests.jsonl
    if ($LASTEXITCODE -ne 0) { throw 'Go tests failed; see artifacts/go-tests.jsonl' }
    $env:CGO_ENABLED = '0'
    & $goBinary build '-ldflags=-s -w -X main.version=v3.0.0-electus-patch3' -o ../artifacts/engram-candidate.exe ./cmd/engram
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    & ../artifacts/engram-candidate.exe version
    if ($LASTEXITCODE -ne 0) { throw 'Candidate version probe failed' }
    $env:GOOS = 'linux'
    $env:GOARCH = 'amd64'
    & $goBinary build '-ldflags=-s -w -X main.version=v3.0.0-electus-patch3' -o ../artifacts/engram-linux-amd64 ./cmd/engram
    if ($LASTEXITCODE -ne 0) { throw 'Linux build failed' }
    Get-FileHash ../artifacts/engram-candidate.exe,../artifacts/engram-linux-amd64 -Algorithm SHA256 | Format-Table -AutoSize
} finally { Pop-Location }
