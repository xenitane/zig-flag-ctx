# zig-flag-ctx

A **simple and fast** cli flag parsing library for zig inspired from go's [flag pckage](https://pkg.go.dev/flag).

[![Tests](https://github.com/xenitane/zig-flag/actions/workflows/main.yml/badge.svg)](https://github.com/xenitane/zig-flag/actions/workflows/main.yml)
[![Zig Version](https://img.shields.io/badge/Zig_Version-0.14.1-orange.svg?logo=zig)](README.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg?logo=cachet)](LICENSE)
[![Version](https://img.shields.io/badge/zig--flag-v3.7.1-green)](https://github.com/xenitane/zig-flag/releases)

## Highlights

- Fast flag parsing (`-flag`, `--flag`, `-flag=value` and `--flag=value`).
- Type-safe support for `bool`, `int`, `file-size`, `string` and `list of strings`.
- Pretty help output with aligned flags & args, see `usage` function.

## Installation

```bash
zig fetch --save git+https://github.com/xenitane/zig-flag-ctx
```

Add to your `build.zig`:

```zig
const zig_flag = b.dependency("zfc", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zfc", zig_flag.module("zfc"));
```

## API

- `init(ac: allocator, args: []const [:0]const u8) FlagCtx`: Initializes a flag context.
- `deinit() void`: Frees the context.
- `flagNew(comptime flag_type: FlagType, comptime name: cstr, comptime desc: cstr, comptime def: FlagValTypeArg(flag_type)) *const FlagValTypeRet(flag_type)`: Adds a flag to the context with `name`, `description` and return a const pointer for the value initialized with `def` and updated after `parse`.
- `flagVar(comptime flag_type: FlagType, comptime ptr: *FlagValTypeRet(flag_type), comptime name: cstr, comptime desc: cstr, comptime def: FlagValTypeArg(flag_type)) void`: Adds a flag to the context with `name`, `description` and stores the value in the pointer supplied(`ptr`) initialized with `def` and updated after `parse`.
- `usage() void`: Pretty prints the usage message for the flags.
- `hasArgs() bool`: Returns true if there are args left to parse.
- `restArgs() []const [:0]const u8`: Return all the args the parser has not seen yet
- `nextArg() ?[:0]const u8`: Returns the first arg not seen by parser otherwise `null`
- `parse() ParserError!void`: Parse the flags supplies with `init` or returns an error if any happens during parsing.
- `printError() void`: Prints the error message for the error occurred during parsing

### Types

- `FlagType`: enum for all the possible value types for flags.

## Example

```zig
// src/main.zig
const std = @import("std");
const FlagCtx = @import("zfc");

pub fn main() !void {
    var DA = std.heap.DebugAllocator(.{}){};
    defer {
        if (DA.deinit() == .leak) {
            @panic("memory leaked");
        }
    }
    const da = DA.allocator();

    const args = try std.process.argsWithAlloc(da);
    defer std.process.argsFree(args, da);

    const flag_ctx = FlagCtx.init(da, args);
    defer flag_ctx.deinit();

    
    const help = flag_ctx.flagNew(.Bool, "help", "Print this help message", false);

    var output_path: [:0]const u8 = undefined;

    const out_name = flag_ctx.flagVar(.Str, &output_path, "o", "Output Path", "");

    while (flag_ctx.hasArgs()) {
        flag_ctx.parse() catch {
            flag_ctx.usage();
            flag_ctx.printError();
            std.process.exit(1);
        }
        // process the non flag arg(s) here ...
    }

    if (help.*) {
        flag_ctx.usage();
        return;
    }

    if (output_path.*.len != 0) {
        std.debug.print("output path = `{s}`\n", .{output_path});
    }
}

```

## License

MIT. See [LICENSE](license). Contributions welcome.
