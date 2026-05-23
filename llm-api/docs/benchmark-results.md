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
