const std = @import("std");
const root = @import("root");

const cstr = [:0]const u8;

const FlagList = std.ArrayList(cstr);

pub const FlagType = enum { Bool, U64, Size, Str, List, External };

const External = union(FlagType) { Bool: *bool, U64: *u64, Size: *usize, Str: *cstr, List: *FlagList, External: void };

const FlagVal = union(FlagType) { Bool: bool, U64: u64, Size: usize, Str: cstr, List: FlagList, External: External };

const Flag = struct { name: cstr, desc: cstr, kind: FlagType, def: FlagVal, val: FlagVal };

pub const ParseError = error{ NoError, Unknown, NoValue, InvalidBool, InavlidSizeSuffix, OOMProgramName } || std.fmt.ParseIntError || std.mem.Allocator.Error;

const FLAG_CAP = if (@hasDecl(root, "FLAG_CAP") and @TypeOf(root.FLAG_CAP) == comptime_int) root.FLAG_CAP else 256;
const Self = @This();

program_name: cstr = "",

flags: [FLAG_CAP]Flag = undefined,
flag_count: usize = 0,

parse_error: ParseError = ParseError.NoError,
parse_error_name: cstr = "",

args: []const cstr,
cur_arg: usize = 0,

ctx_arena: std.heap.ArenaAllocator,

fn FlagValTypeArg(comptime flag_type: FlagType) type {
    return switch (flag_type) {
        .Bool => bool,
        .U64 => u64,
        .Size => usize,
        .Str => cstr,
        .List => void,
        .External => unreachable,
    };
}

fn FlagValTypeRet(comptime flag_type: FlagType) type {
    return switch (flag_type) {
        .Bool => *const bool,
        .U64 => *const u64,
        .Size => *const usize,
        .Str => *const cstr,
        .List => *FlagList,
        .External => unreachable,
    };
}

fn FlagValTypePtr(comptime flag_type: FlagType) type {
    return switch (flag_type) {
        .Bool => *bool,
        .U64 => *u64,
        .Size => *usize,
        .Str => *cstr,
        .List => *FlagList,
        .External => unreachable,
    };
}

fn parseBool(val: [:0]const u8) ParseError!bool {
    if (std.mem.eql(u8, "1", val) or std.mem.eql(u8, "true", val)) {
        return true;
    }
    if (std.mem.eql(u8, "0", val) or std.mem.eql(u8, "false", val)) {
        return false;
    }
    return ParseError.InvalidBool;
}

/// Initializes a flag context.
pub fn init(ac: std.mem.Allocator, args: []const cstr) Self {
    return .{ .args = args, .ctx_arena = .init(ac) };
}

///  Frees the context.
pub fn deinit(self: *Self) void {
    self.ctx_arena.deinit();
    self.* = undefined;
}

/// Adds a flag to the context with `name`, `description` and return a const pointer for the value initialized with `def` and updated after `parse`.
pub fn flagNew(self: *Self, comptime flag_type: FlagType, comptime name: cstr, comptime desc: cstr, comptime def: FlagValTypeArg(flag_type)) FlagValTypeRet(flag_type) {
    if (self.flag_count >= FLAG_CAP) {
        @panic("excessive args");
    }

    var flag = &self.flags[self.flag_count];

    self.flag_count += 1;

    flag.* = .{
        .name = name,
        .desc = desc,
        .kind = flag_type,
        .def = switch (flag_type) {
            .External => unreachable,
            .List => .{ .List = .init(self.ctx_arena.allocator()) },
            else => @unionInit(FlagVal, @tagName(flag_type), def),
        },
        .val = switch (flag_type) {
            .External => unreachable,
            .List => .{ .List = .init(self.ctx_arena.allocator()) },
            else => @unionInit(FlagVal, @tagName(flag_type), def),
        },
    };

    return &@field(flag.val, @tagName(flag_type));
}

/// Adds a flag to the context with `name`, `description` and stores the value in the pointer supplied(`ptr`) initialized with `def` and updated after `parse`.
pub fn flagVar(self: *Self, comptime flag_type: FlagType, comptime ptr: FlagValTypePtr(flag_type), comptime name: cstr, comptime desc: cstr, comptime def: FlagValTypeArg(flag_type)) void {
    if (self.flag_count >= FLAG_CAP) {
        @panic("excessive args");
    }

    ptr.* = def;

    self.flags[self.flag_count] = .{
        .name = name,
        .desc = desc,
        .kind = flag_type,
        .def = switch (flag_type) {
            .External => unreachable,
            .List => .init(self.ctx_arena.allocator()),
            else => @unionInit(FlagVal, @tagName(flag_type), def),
        },
        .val = .{ .External = @unionInit(External, @tagName(flag_type), ptr) },
    };

    self.flag_count += 1;
}

/// Pretty prints the usage message for the flags.
pub fn usage(self: Self) void {
    std.debug.print("Usage: {s} [OPTIONS] <inputs...> [--] [run arguments]\n", .{self.program_name});
    std.debug.print("OPTIONS:\n", .{});
    for (0..self.flag_count) |i| {
        const clf = self.flags[i];
        std.debug.print("    -{s}\n", .{clf.name});
        {
            var ss = std.mem.splitScalar(u8, clf.desc, '\n');
            while (ss.next()) |desc_line| {
                std.debug.print("        {s}\n", .{desc_line});
            }
        }
        switch (clf.def) {
            .Bool => |b| if (b) {
                std.debug.print("        Default: true\n", .{});
            },
            .U64, .Size => |u| {
                std.debug.print("        Default: {d}\n", .{u});
            },
            .Str => |str| if (str.len > 0) {
                std.debug.print("        Default: {s}\n", .{str});
            },
            .List => {},
            else => unreachable,
        }
    }
}

/// Returns true if there are args left to parse.
pub fn hasArgs(self: Self) bool {
    return self.cur_arg < self.args.len;
}

/// All the args the parser has not seen yet
pub fn restArgs(self: Self) []const cstr {
    return self.args[self.cur_arg..];
}

/// Returns the first arg not seen by parser otherwise `null`
pub fn nextArg(self: *Self) ?cstr {
    while (self.hasArgs()) {
        const arg = self.args[self.cur_arg];
        self.cur_arg += 1;
        return arg;
    }
    return null;
}

/// Parse the flags supplies with `init`
pub fn parse(self: *Self) ParseError!void {
    if (!self.hasArgs()) {
        return;
    }

    if (self.program_name.len == 0) {
        self.program_name = self.ctx_arena.allocator().dupeZ(u8, self.nextArg() orelse unreachable) catch {
            self.parse_error = ParseError.OOMProgramName;
            return self.parse_error;
        };
    }

    if (!self.hasArgs()) {
        return;
    }

    {
        const arg = self.args[self.cur_arg];
        if (arg.len > 0 and (arg[0] != '-' or (arg.len == 2 and arg[1] == '-'))) {
            return;
        }
    }

    while (self.nextArg()) |raw_arg| {
        if (raw_arg.len == 0) {
            continue;
        }

        var ref_arg: cstr = raw_arg[1..];
        if (ref_arg.len > 0 and ref_arg[0] == '-') {
            ref_arg = ref_arg[1..];
        }

        for (0..self.flag_count) |flag_idx| {
            var flag = &self.flags[flag_idx];
            const flag_name_len = flag.name.len;

            if (std.mem.startsWith(u8, ref_arg, flag.name)) {
                const val: [:0]const u8 = if (ref_arg.len == flag_name_len) blk: {
                    if (flag.val == .Bool) {
                        break :blk "1";
                    }
                    const val = self.nextArg() orelse {
                        self.parse_error = ParseError.NoValue;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    };
                    break :blk val;
                } else if (ref_arg[flag_name_len] == '=') blk: {
                    const val = ref_arg[(flag_name_len + 1)..];
                    if (val.len == 0) {
                        self.parse_error = ParseError.NoValue;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    }
                    break :blk val;
                } else {
                    continue;
                };

                const flag_val: FlagVal = switch (flag.kind) {
                    .Bool => .{ .Bool = parseBool(val) catch {
                        self.parse_error = ParseError.InvalidBool;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    } },
                    .U64 => .{ .U64 = std.fmt.parseInt(u64, val, 10) catch |err| {
                        self.parse_error = err;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    } },
                    .Size => blk: {
                        var idx: usize = 0;
                        while (std.ascii.isDigit(val[idx])) : (idx += 1) {}
                        const number = std.fmt.parseInt(usize, val[0..idx], 10) catch |err| {
                            self.parse_error = err;
                            self.parse_error_name = flag.name;
                            return self.parse_error;
                        };
                        var mult: usize = 1;
                        const suffix = val[idx..];
                        if (std.mem.eql(u8, "K", suffix)) {
                            mult = 1 << 10;
                        } else if (std.mem.eql(u8, "M", suffix)) {
                            mult = 1 << 20;
                        } else if (std.mem.eql(u8, "G", suffix)) {
                            mult = 1 << 30;
                        } else if (suffix.len != 0) {
                            self.parse_error = ParseError.InavlidSizeSuffix;
                            self.parse_error_name = flag.name;
                            return self.parse_error;
                        }
                        break :blk .{ .Size = std.math.mul(usize, number, mult) catch |err| {
                            self.parse_error = err;
                            self.parse_error_name = flag.name;
                            return self.parse_error;
                        } };
                    },
                    .Str => .{ .Str = self.ctx_arena.allocator().dupeZ(u8, val) catch |err| {
                        self.parse_error = err;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    } },
                    .List => .{ .Str = flag.val.List.allocator.dupeZ(u8, val) catch |err| {
                        self.parse_error = err;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    } },
                    .External => unreachable,
                };
                switch (flag.val) {
                    .Bool, .U64, .Size, .Str => flag.val = flag_val,
                    .List => flag.val.List.append(flag_val.Str) catch |err| {
                        self.parse_error = err;
                        self.parse_error_name = flag.name;
                        return self.parse_error;
                    },
                    .External => |*ext| switch (ext.*) {
                        .External => unreachable,
                        .List => ext.List.append(flag_val.Str) catch |err| {
                            self.parse_error = err;
                            self.parse_error_name = flag.name;
                            return self.parse_error;
                        },
                        inline else => |ptr, label| ptr.* = @field(flag_val, @tagName(label)),
                    },
                }
            }
        } else {
            self.parse_error = ParseError.Unknown;
            self.parse_error_name = ref_arg;
            return self.parse_error;
        }
    }
}

pub fn printError(self: Self) void {
    switch (self.parse_error) {
        ParseError.NoError => std.debug.print("Operation Failed Successfully! Please tell the developer of this software that they don't know what they are doing! :)", .{}),
        ParseError.Unknown => std.debug.print("ERROR: -{s}: unknown flag\n", .{self.parse_error_name}),
        ParseError.NoValue => std.debug.print("ERROR: -{s}: no value provided\n", .{self.parse_error_name}),
        ParseError.InvalidBool => std.debug.print("ERROR: -{s}: invalid boolean\n", .{self.parse_error_name}),
        ParseError.InvalidCharacter => std.debug.print("ERROR: -{s}: invalid number\n", .{self.parse_error_name}),
        ParseError.Overflow => std.debug.print("ERROR: -{s}: integer overflow\n", .{self.parse_error_name}),
        ParseError.InavlidSizeSuffix => std.debug.print("ERROR: -{s}: invalid size suffix\n", .{self.parse_error_name}),
        ParseError.OutOfMemory => std.debug.print("ERROR: -{s}: Ran out of memory while processing\n", .{self.parse_error_name}),
        ParseError.OOMProgramName => std.debug.print("ERROR: Ran out of memory while processing\n", .{}),
    }
}
