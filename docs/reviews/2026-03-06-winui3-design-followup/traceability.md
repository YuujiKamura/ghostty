# Traceability (Raw -> Follow-up Focus)

Raw sources:
- `app-architecture.raw.txt`
- `com-aggregation-architecture.raw.txt`
- `surface-architecture.raw.txt`

Mapping:
1. `initXaml` still needs further responsibility split (`app-architecture.raw.txt`, section `### 4. 改善点`).
2. COM lifecycle/manual release complexity remains a structural risk (`app-architecture.raw.txt`, `com-aggregation-architecture.raw.txt`, section `### 4. 改善点`).
3. Surface has TODO/No-op debt that affects completion criteria (`surface-architecture.raw.txt`, section `### 4. 改善点`).

Inference boundary:
- Any implementation plan not directly quoted by the files above must be marked as `Inference`.
