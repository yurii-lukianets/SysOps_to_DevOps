# LLM Benchmark Results — RTX 3050 (8GB VRAM)

## Qwen3-35B MOE — ncmoe parameter sweep

| ncmoe | ub | b | pp t/s | tg t/s | notes |
|-------|-----|------|--------|--------|-------|
| 26 | 1024 | 1024 | 83.40 | 12.63 | too slow |
| 29 | 1024 | 1024 | 82.60 | 15.98 | too slow |
| **33** | **1024** | **1024** | **264.43** | **32.66** | **optimal ★** |
| 35 | 1024 | 1024 | 261.34 | 31.49 | marginal |

## Qwen3-35B MOE — batch size sweep (ncmoe=33)

| ub | b | pp t/s | tg t/s |
|----|---|--------|--------|
| 512 | 512 | 353.11 | 31.07 |
| 1024 | 1024 | 264.43 | 32.66 |
| 2048 | 2048 | 354.89 | 31.61 |

## Qwopus 27B — ngl sweep

| ngl | pp t/s | tg t/s | notes |
|-----|--------|--------|-------|
| 20 | 225.74 | 3.82 | CPU bottleneck |
| 25 | 230.21 | 4.17 | best for this GPU |
| 30 | 35.58 | 4.64 | VRAM overflow |
| 99 | 38.81 | 1.10 | VRAM overflow |

## Optimal launch command

## Refined sweep — ncmoe 31–34 (Qwen3-35B MOE)

| ncmoe | pp t/s | tg t/s | notes |
|-------|--------|--------|-------|
| 31 | 418.25 | 33.41 | fast pp, good tg |
| **32** | **411.84** | **33.99** | **optimal ★ best pp+tg balance** |
| 33 | 263.45 | 34.24 | pp cliff (-37%), tg marginal gain |
| 34 | 262.05 | 33.51 | no benefit over 33 |

> Cliff at ncmoe=32→33: GPU↔CPU layer boundary crossed.
> ncmoe=32 wins: pp=411 t/s (37% faster context), tg=33.99 t/s

## Refined sweep — Qwopus 27B ngl 28–31

| ngl | pp t/s | tg t/s | notes |
|-----|--------|--------|-------|
| 28 | 240.51 | 4.61 | safe |
| **29** | **213.91** | **4.69** | **last safe value ★** |
| 30 | 40.35 | 4.86 | VRAM overflow — pp drops 5× |
| 31 | 40.53 | 4.51 | overflow continues |

> VRAM cliff at ngl=29→30. Max safe: ngl=29.
> Note: dense 27B is not practical on 8GB VRAM (tg ~4.7 t/s)

## Updated optimal launch command

```powershell
.\llama-server.exe -m "l:\LLM\models\Qwen3.6-35B-A3B-MXFP4_MOE.gguf" -fa 1 -ngl 99 -ncmoe 32 -ub 1024 -b 1024 -t 12 -ctk q8_0 -ctv q8_0 --jinja --host 0.0.0.0 --port 8080 --metrics
```
