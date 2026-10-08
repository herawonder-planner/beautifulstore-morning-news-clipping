param([Parameter(Mandatory)][string]$Summary)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:pass = 0
$script:fail = 0
function Check([bool]$ok, [string]$msg) {
    if ($ok) { Write-Host "[PASS] $msg"; $script:pass++ }
    else { Write-Host "[FAIL] $msg"; $script:fail++ }
}
function Normalize([string]$s) {
    $s = $s -replace '[“”‘’"'']', ''
    $s = $s -replace '\s+', ' '
    return $s.Trim()
}

if (-not (Test-Path -LiteralPath $Summary)) {
    Write-Host "[FAIL] 요약 파일이 없습니다: $Summary"
    Write-Host "결과: 통과 0 / 실패 1"
    exit 1
}
$lines = @(Get-Content -LiteralPath $Summary -Encoding UTF8)
$dir = Split-Path -Parent (Resolve-Path -LiteralPath $Summary).Path

function MetaValue([string]$key) {
    foreach ($l in $lines) {
        if ($l -match ('^\s*-\s*' + [regex]::Escape($key) + '\s*:\s*(.+?)\s*$')) { return $Matches[1] }
    }
    return $null
}

$h1 = $lines | Where-Object { $_ -match '^# \S' } | Select-Object -First 1
Check ($null -ne $h1) 'H1 제목이 있다'
$status = MetaValue '상태'
$data = MetaValue '데이터'
$url = MetaValue 'URL'
$when = MetaValue '확인 시각'
Check ($null -ne $status) '메타: 상태 줄이 있다'
Check ($null -ne $data) '메타: 데이터 줄이 있다'
Check ($null -ne $url) '메타: URL 줄이 있다'
Check ($null -ne $when) '메타: 확인 시각 줄이 있다'
Check (($data -eq '실보도') -or ($data -eq '가상 예시')) "데이터 값이 '실보도' 또는 '가상 예시'이다 (값: $data)"
if ($data -eq '가상 예시') {
    Check ($h1 -like '# `[가상 예시`]*') '가상 예시이므로 제목에 [가상 예시]가 있다'
}

$hasSummarySection = [bool]($lines | Where-Object { $_ -match '^## 3줄 요약\s*$' })

if ($status -like '✅*') {
    $press = MetaValue '언론사'
    $pub = MetaValue '발행일'
    $srcName = MetaValue '원문 저장'
    Check ($null -ne $press) '성공: 언론사 줄이 있다'
    Check ($null -ne $pub) '성공: 발행일 줄이 있다'
    Check ($null -ne $srcName) '성공: 원문 저장 줄이 있다'
    Check $hasSummarySection '성공: "## 3줄 요약" 섹션이 있다'

    # 요약 섹션 파싱
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## 3줄 요약\s*$') { $start = $i; break } }
    $items = @()   # 각 항목: 번호줄 인덱스
    if ($start -ge 0) {
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^## ') { break }
            if ($lines[$i] -match '^\d+\.\s+\S') { $items += $i }
        }
    }
    Check ($items.Count -eq 3) "번호 항목이 정확히 3개이다 (현재 $($items.Count)개)"

    $source = $null
    if ($srcName) {
        $srcPath = Join-Path $dir $srcName
        if (Test-Path -LiteralPath $srcPath) {
            $source = Normalize ((Get-Content -LiteralPath $srcPath -Encoding UTF8) -join "`n")
            Check $true "원문 저장 파일을 읽었다 ($srcName)"
        } else {
            Check $false "원문 저장 파일이 같은 폴더에 있다 ($srcName)"
        }
    }

    $n = 0
    foreach ($idx in $items) {
        $n++
        $next = if ($idx + 1 -lt $lines.Count) { $lines[$idx + 1] } else { '' }
        if ($next -match '^\s*>\s*근거:\s*["“](.+)["”]\s*$') {
            $quote = $Matches[1]
            Check $true "항목 ${n}: 바로 다음 줄에 근거 인용이 있다"
            $q = Normalize $quote
            Check ($q.Length -ge 20) "항목 ${n}: 근거가 20자 이상이다 ($($q.Length)자)"
            if ($null -ne $source) {
                Check ($source.Contains($q)) "항목 ${n}: 근거가 원문 본문에 글자 그대로 있다"
            }
        } else {
            Check $false "항목 ${n}: 바로 다음 줄에 > 근거: `"...`" 가 있다"
        }
    }
}
elseif ($status -like '❌*') {
    Check (-not $hasSummarySection) '실패: "## 3줄 요약" 섹션이 없다'
    Check ($status -match '\(사유:\s*\S.*\)') '실패: 사유 괄호가 있다'
}
elseif ($null -ne $status) {
    Check $false "상태 값을 알 수 없다 (값: $status)"
}

Write-Host "결과: 통과 $($script:pass) / 실패 $($script:fail)"
if ($script:fail -gt 0) { exit 1 }
