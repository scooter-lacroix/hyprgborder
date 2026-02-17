# Zig 0.16.0-dev Migration Notes

This document captures key syntax changes and API differences encountered when working with Zig 0.16.0-dev.368+2a97e0af6, compared to earlier versions.

## ArrayList API Changes

### Initialization
**Old (pre-0.16):**
```zig
var list = std.ArrayList(T).init(allocator);
```

**New (0.16+):**
```zig
// Method 1: Empty initialization (most common)
var list: std.ArrayList(T) = .{};

// Method 2: Still works but may be deprecated in some contexts
var list = std.ArrayList(T).init(allocator);
```

**Note**: The `.{}` initialization pattern is now preferred for ArrayList and many other standard library types.

### Method Calls Require Allocator
**Old:**
```zig
try list.append(item);
list.deinit();
```

**New:**
```zig
try list.append(allocator, item);
list.deinit(allocator);
```

### Other ArrayList Methods
**Old:**
```zig
list.clearAndFree();
```

**New:**
```zig
list.clearAndFree(allocator);
```

## Atomic API Changes

### Atomic Types
**Old:**
```zig
std.atomic.Atomic(bool)
```

**New:**
```zig
std.atomic.Value(bool)
```

### Atomic Operations
**Old:**
```zig
atomic_var.store(value, .Release);
atomic_var.load(.Acquire);
```

**New:**
```zig
atomic_var.store(value, .release);
atomic_var.load(.acquire);
```

## Process API Changes

### Child Process Execution
**Old:**
```zig
std.ChildProcess.exec(.{
    .allocator = allocator,
    .argv = &[_][]const u8{ "command", "arg" },
})
```

**New:**
```zig
std.process.Child.run(.{
    .allocator = allocator,
    .argv = &[_][]const u8{ "command", "arg" },
})
```

## Memory API Changes

### String Splitting
**Old:**
```zig
std.mem.split(u8, string, delimiter)
```

**New:**
```zig
std.mem.splitSequence(u8, string, delimiter)
```

## JSON API Changes

### JSON Serialization
**Old:**
```zig
try std.json.stringify(value, .{}, writer);
```

**New:**
```zig
// Method 1: Using Stringify.value with std.Io.Writer.Allocating
var out: std.Io.Writer.Allocating = .init(allocator);
defer out.deinit();
try std.json.Stringify.value(value, .{}, &out.writer);
const json_string = out.written();

// Method 2: Using Stringify struct for streaming
var stringify: std.json.Stringify = .{
    .writer = &writer,
    .options = .{},
};
try stringify.beginObject();
try stringify.objectField("key");
try stringify.write(value);
try stringify.endObject();
```

### JSON HashMap/ObjectMap Initialization
**Old:**
```zig
var json_obj = std.json.ObjectMap.init(allocator);
defer json_obj.deinit();
```

**New:**
```zig
// Still works the same way, but ArrayList pattern changed
var json_obj = std.json.ObjectMap.init(allocator);
defer json_obj.deinit(); // No allocator needed for ObjectMap.deinit()
```

## File API Changes

### File Writer
**Old:**
```zig
file.writer()
```

**New:**
```zig
var buffer: [4096]u8 = undefined;
file.writer(buffer[0..])
```

Note: The file writer now requires a buffer parameter.

## Debug Print Changes

### Format Arguments Required
**Old (sometimes worked):**
```zig
std.debug.print("Hello world\n");
```

**New (always required):**
```zig
std.debug.print("Hello world\n", .{});
```

All `std.debug.print` calls must include the format arguments tuple, even if empty.

## Build System Changes

### Test Configuration
**Old:**
```zig
const tests = b.addTest(.{
    .root_source_file = b.path("src/file.zig"),
    .target = target,
    .optimize = optimize,
});
```

**New:**
```zig
const tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/file.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
```

## Error Handling Patterns

### Catch with Block Labels
When you need to return a value from a catch block, use block labels:

**Pattern:**
```zig
const result = someFunction() catch |err| blk: {
    // Handle error
    std.debug.print("Error: {s}\n", .{@errorName(err)});
    break :blk default_value;
};
```

## Heap Allocator Changes

### DebugAllocator Initialization
**Old:**
```zig
var gpa = std.heap.DebugAllocator(.{}){};
```

**New:**
```zig
var gpa: std.heap.DebugAllocator(.{}) = .init;
// or
var gpa = std.heap.DebugAllocator(.{}).init;
```

### Other Allocators
```zig
// GeneralPurposeAllocator still uses old pattern (for now)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

// But prefer DebugAllocator with new .init pattern for development
var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
defer _ = debug_gpa.deinit();
```

## Common Patterns

### Struct Initialization with ArrayList
**Pattern:**
```zig
const MyStruct = struct {
    items: std.ArrayList(T),
    
    pub fn init(allocator: std.mem.Allocator) MyStruct {
        return MyStruct{
            .items = .{}, // Empty initialization
        };
    }
    
    pub fn deinit(self: *MyStruct, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }
};
```

### Module Dependencies in build.zig
**Pattern:**
```zig
// Define modules in dependency order (no circular deps)
const utils_mod = b.addModule("utils", .{
    .root_source_file = b.path("src/utils/mod.zig"),
    .target = target,
});

const config_mod = b.addModule("config", .{
    .root_source_file = b.path("src/config/mod.zig"),
    .target = target,
    .imports = &.{
        .{ .name = "utils", .module = utils_mod },
    },
});
```

## Tips for Migration

1. **Always pass allocators**: Most collection methods now require explicit allocator parameters
2. **Use `.{}` initialization**: Prefer empty struct initialization for ArrayList and similar types
3. **Check deprecation warnings**: Some allocators like DebugAllocator now require `.init`
4. **Use block labels**: For complex catch expressions that need to return values
5. **Check atomic enum values**: Atomic ordering enums are now lowercase
6. **Update process APIs**: Child process execution has moved to `std.process.Child`
7. **JSON serialization**: Use `std.Io.Writer.Allocating` for in-memory JSON generation
8. **File writers**: Always provide a buffer when creating file writers
9. **Debug prints**: Always include format arguments, even if empty `(.{})`

## Important Notes

### Mixed Initialization Patterns
In Zig 0.16.0-dev, there's a transition period where different types use different initialization patterns:

- **ArrayList**: Uses `.{}` empty initialization ✅ **New preferred pattern**
- **DebugAllocator**: Now requires `.init` ✅ **New preferred pattern** (old pattern deprecated)
- **GeneralPurposeAllocator**: Still uses `Type(.{}){}` (legacy pattern, may change)
- **HashMap/ObjectMap**: Still uses `.init(allocator)` (legacy pattern)

**Recommendation**: Use DebugAllocator with `.init` for development as it follows the new initialization pattern and provides better debugging capabilities.

### Checking for Deprecations
Always check for deprecation warnings in your IDE or compiler output. Many types are transitioning to new initialization patterns, and the compiler will guide you to the correct syntax.

## Version Information

These notes are based on:
- **Zig Version**: 0.16.0-dev.368+2a97e0af6
- **Date**: December 2024
- **Platform**: Linux x86_64

## References

- [Zig 0.16.0 Release Notes](https://ziglang.org/download/0.16.0/release-notes.html) (when available)
- [Zig Standard Library Documentation](https://ziglang.org/documentation/master/std/)