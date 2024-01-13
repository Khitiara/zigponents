const std = @import("std");
const testing = std.testing;
const utils = @import("utils.zig");

pub fn getInterfaceId(comptime T: type) utils.Uuid {
    comptime {
        if (@typeInfo(T) != std.builtin.TypeId.Struct) {
            @compileError("COM Interface must be struct");
        }
        if (!@typeInfo(@TypeOf(&T.interfaceId)).Pointer.is_const) {
            @compileError("InterfaceId must be a constant");
        }
    }
    return T.interfaceId;
}

const sOk: i32 = 0x00000000;
const eNoInterface: i32 = 0x80004002;

pub const QueryInterfaceError = error{ NoInterface, UnknownError };

pub const MergeVTable = utils.MergeVTable;

pub const IUnknown = extern struct {
    vtbl: *const Vtable,

    pub const Vtable = extern struct {
        queryInterface: *const fn (this: *const IUnknown, riid: utils.Uuid, ppvObject: *?*const anyopaque) callconv(.C) i32,
        addRef: *const fn (this: *const IUnknown) callconv(.C) u32,
        release: *const fn (this: *const IUnknown) callconv(.C) u32,
    };
    pub const interfaceId = utils.parseUuidLiteral("00000000-0000-0000-c000-000000000046");
};

fn getIUnknown(obj: anytype) *const IUnknown {
    comptime {
        switch (@typeInfo(@TypeOf(obj))) {
            .Pointer => |p| if (!p.is_const)
                @compileError("Cannot queryInterface a non-const pointer"),
            else => @compileError("Cannot queryInterface a non-pointer"),
        }
    }
    return @ptrCast(obj);
}

fn assertDecl(comptime T: anytype, comptime name: []const u8, comptime Decl: type) void {
    if (!@hasDecl(T, name)) @compileError("Interface missing declaration: " ++ name ++ @typeName(Decl));
    const Found = @TypeOf(@field(T, name));
    if (Found != Decl) @compileError("Interface decl '" ++ name ++ "'\n\texpected type: " ++ @typeName(Decl) ++ "\n\t   found type: " ++ @typeName(Found));
}

fn assertField(comptime T: anytype, comptime name: []const u8, comptime Field: type) void {
    if (!@hasField(T, name)) @compileError("Interface missing field: ." ++ name ++ @typeName(Field));
    const Found = @TypeOf(@field(@as(T, undefined), name));
    if (Found != Field) @compileError("Interface field '" ++ name ++ "'\n\texpected type: " ++ @typeName(Field) ++ "\n\t   found type: " ++ @typeName(Found));
}

pub fn queryInterface(obj: anytype, comptime iface: type) QueryInterfaceError!*const iface {
    const unknown: *const IUnknown = getIUnknown(obj);
    var output: *const iface = undefined;
    return switch (unknown.vtbl.queryInterface(unknown, getInterfaceId(iface), &output)) {
        sOk => return output,
        eNoInterface => return error.NoInterface,
        else => return error.UnknownError,
    };
}

pub fn addRef(obj: anytype) u32 {
    const unknown: *const IUnknown = getIUnknown(obj);
    return unknown.vtbl.addRef(unknown);
}

pub fn release(obj: anytype) u32 {
    const unknown: *const IUnknown = getIUnknown(obj);
    return unknown.vtbl.release(unknown);
}