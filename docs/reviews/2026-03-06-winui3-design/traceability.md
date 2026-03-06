# Traceability (Raw -> Finding)

This file maps issue findings to raw review-crate outputs without paraphrase loss.

## Raw Sources
- `app-architecture.raw.txt`
- `surface-architecture.raw.txt`
- `com-aggregation-architecture.raw.txt`
- `parity-audit.raw.txt`

## Mapping
1. Finding: `initXaml` responsibility concentration harms diagnosability.
- Raw evidence:
  - app-architecture.raw.txt
  - section: "### 4. 改善点"
  - sentence includes: "`initXaml`の巨大化"

2. Finding: startup/pass criteria are decoupled from lifecycle health.
- Raw evidence:
  - parity-audit.raw.txt
  - section includes: "FINAL_JUDGMENT: PASS"
  - (paired with runtime gate evidence in this repo: quality-gate summaries showing keep-alive failures)

3. Finding: COM ownership/release contract is under-specified.
- Raw evidence:
  - com-aggregation-architecture.raw.txt
  - section: "### 4. 改善点・注意点"
  - sentence includes: "参照カウントとメモリ解放"

4. Finding: Surface side has implementation/test debt in platform hooks.
- Raw evidence:
  - surface-architecture.raw.txt
  - section: "### 4. 改善点"
  - sentence includes: "未実装（TODO）の解消"

## Inference Boundary
- Any architecture recommendation in issue #23 should reference at least one raw source above.
- If a recommendation cannot be mapped to raw evidence, label it explicitly as `Inference`.
