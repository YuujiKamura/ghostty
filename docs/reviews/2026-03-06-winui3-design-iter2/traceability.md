# Traceability (Raw -> Iteration 2 Actions)

Raw sources:
- `app-architecture.raw.txt`
- `com-aggregation-architecture.raw.txt`
- `surface-architecture.raw.txt`
- `com-aggregation-architecture-postfix.raw.txt`
- `surface-architecture-postfix.raw.txt`

Actions in this iteration:
1. GUID centralization step:
- Added `IID_IUnknown` / `IID_IAgileObject` in `winrt.zig`.
- Updated `com_aggregation.zig` to consume those constants.
- Evidence linkage: `com-aggregation-architecture.raw.txt` ("GUID の一元管理").

2. Reduced silent error swallowing in Surface title update:
- Added explicit warning logs for UTF-16 conversion, HSTRING creation, boxing, and `putHeader`.
- Evidence linkage: `surface-architecture.raw.txt` ("エラーハンドリングの徹底").

Inference boundary:
- Items not directly requested by raw outputs are intentionally deferred.
