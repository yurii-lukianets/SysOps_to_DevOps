# benchmark.ps1 — llama-bench з різними параметрами → CSV результат
$model1 = "l:\LLM\models\Qwen3.6-35B-A3B-MXFP4_MOE.gguf"
$model2 = "l:\LLM\models\Qwopus3.6-27B-v1-preview-Q4_K_M.gguf"
$bench  = "J:\llm_working_bin\llama-b9159-bin-win-cuda-12.4-x64\llama-bench.exe"
$out    = "J:\llm_working_bin\bench_results.csv"

"model,backend,n_gpu_layers,ncmoe,ub,b,pp_t_s,tg_t_s,timestamp" | Out-File $out

function Run-Bench {
    param($model, $ngl, $ncmoe, $ub, $b)
    $name = Split-Path $model -Leaf
    Write-Host "Testing $name ngl=$ngl ncmoe=$ncmoe ub=$ub b=$b ..."
    $raw = & $bench -m $model -fa 1 -ngl $ngl -ncmoe $ncmoe -ub $ub -b $b --no-mmap -t 12 -ctk q8_0 -ctv q8_0 -p 512 -n 128 -r 3 2>&1
    $line = $raw | Where-Object { $_ -match "^\|.*CUDA" } | Select-Object -Last 1
    if ($line) {
        $cols = $line -split "\|" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $pp = $cols[-2]; $tg = $cols[-1]
        "$name,CUDA,$ngl,$ncmoe,$ub,$b,$pp,$tg,$(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Add-Content $out
        Write-Host "  pp=$pp tok/s  tg=$tg tok/s"
    }
}

# Тест 1: Qwen3-35B MOE — різні ncmoe
Run-Bench $model1 99 26 1024 1024
Run-Bench $model1 99 29 1024 1024
Run-Bench $model1 99 33 1024 1024
Run-Bench $model1 99 35 1024 1024

# Тест 2: Qwen3-35B MOE — різні batch size
Run-Bench $model1 99 33 512  512
Run-Bench $model1 99 33 1024 1024
Run-Bench $model1 99 33 2048 2048

# Тест 3: Qwopus 27B — різні ngl
Run-Bench $model2 15 0 1024 1024
Run-Bench $model2 20 0 1024 1024
Run-Bench $model2 25 0 1024 1024
Run-Bench $model2 30 0 1024 1024

Write-Host "`nДонe! Результати: $out"
Import-Csv $out | Format-Table -AutoSize