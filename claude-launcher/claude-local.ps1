# ============================================================
#  Завантаження ключів з окремого файлу
# ============================================================
$keysFile = Join-Path $PSScriptRoot "keys.ps1"
if (-not (Test-Path $keysFile)) {
    Write-Host "Файл keys.ps1 не знайдено поруч зі скриптом!" -ForegroundColor Red
    exit 1
}
. $keysFile

# ============================================================
#  ХМАРНІ провайдери
# ============================================================
$cloud = @(
    @{
        label   = "OpenRouter — poolside/laguna-xs.2:free"
        baseUrl = "https://openrouter.ai/api/v1"
        token   = $OPENROUTER_KEY
        model   = "poolside/laguna-xs.2:free"
    }
    @{
        label   = "OpenRouter — poolside/laguna-m.1:free"
        baseUrl = "https://openrouter.ai/api/v1"
        token   = $OPENROUTER_KEY
        model   = "poolside/laguna-m.1:free"
    }
    @{
        label   = "OpenRouter — nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
        baseUrl = "https://openrouter.ai/api/v1"
        token   = $OPENROUTER_KEY
        model   = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
    }
    @{
        label   = "OpenRouter — openrouter/owl-alpha"
        baseUrl = "https://openrouter.ai/api/v1"
        token   = $OPENROUTER_KEY
        model   = "openrouter/owl-alpha"
    }
    @{
        label   = "Groq — llama-3.3-70b-versatile"
        baseUrl = "https://api.groq.com/openai/v1"
        token   = $GROQ_KEY
        model   = "llama-3.3-70b-versatile"
    }
    @{
        label   = "Groq — qwen/qwen3-32b"
        baseUrl = "https://api.groq.com/openai/v1"
        token   = $GROQ_KEY
        model   = "qwen/qwen3-32b"
    }
)

# ============================================================
#  ЛОКАЛЬНІ моделі
#  Оптимізовано за бенчмарками (bench_results_4_model_test1.csv)
# ============================================================
$local = @(
    @{
        # ~60 t/s, легка — ідеальна для /init і швидкого коду
        label  = "qwen2.5-coder-7b-instruct-q5  [60+ t/s, кодинг, /init]"
        name   = "qwen2.5-coder-7b-instruct-q5_k_m"
        dir    = "J:\LLM\models"
        ngl    = 999
        ncmoe  = 0
        ub     = 512
        b      = 512
        extra  = ""
    }
    @{
        # ~32 t/s, мультимодальна, ncmoe=30 за бенчами (+1% vs 25)
        label  = "Gemma-4 26B-A4B MXFP4 MoE  [32 t/s, мультимодальна]"
        name   = "gemma-4-26B-A4B-it-MXFP4_MOE_F16"
        dir    = "J:\LLM\models"
        ngl    = 999
        ncmoe  = 30
        ub     = 512
        b      = 512
        extra  = "--flash-attn 1 --temp 0.7 --top-p 0.8 --top-k 20 --presence-penalty 0.0 --repeat-penalty 1.0"
    }
    @{
        # Q4_K_M ~14GB, стандартний запуск (RotorQuant KV потребує окремого форку)
        # RotorQuant fork: github.com/johndpope/llama-cpp-turboquant
        label  = "Gemma-4 26B-A4B RotorQuant Q4_K_M  [~14GB, alt quant]"
        name   = "gemma-4-26B-A4B-RotorQuant-Q4_K_M"
        dir    = "J:\LLM\models"
        ngl    = 999
        ncmoe  = 30
        ub     = 512
        b      = 512
        # Стандартний режим (без iso3 — потребує спеціальний форк)
        # Для RotorQuant KV: замінити на --ctk iso3 --ctv iso3 після збірки форку
        extra  = "--flash-attn 1 --temp 0.7 --top-p 0.8 --top-k 20"
    }
    @{
        # ~5 t/s — занадто повільна для агентського режиму!
        # Використовувати тільки для аналізу/читання в режимі [3]
        label  = "⚠️  DS4X8R1L3.1 24B IQ4_XS  [~5 t/s! тільки аналіз]"
        name   = "DS4X8R1L3.1-Dp-Thnkr-UnC-24B-D_AU-IQ4_XS"
        dir    = "J:\LLM\models"
        ngl    = 999
        ncmoe  = 0
        ub     = 512
        b      = 512
        extra  = "--temp 0.6 --top-p 0.9 --repeat-penalty 1.05"
    }
    @{
        # ~20 t/s, ncmoe=0 (override-kv), creative/uncensored
        label  = "L3.2 8x4B MoE 21B IQ4_XS  [~20 t/s, uncensored]"
        name   = "L3.2-8X4B-MOE-V2-Dark-Champion-Inst-21B-uncen-ablit-D_AU-IQ4_XS"
        dir    = "J:\LLM\models"
        ngl    = 999
        ncmoe  = 0
        ub     = 512
        b      = 512
        extra  = "--override-kv llama.expert_used_count=int:4 --temp 0.8 --repeat-penalty 1.02"
    }
    @{
        # ncmoe=33 (за бенчем твого заліза 8GB — залишаємо 33 для Qwen3.6)
        # --reasoning-budget 0 вимикає thinking (стаття: fast > thinking для коду)
        label  = "Qwen3.6 35B-A3B MXFP4 MoE  [reasoning, fast mode]"
        name   = "Qwen3.6-35B-A3B-MXFP4_MOE"
        dir    = "J:\LLM\models"
        ngl    = 99
        ncmoe  = 33
        ub     = 2048
        b      = 2048
        extra  = "--reasoning-budget 0 --reasoning off --temp 0.7"
    }
    @{
        # ~46 t/s з ncmoe=30 — найкращий результат за бенчами
        label  = "Qwopus MoE 35B-A3B Q4_K_M  [46 t/s, універсальна]"
        name   = "Qwopus-MoE-35B-A3B-Q4_K_M"
        dir    = "J:\LLM\models"
        ngl    = 999
        ncmoe  = 30
        ub     = 1024
        b      = 2048
        extra  = "--flash-attn 1 --temp 0.7 --top-p 0.8 --top-k 20 --presence-penalty 1.5 --repeat-penalty 1.0 --parallel 2 --reasoning-budget 0"
    }
)

$llamaDir = "J:\llm_working_bin\llama-b9159-bin-win-cuda-12.4-x64"
$port     = 8080

# ============================================================
#  МЕНЮ — вибір моделі
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║            Claude Code — вибір моделі                   ║" -ForegroundColor Cyan
Write-Host "  ╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "  ║  ☁  ХМАРА                                              ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$idx = 1
foreach ($c in $cloud) {
    Write-Host ("  [{0}] {1}" -f $idx, $c.label) -ForegroundColor Magenta
    $idx++
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  💻 ЛОКАЛЬНО (llama.cpp)                                ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

foreach ($l in $local) {
    $color = if ($l.label -match "^⚠") { "DarkYellow" } else { "Yellow" }
    Write-Host ("  [{0}] {1}" -f $idx, $l.label) -ForegroundColor $color
    $idx++
}

Write-Host ""
$raw = Read-Host "  Обери модель (1-$($idx-1))"
if (-not ($raw -match '^\d+$') -or [int]$raw -lt 1 -or [int]$raw -ge $idx) {
    Write-Host "Невірний вибір." -ForegroundColor Red
    exit 1
}
$choice = [int]$raw - 1

# ============================================================
#  МЕНЮ — режим доступу (живий проект!)
# ============================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  🔐 Режим доступу                                       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  [1] Повний доступ       (Bash + Write + Edit)" -ForegroundColor Yellow
Write-Host "  [2] Без Bash            (Write + Edit, без виконання команд)" -ForegroundColor Green
Write-Host "  [3] Тільки читання       (аналіз коду, без змін)" -ForegroundColor Green
Write-Host ""
$modeRaw = Read-Host "  Режим (1-3) [Enter = 2]"
if ($modeRaw -eq "") { $modeRaw = "2" }

$claudeFlags = switch ($modeRaw) {
    "1" { "" }
    "3" { '--disallowedTools "Bash,Write,Edit"' }
    default { '--disallowedTools "Bash"' }
}
$modeLabel = switch ($modeRaw) {
    "1" { "🔓 Повний доступ" }
    "3" { "👁  Тільки читання" }
    default { "🛡  Без Bash" }
}

# ============================================================
#  Допоміжна функція — зупинити сервер і звільнити порт
# ============================================================
function Stop-LlamaServer {
    $procs = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "  Зупиняю llama-server (PID: $($procs.Id -join ','))..." -ForegroundColor DarkYellow
        $procs | Stop-Process -Force
        Start-Sleep 3
    }
    # Страховка — зупинити все, що тримає порт
    $netLine = netstat -ano 2>$null | Select-String ":$port\s" | Select-String "LISTENING"
    if ($netLine) {
        $portPid = ($netLine -split '\s+')[-1]
        if ($portPid -match '^\d+$' -and $portPid -ne '0') {
            Write-Host "  Порт $port зайнятий PID $portPid — звільняю..." -ForegroundColor DarkYellow
            taskkill /PID $portPid /F 2>$null | Out-Null
            Start-Sleep 2
        }
    }
}

# ============================================================
#  ХМАРА
# ============================================================
if ($choice -lt $cloud.Count) {
    $c = $cloud[$choice]
    Write-Host "`n  ☁  $($c.label)" -ForegroundColor Magenta
    Stop-LlamaServer
    $env:ANTHROPIC_BASE_URL   = $c.baseUrl
    $env:ANTHROPIC_AUTH_TOKEN = $c.token
    $env:ANTHROPIC_MODEL      = $c.model
}
# ============================================================
#  ЛОКАЛЬНО
# ============================================================
else {
    $l = $local[$choice - $cloud.Count]
    $gguf = Join-Path $l.dir "$($l.name).gguf"

    if (-not (Test-Path $gguf)) {
        Write-Host "`n  Файл не знайдено: $gguf" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n  💻 $($l.label)" -ForegroundColor Green
    Stop-LlamaServer

    # Збираємо аргументи сервера
    $srvArgs  = "-m `"$gguf`""
    $srvArgs += " -fa 1 -ngl $($l.ngl) -ub $($l.ub) -b $($l.b)"
    $srvArgs += " -c 65536 --no-mmap -t 12"
    $srvArgs += " -ctk q8_0 -ctv q8_0 --jinja"
    if ($l.ncmoe -gt 0) { $srvArgs += " -ncmoe $($l.ncmoe)" }
    if ($l.extra)        { $srvArgs += " $($l.extra)" }
    $srvArgs += " --host 0.0.0.0 --port $port --metrics"

    Write-Host "  Запускаю сервер..." -ForegroundColor DarkGray
    Start-Process -FilePath "$llamaDir\llama-server.exe" `
                  -ArgumentList $srvArgs `
                  -WindowStyle Minimized

    # Чекаємо /health
    $ready = $false
    Write-Host "  Очікую /health " -ForegroundColor Yellow -NoNewline
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep 2
        try {
            $r = Invoke-WebRequest "http://127.0.0.1:$port/health" `
                                   -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
        Write-Host "." -NoNewline -ForegroundColor DarkGray
    }

    if (-not $ready) {
        Write-Host "`n  Сервер не відповів за 80с!" -ForegroundColor Red
        exit 1
    }
    Write-Host " OK" -ForegroundColor Green

    Write-Host "  Розігрів моделі (5с)..." -ForegroundColor DarkGray
    Start-Sleep 5

    $env:ANTHROPIC_BASE_URL   = "http://127.0.0.1:$port"
    $env:ANTHROPIC_AUTH_TOKEN = "local"
    $env:ANTHROPIC_MODEL      = $l.name
}

# ============================================================
#  Запуск Claude Code
# ============================================================
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "  │  Model  : $env:ANTHROPIC_MODEL" -ForegroundColor Cyan
Write-Host "  │  URL    : $env:ANTHROPIC_BASE_URL" -ForegroundColor Cyan
Write-Host "  │  Режим  : $modeLabel" -ForegroundColor Cyan
Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

if ($claudeFlags) {
    Invoke-Expression "claude $claudeFlags"
} else {
    claude
}
