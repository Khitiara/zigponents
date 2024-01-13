pub const Uuid: type = u128;

const std = @import("std");
const Type = @import("std").builtin.Type;

inline fn hex2hw(comptime h: u8) u8 {
    return switch (h) {
        48...57 => h - 48,
        65...70 => h - 65 + 10,
        97...102 => h - 97 + 10,
        else => @compileError("Invalid hex character " ++ h),
    };
}

pub inline fn parseUuidLiteral(comptime str: []const u8) Uuid {
    if (str.len != 36) {
        @compileError("Malformed URN UUID");
    } else if (comptime std.mem.count(u8, str, "-") != 4) {
        @compileError("Malformed URN UUID");
    } else if (str[8] != '-' or str[13] != '-' or str[18] != '-' or str[23] != '-') {
        @compileError("Malformed URN UUID");
    }

    var uuid: Uuid = 0;
    var i: usize = 0;
    var j: u7 = 0;
    while (i <= 34) {
        if (str[i] == '-') {
            i += 1;
            continue;
        }

        const digit: u8 = (hex2hw(str[i]) << 4) | hex2hw(str[i + 1]);
        uuid |= @as(Uuid, @intCast(digit)) << (j * 8);
        i += 2;
        j += 1;
    }
    return uuid;
}

inline fn getOptionalDecl(comptime T: anytype, comptime name: []const u8, comptime Field: type) ?Field {
    if (!@hasDecl(T, name)) return null;
    const f = @field(T, name);
    if (@TypeOf(f) != Field) return null;
    return @as(Field, f);
}

pub fn MergeVTable(comptime T: type) type {
    var entries: []const Type.StructField = &[_]Type.StructField{};
    var parent: ?type = T;
    inline while (parent) |p| : (parent = getOptionalDecl(p, "Parent", type)) {
        const str = @typeInfo(p).Struct;
        if (str.layout != .Extern) {
            @compileError("Vtable struct must be extern");
        }
        const f = str.fields;
        var i: usize = f.len;
        inline while (i > 0) {
            i -= 1;
            const entry = f[i];
            const ptrType = @typeInfo(entry.type).Pointer;
            if (ptrType.size != .One or !ptrType.is_const) {
                @compileError("Vtable function pointer must be single-item const pointer");
            }
            const fnType = @typeInfo(ptrType.child).Fn;
            if (fnType.calling_convention != .C) {
                @compileError("Function pointer in vtable must have C calling convention");
            }
            entries = [1]Type.StructField{entry} ++ entries;
        }
    }

    return @Type(Type{ .Struct = .{
        .fields = entries,
        .decls = &[0]Type.Declaration{},
        .layout = .Extern,
        .is_tuple = false,
    } });
}

const testing = @import("std").testing;
const expectEql = testing.expectEqual;
const TypeId = @import("std").builtin.TypeId;

test "Merging VTables" {
    const A = extern struct {
        testFn1: *const fn (self: *const anyopaque, int: i32) callconv(.C) i32,
        testFn2: *const fn (self: *const anyopaque, int: u32) callconv(.C) i32,

        const interfaceId = parseUuidLiteral("aa000000-0000-0000-c000-000000000046");
    };

    const B = extern struct {
        testFn3: *const fn (self: *const anyopaque, float: f32) callconv(.C) i32,
        testFn4: *const fn (self: *const anyopaque, float: f64) callconv(.C) i32,

        const Parent = A;
        const interfaceId = parseUuidLiteral("bb000000-0000-0000-c000-000000000046");
    };

    const Merged = MergeVTable(B);
    testing.refAllDecls(A);
    testing.refAllDecls(B);
    testing.refAllDecls(Merged);

    const info = @typeInfo(Merged);
    try expectEql(.Struct, @as(TypeId, info));
    const strInfo = info.Struct;
    try expectEql(4, strInfo.fields.len);
    try expectEql(@TypeOf(@as(A, undefined).testFn1), strInfo.fields[0].type);
    try expectEql(@TypeOf(@as(A, undefined).testFn1), @TypeOf(@as(Merged, undefined).testFn1));
    try expectEql(@TypeOf(@as(A, undefined).testFn2), strInfo.fields[1].type);
    try expectEql(@TypeOf(@as(A, undefined).testFn2), @TypeOf(@as(Merged, undefined).testFn2));
    try expectEql(@TypeOf(@as(B, undefined).testFn3), strInfo.fields[2].type);
    try expectEql(@TypeOf(@as(B, undefined).testFn3), @TypeOf(@as(Merged, undefined).testFn3));
    try expectEql(@TypeOf(@as(B, undefined).testFn4), strInfo.fields[3].type);
    try expectEql(@TypeOf(@as(B, undefined).testFn4), @TypeOf(@as(Merged, undefined).testFn4));
}
