# Phase 3 Implementation Strategy: Coordinate Stabilization

## Problem Analysis (Based on Phase 1 Expected Patterns)

### Identified Issues:
1. **TSF Coordinate Request Storms**: Gemini CLI likely triggers rapid cursor updates → excessive GetTextExt calls
2. **Coordinate Calculation Race Conditions**: imePoint() called during surface geometry updates
3. **Stale Coordinate Persistence**: TSF caches incorrect coordinates during rapid UI changes
4. **Non-atomic Updates**: Cursor position and surface metrics updated separately

### Expected Log Patterns (Gemini CLI vs Claude Code):

#### Gemini CLI (Problematic):
```
TUI cursor update: CSI H (1,1)
TSF GetTextExt: cursor=(1,1) ime_pos=(20.0,25.0) screen=(100,200)
TUI cursor update: CSI H (1,15)
TSF GetTextExt: cursor=(1,15) ime_pos=(300.0,25.0) screen=(350,200)
TUI cursor update: CSI H (1,1)  // Rapid position changes
TSF GetTextExt: cursor=(1,1) ime_pos=(20.0,25.0) screen=(100,200)
// Pattern: High frequency updates with coordinate jumping
```

#### Claude Code (Stable):
```
TUI cursor update: CSI H (1,10)
TSF GetTextExt: cursor=(1,10) ime_pos=(200.0,25.0) screen=(250,200)
// Pattern: Infrequent, stable coordinate requests
```

## Phase 3 Implementation Strategy

### Component 1: Coordinate Caching System

#### Location: `src/apprt/winui3/App.zig`

```zig
// Add to App struct
const IMECoordinateCache = struct {
    last_cursor_x: u32 = 0,
    last_cursor_y: u32 = 0,
    last_screen_x: i32 = 0,
    last_screen_y: i32 = 0,
    last_update_time: i64 = 0,
    cache_valid: bool = false,
    
    const CACHE_DURATION_MS = 150; // Cache coordinates for 150ms
    const MIN_POSITION_CHANGE = 5; // Minimum pixel movement to invalidate
};

ime_coord_cache: IMECoordinateCache = .{},
```

#### Updated tsfGetCursorRect:
```zig
fn tsfGetCursorRect(userdata: ?*anyopaque) os.RECT {
    const app: *App = @ptrCast(@alignCast(userdata orelse return os.RECT{}));
    const surface = app.activeSurface() orelse return os.RECT{};
    const hwnd = app.hwnd orelse return os.RECT{};

    // Get current cursor position for comparison
    surface.core_surface.renderer_state.mutex.lock();
    const cursor_x = surface.core_surface.renderer_state.terminal.screens.active.cursor.x;
    const cursor_y = surface.core_surface.renderer_state.terminal.screens.active.cursor.y;
    surface.core_surface.renderer_state.mutex.unlock();

    const current_time = std.time.milliTimestamp();
    
    // Check cache validity
    const cache = &app.ime_coord_cache;
    const cache_expired = (current_time - cache.last_update_time) > IMECoordinateCache.CACHE_DURATION_MS;
    const cursor_moved = (cursor_x != cache.last_cursor_x) or (cursor_y != cache.last_cursor_y);
    
    if (cache.cache_valid and !cache_expired and !cursor_moved) {
        log.info("TSF GetTextExt: using cached coordinates screen=({d},{d})", .{cache.last_screen_x, cache.last_screen_y});
        return os.RECT{
            .left = cache.last_screen_x,
            .top = cache.last_screen_y,
            .right = cache.last_screen_x + 1,
            .bottom = cache.last_screen_y + 20, // Default cell height
        };
    }

    // Calculate fresh coordinates
    const ime_pos = surface.core_surface.imePoint();
    var pt = os.POINT{ .x = @intFromFloat(ime_pos.x), .y = @intFromFloat(ime_pos.y) };
    _ = os.ClientToScreen(hwnd, &pt);

    // Update cache only if coordinates changed significantly
    const significant_change = @abs(pt.x - cache.last_screen_x) > IMECoordinateCache.MIN_POSITION_CHANGE or
                              @abs(pt.y - cache.last_screen_y) > IMECoordinateCache.MIN_POSITION_CHANGE;
    
    if (significant_change or !cache.cache_valid) {
        cache.last_cursor_x = cursor_x;
        cache.last_cursor_y = cursor_y;
        cache.last_screen_x = pt.x;
        cache.last_screen_y = pt.y;
        cache.last_update_time = current_time;
        cache.cache_valid = true;
        
        log.info("TSF GetTextExt: updated cache cursor=({d},{d}) screen=({d},{d})", .{cursor_x, cursor_y, pt.x, pt.y});
    } else {
        log.info("TSF GetTextExt: coordinate change too small, using cached values", .{});
    }

    return os.RECT{
        .left = cache.last_screen_x,
        .top = cache.last_screen_y,
        .right = cache.last_screen_x + 1,
        .bottom = cache.last_screen_y + @intFromFloat(ime_pos.height),
    };
}
```

### Component 2: TSF Update Throttling

#### Location: `src/apprt/winui3/tsf.zig`

```zig
// Add to TsfImplementation struct
const TSFUpdateThrottle = struct {
    pending_update: bool = false,
    last_update_time: i64 = 0,
    timer_id: ?usize = null,
    
    const THROTTLE_DELAY_MS = 50; // 50ms debounce
};

tsf_throttle: TSFUpdateThrottle = .{},
```

#### Throttled coordinate updates:
```zig
fn scheduleCoordinateUpdate(self: *TsfImplementation) void {
    const current_time = std.time.milliTimestamp();
    
    if (self.tsf_throttle.pending_update) {
        log.info("TSF: coordinate update already pending, skipping", .{});
        return;
    }
    
    const time_since_last = current_time - self.tsf_throttle.last_update_time;
    if (time_since_last < TSFUpdateThrottle.THROTTLE_DELAY_MS) {
        // Schedule delayed update
        self.tsf_throttle.pending_update = true;
        // Use Windows timer or similar mechanism to delay
        log.info("TSF: throttling coordinate update, scheduling in {}ms", .{TSFUpdateThrottle.THROTTLE_DELAY_MS - time_since_last});
        return;
    }
    
    // Immediate update
    self.performCoordinateUpdate();
}

fn performCoordinateUpdate(self: *TsfImplementation) void {
    self.tsf_throttle.last_update_time = std.time.milliTimestamp();
    self.tsf_throttle.pending_update = false;
    
    // Trigger actual TSF coordinate refresh
    _ = self.requestEditSession(tsf.TF_ES_READWRITE | tsf.TF_ES_ASYNC);
    log.info("TSF: coordinate update executed", .{});
}
```

### Component 3: Smart Cursor Update Detection

#### Location: `src/termio/stream_handler.zig`

```zig
fn handleCursorPosition(self: *StreamHandler, value: anytype) void {
    const old_x = self.terminal.screens.active.cursor.x;
    const old_y = self.terminal.screens.active.cursor.y;
    
    // Apply cursor update
    self.terminal.setCursorPos(value.row, value.col);
    
    const new_x = self.terminal.screens.active.cursor.x;
    const new_y = self.terminal.screens.active.cursor.y;
    
    // Detect significant movement that requires IME update
    const moved_significantly = @abs(@as(i32, new_x) - @as(i32, old_x)) > 2 or
                               @abs(@as(i32, new_y) - @as(i32, old_y)) > 0;
    
    if (moved_significantly) {
        log.info("TUI cursor update: CSI H ({d},{d}) -> ({d},{d}) [significant]", .{old_x, old_y, new_x, new_y});
        // Notify TSF of significant movement
        if (self.app_context) |app| {
            app.scheduleIMECoordinateUpdate();
        }
    } else {
        log.debug("TUI cursor update: CSI H ({d},{d}) -> ({d},{d}) [minor]", .{old_x, old_y, new_x, new_y});
    }
}
```

### Component 4: Gemini CLI Specific Optimizations

#### Detection mechanism:
```zig
// Add to App struct
const AppDetection = struct {
    is_gemini_active: bool = false,
    rapid_cursor_updates: u32 = 0,
    last_detection_time: i64 = 0,
    
    const RAPID_UPDATE_THRESHOLD = 5; // 5 updates in short time = Gemini-like behavior
    const DETECTION_WINDOW_MS = 1000; // 1 second window
};

app_detection: AppDetection = .{},
```

#### Adaptive behavior:
```zig
fn detectRapidCursorApp(app: *App) void {
    const current_time = std.time.milliTimestamp();
    
    if (current_time - app.app_detection.last_detection_time > AppDetection.DETECTION_WINDOW_MS) {
        // Reset counter
        app.app_detection.rapid_cursor_updates = 0;
        app.app_detection.last_detection_time = current_time;
    }
    
    app.app_detection.rapid_cursor_updates += 1;
    
    if (app.app_detection.rapid_cursor_updates >= AppDetection.RAPID_UPDATE_THRESHOLD) {
        if (!app.app_detection.is_gemini_active) {
            app.app_detection.is_gemini_active = true;
            log.info("App Detection: Gemini-like rapid cursor behavior detected, enabling enhanced stability", .{});
            
            // Increase cache duration for rapid-update apps
            app.ime_coord_cache.CACHE_DURATION_MS = 250; // Longer cache for Gemini
        }
    } else if (app.app_detection.rapid_cursor_updates == 0 and app.app_detection.is_gemini_active) {
        app.app_detection.is_gemini_active = false;
        log.info("App Detection: Returning to normal cursor behavior", .{});
        app.ime_coord_cache.CACHE_DURATION_MS = 150; // Normal cache duration
    }
}
```

## Implementation Priority

### Phase 3.1 (High Priority - Week 1):
1. **Coordinate Caching System** - Immediate stability improvement
2. **Basic Update Throttling** - Reduce TSF call frequency

### Phase 3.2 (Medium Priority - Week 2):
3. **Smart Cursor Detection** - Optimize for significant movements only
4. **Enhanced Logging** - Validate Phase 3 effectiveness

### Phase 3.3 (Low Priority - Week 3):
5. **App-Specific Optimizations** - Gemini CLI adaptive behavior
6. **Performance Tuning** - Fine-tune cache and throttle parameters

## Success Metrics

### Primary Goals:
- **Gemini CLI**: IME positioning within 50 pixels of cursor
- **Claude Code**: No regression in current behavior
- **Performance**: <10ms latency overhead for coordinate calculation

### Measurable Improvements:
- TSF GetTextExt calls reduced by 60-80%
- Coordinate jitter reduced by 90%
- User-reported positioning accuracy >85%

## Testing Strategy

### Automated Testing:
- Unit tests for coordinate caching logic
- Performance benchmarks for throttling mechanisms
- Regression tests for Claude Code behavior

### Manual Testing:
- Gemini CLI Japanese input testing
- Claude Code comparison testing  
- Edge case testing (rapid typing, window resize, multi-monitor)

This Phase 3 strategy addresses the root causes identified in the investigation while maintaining backward compatibility and providing measurable improvements for the TSF IME positioning issues.