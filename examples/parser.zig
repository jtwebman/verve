const std = @import("std");

// ── Runtime helpers ──────────────────────────────
fn verve_write(fd: i64, ptr: [*]const u8, len: i64) void {
    const f = std.posix.STDOUT_FILENO;
    _ = fd;
    const actual_len: usize = if (len > 0) @intCast(@as(u64, @bitCast(len))) else blk: { var l: usize = 0; while (ptr[l] != 0) l += 1; break :blk l; };
    const slice = ptr[0..actual_len];
    _ = std.posix.write(f, slice) catch 0;
}

const List = struct {
    items: [*]i64,
    len: i64,
    cap: i64,
    pub fn init() List {
        const mem = std.heap.page_allocator.alloc(i64, 256) catch return .{ .items = undefined, .len = 0, .cap = 0 };
        return .{ .items = @constCast(mem.ptr), .len = 0, .cap = 256 };
    }
    pub fn append(self: *List, val: i64) void {
        const idx: usize = @intCast(@as(u64, @bitCast(self.len)));
        self.items[idx] = val;
        self.len += 1;
    }
    pub fn get(self: *const List, idx: i64) i64 {
        return self.items[@intCast(@as(u64, @bitCast(idx)))];
    }
};

const Tagged = struct { tag: i64, value: i64 };
fn makeTagged(tag: i64, value: i64) i64 {
    const t = std.heap.page_allocator.create(Tagged) catch return 0;
    t.* = .{ .tag = tag, .value = value };
    return @intCast(@intFromPtr(t));
}
fn getTag(ptr: i64) i64 {
    if (ptr == 0) return -1;
    return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).tag;
}
fn getTagValue(ptr: i64) i64 {
    if (ptr == 0) return 0;
    return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).value;
}

fn fileOpen(path_ptr: i64, path_len: i64) i64 {
    const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(path_ptr))))));
    const len: usize = if (path_len > 0) @intCast(@as(u64, @bitCast(path_len))) else blk: { var l: usize = 0; while (ptr[l] != 0) l += 1; break :blk l; };
    const path = ptr[0..len];
    const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 10 * 1024 * 1024) catch return makeTagged(1, 0);
    // Store data ptr and len as a stream (two i64s)
    const stream = std.heap.page_allocator.alloc(i64, 3) catch return makeTagged(1, 0);
    stream[0] = @intCast(@intFromPtr(data.ptr));
    stream[1] = @intCast(data.len);
    stream[2] = 0; // read position
    return makeTagged(0, @intCast(@intFromPtr(stream.ptr)));
}

fn streamReadAll(stream_ptr: i64) i64 {
    const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));
    return s[0]; // return data ptr
}
fn streamReadAllLen(stream_ptr: i64) i64 {
    const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));
    return s[1]; // return data len
}

fn strEql(a: [*]const u8, a_len: i64, b: [*]const u8, b_len: i64) bool {
    if (a_len != b_len) return false;
    const len: usize = @intCast(@as(u64, @bitCast(a_len)));
    return std.mem.eql(u8, a[0..len], b[0..len]);
}

fn verve_Tokenizer_single_char_kind(param_b: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_b;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = 40;
                r2 = if (r0 == r1) @as(i64, 1) else @as(i64, 0);
                block = if (r2 != 0) 2 else 3; continue;
            },
            1 => {
                block = 2;
            },
            2 => {
                r3 = @intCast(@intFromPtr(@as([*]const u8, "lparen")));
                r4 = 6;
                return r3;
            },
            3 => {
                r5 = 41;
                r6 = if (r0 == r5) @as(i64, 1) else @as(i64, 0);
                block = if (r6 != 0) 4 else 5; continue;
            },
            4 => {
                r7 = @intCast(@intFromPtr(@as([*]const u8, "rparen")));
                r8 = 6;
                return r7;
            },
            5 => {
                r9 = 59;
                r10 = if (r0 == r9) @as(i64, 1) else @as(i64, 0);
                block = if (r10 != 0) 6 else 7; continue;
            },
            6 => {
                r11 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r12 = 4;
                return r11;
            },
            7 => {
                r13 = 58;
                r14 = if (r0 == r13) @as(i64, 1) else @as(i64, 0);
                block = if (r14 != 0) 8 else 9; continue;
            },
            8 => {
                r15 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r16 = 5;
                return r15;
            },
            9 => {
                r17 = 44;
                r18 = if (r0 == r17) @as(i64, 1) else @as(i64, 0);
                block = if (r18 != 0) 10 else 11; continue;
            },
            10 => {
                r19 = @intCast(@intFromPtr(@as([*]const u8, "comma")));
                r20 = 5;
                return r19;
            },
            11 => {
                r21 = 60;
                r22 = if (r0 == r21) @as(i64, 1) else @as(i64, 0);
                block = if (r22 != 0) 12 else 13; continue;
            },
            12 => {
                r23 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r24 = 2;
                return r23;
            },
            13 => {
                r25 = 62;
                r26 = if (r0 == r25) @as(i64, 1) else @as(i64, 0);
                block = if (r26 != 0) 14 else 15; continue;
            },
            14 => {
                r27 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r28 = 2;
                return r27;
            },
            15 => {
                r29 = 61;
                r30 = if (r0 == r29) @as(i64, 1) else @as(i64, 0);
                block = if (r30 != 0) 16 else 17; continue;
            },
            16 => {
                r31 = @intCast(@intFromPtr(@as([*]const u8, "eq")));
                r32 = 2;
                return r31;
            },
            17 => {
                r33 = 43;
                r34 = if (r0 == r33) @as(i64, 1) else @as(i64, 0);
                block = if (r34 != 0) 18 else 19; continue;
            },
            18 => {
                r35 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r36 = 2;
                return r35;
            },
            19 => {
                r37 = 42;
                r38 = if (r0 == r37) @as(i64, 1) else @as(i64, 0);
                block = if (r38 != 0) 20 else 21; continue;
            },
            20 => {
                r39 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r40 = 2;
                return r39;
            },
            21 => {
                r41 = 37;
                r42 = if (r0 == r41) @as(i64, 1) else @as(i64, 0);
                block = if (r42 != 0) 22 else 23; continue;
            },
            22 => {
                r43 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r44 = 2;
                return r43;
            },
            23 => {
                r45 = 33;
                r46 = if (r0 == r45) @as(i64, 1) else @as(i64, 0);
                block = if (r46 != 0) 24 else 25; continue;
            },
            24 => {
                r47 = @intCast(@intFromPtr(@as([*]const u8, "bang")));
                r48 = 4;
                return r47;
            },
            25 => {
                r49 = @intCast(@intFromPtr(@as([*]const u8, "none")));
                r50 = 4;
                return r49;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Tokenizer_tokenize(param_source: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var r84: i64 = 0;
    _ = &r84;
    var r85: i64 = 0;
    _ = &r85;
    var r86: i64 = 0;
    _ = &r86;
    var r87: i64 = 0;
    _ = &r87;
    var r88: i64 = 0;
    _ = &r88;
    var r89: i64 = 0;
    _ = &r89;
    var r90: i64 = 0;
    _ = &r90;
    var r91: i64 = 0;
    _ = &r91;
    var r92: i64 = 0;
    _ = &r92;
    var r93: i64 = 0;
    _ = &r93;
    var r94: i64 = 0;
    _ = &r94;
    var r95: i64 = 0;
    _ = &r95;
    var r96: i64 = 0;
    _ = &r96;
    var r97: i64 = 0;
    _ = &r97;
    var r98: i64 = 0;
    _ = &r98;
    var r99: i64 = 0;
    _ = &r99;
    var r100: i64 = 0;
    _ = &r100;
    var r101: i64 = 0;
    _ = &r101;
    var r102: i64 = 0;
    _ = &r102;
    var r103: i64 = 0;
    _ = &r103;
    var r104: i64 = 0;
    _ = &r104;
    var r105: i64 = 0;
    _ = &r105;
    var r106: i64 = 0;
    _ = &r106;
    var r107: i64 = 0;
    _ = &r107;
    var r108: i64 = 0;
    _ = &r108;
    var r109: i64 = 0;
    _ = &r109;
    var r110: i64 = 0;
    _ = &r110;
    var r111: i64 = 0;
    _ = &r111;
    var r112: i64 = 0;
    _ = &r112;
    var r113: i64 = 0;
    _ = &r113;
    var r114: i64 = 0;
    _ = &r114;
    var r115: i64 = 0;
    _ = &r115;
    var r116: i64 = 0;
    _ = &r116;
    var r117: i64 = 0;
    _ = &r117;
    var r118: i64 = 0;
    _ = &r118;
    var r119: i64 = 0;
    _ = &r119;
    var r120: i64 = 0;
    _ = &r120;
    var r121: i64 = 0;
    _ = &r121;
    var r122: i64 = 0;
    _ = &r122;
    var r123: i64 = 0;
    _ = &r123;
    var r124: i64 = 0;
    _ = &r124;
    var r125: i64 = 0;
    _ = &r125;
    var r126: i64 = 0;
    _ = &r126;
    var r127: i64 = 0;
    _ = &r127;
    var r128: i64 = 0;
    _ = &r128;
    var r129: i64 = 0;
    _ = &r129;
    var r130: i64 = 0;
    _ = &r130;
    var r131: i64 = 0;
    _ = &r131;
    var r132: i64 = 0;
    _ = &r132;
    var r133: i64 = 0;
    _ = &r133;
    var r134: i64 = 0;
    _ = &r134;
    var r135: i64 = 0;
    _ = &r135;
    var r136: i64 = 0;
    _ = &r136;
    var r137: i64 = 0;
    _ = &r137;
    var r138: i64 = 0;
    _ = &r138;
    var r139: i64 = 0;
    _ = &r139;
    var r140: i64 = 0;
    _ = &r140;
    var r141: i64 = 0;
    _ = &r141;
    var r142: i64 = 0;
    _ = &r142;
    var r143: i64 = 0;
    _ = &r143;
    var r144: i64 = 0;
    _ = &r144;
    var r145: i64 = 0;
    _ = &r145;
    var r146: i64 = 0;
    _ = &r146;
    var r147: i64 = 0;
    _ = &r147;
    var r148: i64 = 0;
    _ = &r148;
    var r149: i64 = 0;
    _ = &r149;
    var r150: i64 = 0;
    _ = &r150;
    var r151: i64 = 0;
    _ = &r151;
    var r152: i64 = 0;
    _ = &r152;
    var r153: i64 = 0;
    _ = &r153;
    var r154: i64 = 0;
    _ = &r154;
    var r155: i64 = 0;
    _ = &r155;
    var r156: i64 = 0;
    _ = &r156;
    var r157: i64 = 0;
    _ = &r157;
    var r158: i64 = 0;
    _ = &r158;
    var r159: i64 = 0;
    _ = &r159;
    var r160: i64 = 0;
    _ = &r160;
    var r161: i64 = 0;
    _ = &r161;
    var r162: i64 = 0;
    _ = &r162;
    var r163: i64 = 0;
    _ = &r163;
    var r164: i64 = 0;
    _ = &r164;
    var r165: i64 = 0;
    _ = &r165;
    var r166: i64 = 0;
    _ = &r166;
    var r167: i64 = 0;
    _ = &r167;
    var r168: i64 = 0;
    _ = &r168;
    var r169: i64 = 0;
    _ = &r169;
    var r170: i64 = 0;
    _ = &r170;
    var r171: i64 = 0;
    _ = &r171;
    var r172: i64 = 0;
    _ = &r172;
    var r173: i64 = 0;
    _ = &r173;
    var r174: i64 = 0;
    _ = &r174;
    var r175: i64 = 0;
    _ = &r175;
    var r176: i64 = 0;
    _ = &r176;
    var r177: i64 = 0;
    _ = &r177;
    var r178: i64 = 0;
    _ = &r178;
    var r179: i64 = 0;
    _ = &r179;
    var r180: i64 = 0;
    _ = &r180;
    var r181: i64 = 0;
    _ = &r181;
    var r182: i64 = 0;
    _ = &r182;
    var r183: i64 = 0;
    _ = &r183;
    var r184: i64 = 0;
    _ = &r184;
    var r185: i64 = 0;
    _ = &r185;
    var r186: i64 = 0;
    _ = &r186;
    var r187: i64 = 0;
    _ = &r187;
    var r188: i64 = 0;
    _ = &r188;
    var r189: i64 = 0;
    _ = &r189;
    var r190: i64 = 0;
    _ = &r190;
    var r191: i64 = 0;
    _ = &r191;
    var r192: i64 = 0;
    _ = &r192;
    var r193: i64 = 0;
    _ = &r193;
    var r194: i64 = 0;
    _ = &r194;
    var r195: i64 = 0;
    _ = &r195;
    var r196: i64 = 0;
    _ = &r196;
    var r197: i64 = 0;
    _ = &r197;
    var r198: i64 = 0;
    _ = &r198;
    var r199: i64 = 0;
    _ = &r199;
    var r200: i64 = 0;
    _ = &r200;
    var r201: i64 = 0;
    _ = &r201;
    var r202: i64 = 0;
    _ = &r202;
    var r203: i64 = 0;
    _ = &r203;
    var r204: i64 = 0;
    _ = &r204;
    var r205: i64 = 0;
    _ = &r205;
    var r206: i64 = 0;
    _ = &r206;
    var r207: i64 = 0;
    _ = &r207;
    var r208: i64 = 0;
    _ = &r208;
    var r209: i64 = 0;
    _ = &r209;
    var r210: i64 = 0;
    _ = &r210;
    var r211: i64 = 0;
    _ = &r211;
    var r212: i64 = 0;
    _ = &r212;
    var r213: i64 = 0;
    _ = &r213;
    var r214: i64 = 0;
    _ = &r214;
    var r215: i64 = 0;
    _ = &r215;
    var r216: i64 = 0;
    _ = &r216;
    var r217: i64 = 0;
    _ = &r217;
    var r218: i64 = 0;
    _ = &r218;
    var r219: i64 = 0;
    _ = &r219;
    var r220: i64 = 0;
    _ = &r220;
    var r221: i64 = 0;
    _ = &r221;
    var r222: i64 = 0;
    _ = &r222;
    var r223: i64 = 0;
    _ = &r223;
    var r224: i64 = 0;
    _ = &r224;
    var r225: i64 = 0;
    _ = &r225;
    var r226: i64 = 0;
    _ = &r226;
    var r227: i64 = 0;
    _ = &r227;
    var r228: i64 = 0;
    _ = &r228;
    var r229: i64 = 0;
    _ = &r229;
    var r230: i64 = 0;
    _ = &r230;
    var r231: i64 = 0;
    _ = &r231;
    var r232: i64 = 0;
    _ = &r232;
    var r233: i64 = 0;
    _ = &r233;
    var r234: i64 = 0;
    _ = &r234;
    var r235: i64 = 0;
    _ = &r235;
    var r236: i64 = 0;
    _ = &r236;
    var r237: i64 = 0;
    _ = &r237;
    var r238: i64 = 0;
    _ = &r238;
    var r239: i64 = 0;
    _ = &r239;
    var r240: i64 = 0;
    _ = &r240;
    var r241: i64 = 0;
    _ = &r241;
    var r242: i64 = 0;
    _ = &r242;
    var r243: i64 = 0;
    _ = &r243;
    var r244: i64 = 0;
    _ = &r244;
    var r245: i64 = 0;
    _ = &r245;
    var r246: i64 = 0;
    _ = &r246;
    var r247: i64 = 0;
    _ = &r247;
    var r248: i64 = 0;
    _ = &r248;
    var r249: i64 = 0;
    _ = &r249;
    var r250: i64 = 0;
    _ = &r250;
    var r251: i64 = 0;
    _ = &r251;
    var r252: i64 = 0;
    _ = &r252;
    var r253: i64 = 0;
    _ = &r253;
    var r254: i64 = 0;
    _ = &r254;
    var r255: i64 = 0;
    _ = &r255;
    var r256: i64 = 0;
    _ = &r256;
    var r257: i64 = 0;
    _ = &r257;
    var r258: i64 = 0;
    _ = &r258;
    var r259: i64 = 0;
    _ = &r259;
    var r260: i64 = 0;
    _ = &r260;
    var r261: i64 = 0;
    _ = &r261;
    var r262: i64 = 0;
    _ = &r262;
    var r263: i64 = 0;
    _ = &r263;
    var r264: i64 = 0;
    _ = &r264;
    var r265: i64 = 0;
    _ = &r265;
    var r266: i64 = 0;
    _ = &r266;
    var r267: i64 = 0;
    _ = &r267;
    var r268: i64 = 0;
    _ = &r268;
    var r269: i64 = 0;
    _ = &r269;
    var r270: i64 = 0;
    _ = &r270;
    var r271: i64 = 0;
    _ = &r271;
    var r272: i64 = 0;
    _ = &r272;
    var r273: i64 = 0;
    _ = &r273;
    var r274: i64 = 0;
    _ = &r274;
    var r275: i64 = 0;
    _ = &r275;
    var r276: i64 = 0;
    _ = &r276;
    var r277: i64 = 0;
    _ = &r277;
    var r278: i64 = 0;
    _ = &r278;
    var r279: i64 = 0;
    _ = &r279;
    var r280: i64 = 0;
    _ = &r280;
    var r281: i64 = 0;
    _ = &r281;
    var r282: i64 = 0;
    _ = &r282;
    var r283: i64 = 0;
    _ = &r283;
    var r284: i64 = 0;
    _ = &r284;
    var r285: i64 = 0;
    _ = &r285;
    var r286: i64 = 0;
    _ = &r286;
    var r287: i64 = 0;
    _ = &r287;
    var r288: i64 = 0;
    _ = &r288;
    var r289: i64 = 0;
    _ = &r289;
    var r290: i64 = 0;
    _ = &r290;
    var r291: i64 = 0;
    _ = &r291;
    var r292: i64 = 0;
    _ = &r292;
    var r293: i64 = 0;
    _ = &r293;
    var r294: i64 = 0;
    _ = &r294;
    var r295: i64 = 0;
    _ = &r295;
    var r296: i64 = 0;
    _ = &r296;
    var r297: i64 = 0;
    _ = &r297;
    var r298: i64 = 0;
    _ = &r298;
    var r299: i64 = 0;
    _ = &r299;
    var r300: i64 = 0;
    _ = &r300;
    var r301: i64 = 0;
    _ = &r301;
    var r302: i64 = 0;
    _ = &r302;
    var r303: i64 = 0;
    _ = &r303;
    var r304: i64 = 0;
    _ = &r304;
    var r305: i64 = 0;
    _ = &r305;
    var r306: i64 = 0;
    _ = &r306;
    var r307: i64 = 0;
    _ = &r307;
    var r308: i64 = 0;
    _ = &r308;
    var r309: i64 = 0;
    _ = &r309;
    var r310: i64 = 0;
    _ = &r310;
    var r311: i64 = 0;
    _ = &r311;
    var r312: i64 = 0;
    _ = &r312;
    var r313: i64 = 0;
    _ = &r313;
    var r314: i64 = 0;
    _ = &r314;
    var r315: i64 = 0;
    _ = &r315;
    var r316: i64 = 0;
    _ = &r316;
    var r317: i64 = 0;
    _ = &r317;
    var r318: i64 = 0;
    _ = &r318;
    var r319: i64 = 0;
    _ = &r319;
    var r320: i64 = 0;
    _ = &r320;
    var r321: i64 = 0;
    _ = &r321;
    var r322: i64 = 0;
    _ = &r322;
    var r323: i64 = 0;
    _ = &r323;
    var r324: i64 = 0;
    _ = &r324;
    var r325: i64 = 0;
    _ = &r325;
    var r326: i64 = 0;
    _ = &r326;
    var r327: i64 = 0;
    _ = &r327;
    var r328: i64 = 0;
    _ = &r328;
    var r329: i64 = 0;
    _ = &r329;
    var r330: i64 = 0;
    _ = &r330;
    var r331: i64 = 0;
    _ = &r331;
    var r332: i64 = 0;
    _ = &r332;
    var r333: i64 = 0;
    _ = &r333;
    var r334: i64 = 0;
    _ = &r334;
    var r335: i64 = 0;
    _ = &r335;
    var r336: i64 = 0;
    _ = &r336;
    var r337: i64 = 0;
    _ = &r337;
    var r338: i64 = 0;
    _ = &r338;
    var r339: i64 = 0;
    _ = &r339;
    var r340: i64 = 0;
    _ = &r340;
    var r341: i64 = 0;
    _ = &r341;
    var r342: i64 = 0;
    _ = &r342;
    var r343: i64 = 0;
    _ = &r343;
    var r344: i64 = 0;
    _ = &r344;
    var r345: i64 = 0;
    _ = &r345;
    var r346: i64 = 0;
    _ = &r346;
    var r347: i64 = 0;
    _ = &r347;
    var r348: i64 = 0;
    _ = &r348;
    var r349: i64 = 0;
    _ = &r349;
    var r350: i64 = 0;
    _ = &r350;
    var r351: i64 = 0;
    _ = &r351;
    var r352: i64 = 0;
    _ = &r352;
    var r353: i64 = 0;
    _ = &r353;
    var r354: i64 = 0;
    _ = &r354;
    var r355: i64 = 0;
    _ = &r355;
    var r356: i64 = 0;
    _ = &r356;
    var r357: i64 = 0;
    _ = &r357;
    var r358: i64 = 0;
    _ = &r358;
    var r359: i64 = 0;
    _ = &r359;
    var r360: i64 = 0;
    _ = &r360;
    var r361: i64 = 0;
    _ = &r361;
    var r362: i64 = 0;
    _ = &r362;
    var r363: i64 = 0;
    _ = &r363;
    var r364: i64 = 0;
    _ = &r364;
    var r365: i64 = 0;
    _ = &r365;
    var r366: i64 = 0;
    _ = &r366;
    var r367: i64 = 0;
    _ = &r367;
    var r368: i64 = 0;
    _ = &r368;
    var r369: i64 = 0;
    _ = &r369;
    var r370: i64 = 0;
    _ = &r370;
    var r371: i64 = 0;
    _ = &r371;
    var r372: i64 = 0;
    _ = &r372;
    var r373: i64 = 0;
    _ = &r373;
    var r374: i64 = 0;
    _ = &r374;
    var r375: i64 = 0;
    _ = &r375;
    var r376: i64 = 0;
    _ = &r376;
    var r377: i64 = 0;
    _ = &r377;
    var r378: i64 = 0;
    _ = &r378;
    var r379: i64 = 0;
    _ = &r379;
    var r380: i64 = 0;
    _ = &r380;
    var r381: i64 = 0;
    _ = &r381;
    var r382: i64 = 0;
    _ = &r382;
    var r383: i64 = 0;
    _ = &r383;
    var r384: i64 = 0;
    _ = &r384;
    var r385: i64 = 0;
    _ = &r385;
    var r386: i64 = 0;
    _ = &r386;
    var r387: i64 = 0;
    _ = &r387;
    var r388: i64 = 0;
    _ = &r388;
    var r389: i64 = 0;
    _ = &r389;
    var r390: i64 = 0;
    _ = &r390;
    var r391: i64 = 0;
    _ = &r391;
    var r392: i64 = 0;
    _ = &r392;
    var r393: i64 = 0;
    _ = &r393;
    var r394: i64 = 0;
    _ = &r394;
    var r395: i64 = 0;
    _ = &r395;
    var r396: i64 = 0;
    _ = &r396;
    var r397: i64 = 0;
    _ = &r397;
    var r398: i64 = 0;
    _ = &r398;
    var r399: i64 = 0;
    _ = &r399;
    var r400: i64 = 0;
    _ = &r400;
    var r401: i64 = 0;
    _ = &r401;
    var r402: i64 = 0;
    _ = &r402;
    var r403: i64 = 0;
    _ = &r403;
    var r404: i64 = 0;
    _ = &r404;
    var r405: i64 = 0;
    _ = &r405;
    var r406: i64 = 0;
    _ = &r406;
    var r407: i64 = 0;
    _ = &r407;
    var r408: i64 = 0;
    _ = &r408;
    var r409: i64 = 0;
    _ = &r409;
    var r410: i64 = 0;
    _ = &r410;
    var r411: i64 = 0;
    _ = &r411;
    var r412: i64 = 0;
    _ = &r412;
    var r413: i64 = 0;
    _ = &r413;
    var r414: i64 = 0;
    _ = &r414;
    var r415: i64 = 0;
    _ = &r415;
    var r416: i64 = 0;
    _ = &r416;
    var r417: i64 = 0;
    _ = &r417;
    var r418: i64 = 0;
    _ = &r418;
    var r419: i64 = 0;
    _ = &r419;
    var r420: i64 = 0;
    _ = &r420;
    var r421: i64 = 0;
    _ = &r421;
    var r422: i64 = 0;
    _ = &r422;
    var r423: i64 = 0;
    _ = &r423;
    var r424: i64 = 0;
    _ = &r424;
    var r425: i64 = 0;
    _ = &r425;
    var r426: i64 = 0;
    _ = &r426;
    var r427: i64 = 0;
    _ = &r427;
    var r428: i64 = 0;
    _ = &r428;
    var r429: i64 = 0;
    _ = &r429;
    var r430: i64 = 0;
    _ = &r430;
    var r431: i64 = 0;
    _ = &r431;
    var r432: i64 = 0;
    _ = &r432;
    var r433: i64 = 0;
    _ = &r433;
    var r434: i64 = 0;
    _ = &r434;
    var r435: i64 = 0;
    _ = &r435;
    var r436: i64 = 0;
    _ = &r436;
    var r437: i64 = 0;
    _ = &r437;
    var r438: i64 = 0;
    _ = &r438;
    var r439: i64 = 0;
    _ = &r439;
    var r440: i64 = 0;
    _ = &r440;
    var r441: i64 = 0;
    _ = &r441;
    var r442: i64 = 0;
    _ = &r442;
    var r443: i64 = 0;
    _ = &r443;
    var r444: i64 = 0;
    _ = &r444;
    var r445: i64 = 0;
    _ = &r445;
    var r446: i64 = 0;
    _ = &r446;
    var r447: i64 = 0;
    _ = &r447;
    var r448: i64 = 0;
    _ = &r448;
    var r449: i64 = 0;
    _ = &r449;
    var r450: i64 = 0;
    _ = &r450;
    var r451: i64 = 0;
    _ = &r451;
    var r452: i64 = 0;
    _ = &r452;
    var r453: i64 = 0;
    _ = &r453;
    var r454: i64 = 0;
    _ = &r454;
    var r455: i64 = 0;
    _ = &r455;
    var r456: i64 = 0;
    _ = &r456;
    var r457: i64 = 0;
    _ = &r457;
    var r458: i64 = 0;
    _ = &r458;
    var r459: i64 = 0;
    _ = &r459;
    var r460: i64 = 0;
    _ = &r460;
    var r461: i64 = 0;
    _ = &r461;
    var r462: i64 = 0;
    _ = &r462;
    var r463: i64 = 0;
    _ = &r463;
    var r464: i64 = 0;
    _ = &r464;
    var r465: i64 = 0;
    _ = &r465;
    var r466: i64 = 0;
    _ = &r466;
    var r467: i64 = 0;
    _ = &r467;
    var r468: i64 = 0;
    _ = &r468;
    var r469: i64 = 0;
    _ = &r469;
    var r470: i64 = 0;
    _ = &r470;
    var r471: i64 = 0;
    _ = &r471;
    var r472: i64 = 0;
    _ = &r472;
    var r473: i64 = 0;
    _ = &r473;
    var r474: i64 = 0;
    _ = &r474;
    var r475: i64 = 0;
    _ = &r475;
    var r476: i64 = 0;
    _ = &r476;
    var r477: i64 = 0;
    _ = &r477;
    var r478: i64 = 0;
    _ = &r478;
    var r479: i64 = 0;
    _ = &r479;
    var r480: i64 = 0;
    _ = &r480;
    var r481: i64 = 0;
    _ = &r481;
    var r482: i64 = 0;
    _ = &r482;
    var r483: i64 = 0;
    _ = &r483;
    var r484: i64 = 0;
    _ = &r484;
    var r485: i64 = 0;
    _ = &r485;
    var r486: i64 = 0;
    _ = &r486;
    var r487: i64 = 0;
    _ = &r487;
    var r488: i64 = 0;
    _ = &r488;
    var r489: i64 = 0;
    _ = &r489;
    var r490: i64 = 0;
    _ = &r490;
    var r491: i64 = 0;
    _ = &r491;
    var r492: i64 = 0;
    _ = &r492;
    var r493: i64 = 0;
    _ = &r493;
    var r494: i64 = 0;
    _ = &r494;
    var r495: i64 = 0;
    _ = &r495;
    var r496: i64 = 0;
    _ = &r496;
    var r497: i64 = 0;
    _ = &r497;
    var r498: i64 = 0;
    _ = &r498;
    var r499: i64 = 0;
    _ = &r499;
    var r500: i64 = 0;
    _ = &r500;
    var r501: i64 = 0;
    _ = &r501;
    var r502: i64 = 0;
    _ = &r502;
    var r503: i64 = 0;
    _ = &r503;
    var r504: i64 = 0;
    _ = &r504;
    var r505: i64 = 0;
    _ = &r505;
    var r506: i64 = 0;
    _ = &r506;
    var r507: i64 = 0;
    _ = &r507;
    var r508: i64 = 0;
    _ = &r508;
    var r509: i64 = 0;
    _ = &r509;
    var r510: i64 = 0;
    _ = &r510;
    var r511: i64 = 0;
    _ = &r511;
    var r512: i64 = 0;
    _ = &r512;
    var r513: i64 = 0;
    _ = &r513;
    var r514: i64 = 0;
    _ = &r514;
    var r515: i64 = 0;
    _ = &r515;
    var r516: i64 = 0;
    _ = &r516;
    var r517: i64 = 0;
    _ = &r517;
    var r518: i64 = 0;
    _ = &r518;
    var r519: i64 = 0;
    _ = &r519;
    var r520: i64 = 0;
    _ = &r520;
    var r521: i64 = 0;
    _ = &r521;
    var r522: i64 = 0;
    _ = &r522;
    var r523: i64 = 0;
    _ = &r523;
    var r524: i64 = 0;
    _ = &r524;
    var r525: i64 = 0;
    _ = &r525;
    var r526: i64 = 0;
    _ = &r526;
    var r527: i64 = 0;
    _ = &r527;
    var r528: i64 = 0;
    _ = &r528;
    var r529: i64 = 0;
    _ = &r529;
    var r530: i64 = 0;
    _ = &r530;
    var r531: i64 = 0;
    _ = &r531;
    var r532: i64 = 0;
    _ = &r532;
    var r533: i64 = 0;
    _ = &r533;
    var r534: i64 = 0;
    _ = &r534;
    var r535: i64 = 0;
    _ = &r535;
    var r536: i64 = 0;
    _ = &r536;
    var r537: i64 = 0;
    _ = &r537;
    var r538: i64 = 0;
    _ = &r538;
    var r539: i64 = 0;
    _ = &r539;
    var r540: i64 = 0;
    _ = &r540;
    var r541: i64 = 0;
    _ = &r541;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_source;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                var list_0 = List.init();
                r0 = @intCast(@intFromPtr(&list_0));
                locals[1] = r0;
                r1 = 0;
                locals[2] = r1;
                r2 = locals[0];
                r3 = locals[3];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r2)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r4 = @intCast(sl); }
                locals[4] = r4;
                block = 1; continue;
            },
            1 => {
                r5 = locals[2];
                r6 = locals[4];
                r7 = if (r5 < r6) @as(i64, 1) else @as(i64, 0);
                block = if (r7 != 0) 2 else 3; continue;
            },
            2 => {
                r8 = locals[0];
                r9 = locals[3];
                r10 = locals[2];
                r11 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r8))))))[
@intCast(@as(u64, @bitCast(r10)))];
                locals[5] = r11;
                r12 = locals[5];
                r13 = 32;
                r14 = if (r12 == r13) @as(i64, 1) else @as(i64, 0);
                block = if (r14 != 0) 4 else 6; continue;
            },
            3 => {
                r541 = locals[1];
                return r541;
            },
            4 => {
                r15 = locals[2];
                r16 = 1;
                r17 = r15 +% r16;
                locals[2] = r17;
                block = 1; continue;
            },
            5 => {
                block = 6;
            },
            6 => {
                r18 = locals[5];
                r19 = 9;
                r20 = if (r18 == r19) @as(i64, 1) else @as(i64, 0);
                block = if (r20 != 0) 7 else 9; continue;
            },
            7 => {
                r21 = locals[2];
                r22 = 1;
                r23 = r21 +% r22;
                locals[2] = r23;
                block = 1; continue;
            },
            8 => {
                block = 9;
            },
            9 => {
                r24 = locals[5];
                r25 = 10;
                r26 = if (r24 == r25) @as(i64, 1) else @as(i64, 0);
                block = if (r26 != 0) 10 else 12; continue;
            },
            10 => {
                r27 = locals[2];
                r28 = 1;
                r29 = r27 +% r28;
                locals[2] = r29;
                block = 1; continue;
            },
            11 => {
                block = 12;
            },
            12 => {
                r30 = locals[5];
                r31 = 13;
                r32 = if (r30 == r31) @as(i64, 1) else @as(i64, 0);
                block = if (r32 != 0) 13 else 15; continue;
            },
            13 => {
                r33 = locals[2];
                r34 = 1;
                r35 = r33 +% r34;
                locals[2] = r35;
                block = 1; continue;
            },
            14 => {
                block = 15;
            },
            15 => {
                r36 = locals[5];
                r37 = 47;
                r38 = if (r36 == r37) @as(i64, 1) else @as(i64, 0);
                block = if (r38 != 0) 16 else 18; continue;
            },
            16 => {
                r39 = locals[2];
                r40 = 1;
                r41 = r39 +% r40;
                r42 = locals[4];
                r43 = if (r41 < r42) @as(i64, 1) else @as(i64, 0);
                block = if (r43 != 0) 19 else 21; continue;
            },
            17 => {
                block = 18;
            },
            18 => {
                r102 = locals[5];
                r103 = 123;
                r104 = if (r102 == r103) @as(i64, 1) else @as(i64, 0);
                block = if (r104 != 0) 40 else 42; continue;
            },
            19 => {
                r44 = locals[0];
                r45 = locals[3];
                r46 = locals[2];
                r47 = 1;
                r48 = r46 +% r47;
                r49 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r44))))))[
@intCast(@as(u64, @bitCast(r48)))];
                r50 = 47;
                r51 = if (r49 == r50) @as(i64, 1) else @as(i64, 0);
                block = if (r51 != 0) 22 else 24; continue;
            },
            20 => {
                block = 21;
            },
            21 => {
                r92 = locals[1];
                r93 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r94 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r95 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r93))))))[0] = r94;
                r96 = @intCast(@intFromPtr(@as([*]const u8, "/")));
                r97 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r93))))))[1] = r96;
                r98 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r93))))))[2] = r98;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r92)))))).append(r93);
                r99 = locals[2];
                r100 = 1;
                r101 = r99 +% r100;
                locals[2] = r101;
                block = 1; continue;
            },
            22 => {
                r52 = 0;
                locals[6] = r52;
                r53 = locals[2];
                r54 = 2;
                r55 = r53 +% r54;
                r56 = locals[4];
                r57 = if (r55 < r56) @as(i64, 1) else @as(i64, 0);
                block = if (r57 != 0) 25 else 27; continue;
            },
            23 => {
                block = 24;
            },
            24 => {
                block = 21; continue;
            },
            25 => {
                r58 = locals[0];
                r59 = locals[3];
                r60 = locals[2];
                r61 = 2;
                r62 = r60 +% r61;
                r63 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r58))))))[
@intCast(@as(u64, @bitCast(r62)))];
                r64 = 47;
                r65 = if (r63 == r64) @as(i64, 1) else @as(i64, 0);
                block = if (r65 != 0) 28 else 30; continue;
            },
            26 => {
                block = 27;
            },
            27 => {
                r67 = locals[2];
                locals[7] = r67;
                block = 31; continue;
            },
            28 => {
                r66 = 1;
                locals[6] = r66;
                block = 30; continue;
            },
            29 => {
                block = 30;
            },
            30 => {
                block = 27; continue;
            },
            31 => {
                r68 = locals[2];
                r69 = locals[4];
                r70 = if (r68 < r69) @as(i64, 1) else @as(i64, 0);
                block = if (r70 != 0) 32 else 33; continue;
            },
            32 => {
                r71 = locals[0];
                r72 = locals[3];
                r73 = locals[2];
                r74 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r71))))))[
@intCast(@as(u64, @bitCast(r73)))];
                r75 = 10;
                r76 = if (r74 == r75) @as(i64, 1) else @as(i64, 0);
                block = if (r76 != 0) 34 else 36; continue;
            },
            33 => {
                r80 = locals[6];
                block = if (r80 != 0) 37 else 39; continue;
            },
            34 => {
                block = 33; continue;
            },
            35 => {
                block = 36;
            },
            36 => {
                r77 = locals[2];
                r78 = 1;
                r79 = r77 +% r78;
                locals[2] = r79;
                block = 31; continue;
            },
            37 => {
                r81 = locals[1];
                r82 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r83 = @intCast(@intFromPtr(@as([*]const u8, "doc")));
                r84 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r82))))))[0] = r83;
                r85 = locals[0];
                r86 = locals[3];
                r87 = locals[7];
                r88 = locals[2];
                r89 = r85 +% r87;
                r90 = r88 -% r87;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r82))))))[1] = r89;
                r91 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r82))))))[2] = r91;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r81)))))).append(r82);
                block = 39; continue;
            },
            38 => {
                block = 39;
            },
            39 => {
                block = 1; continue;
            },
            40 => {
                r105 = locals[1];
                r106 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r107 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r108 = 6;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r106))))))[0] = r107;
                r109 = @intCast(@intFromPtr(@as([*]const u8, "{")));
                r110 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r106))))))[1] = r109;
                r111 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r106))))))[2] = r111;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r105)))))).append(r106);
                r112 = locals[2];
                r113 = 1;
                r114 = r112 +% r113;
                locals[2] = r114;
                block = 1; continue;
            },
            41 => {
                block = 42;
            },
            42 => {
                r115 = locals[5];
                r116 = 125;
                r117 = if (r115 == r116) @as(i64, 1) else @as(i64, 0);
                block = if (r117 != 0) 43 else 45; continue;
            },
            43 => {
                r118 = locals[1];
                r119 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r120 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r121 = 6;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r119))))))[0] = r120;
                r122 = @intCast(@intFromPtr(@as([*]const u8, "}")));
                r123 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r119))))))[1] = r122;
                r124 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r119))))))[2] = r124;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r118)))))).append(r119);
                r125 = locals[2];
                r126 = 1;
                r127 = r125 +% r126;
                locals[2] = r127;
                block = 1; continue;
            },
            44 => {
                block = 45;
            },
            45 => {
                r128 = locals[5];
                r129 = 45;
                r130 = if (r128 == r129) @as(i64, 1) else @as(i64, 0);
                block = if (r130 != 0) 46 else 48; continue;
            },
            46 => {
                r131 = locals[2];
                r132 = 1;
                r133 = r131 +% r132;
                r134 = locals[4];
                r135 = if (r133 < r134) @as(i64, 1) else @as(i64, 0);
                block = if (r135 != 0) 49 else 51; continue;
            },
            47 => {
                block = 48;
            },
            48 => {
                r164 = locals[5];
                r165 = 61;
                r166 = if (r164 == r165) @as(i64, 1) else @as(i64, 0);
                block = if (r166 != 0) 55 else 57; continue;
            },
            49 => {
                r136 = locals[0];
                r137 = locals[3];
                r138 = locals[2];
                r139 = 1;
                r140 = r138 +% r139;
                r141 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r136))))))[
@intCast(@as(u64, @bitCast(r140)))];
                r142 = 62;
                r143 = if (r141 == r142) @as(i64, 1) else @as(i64, 0);
                block = if (r143 != 0) 52 else 54; continue;
            },
            50 => {
                block = 51;
            },
            51 => {
                r154 = locals[1];
                r155 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r156 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r157 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r155))))))[0] = r156;
                r158 = @intCast(@intFromPtr(@as([*]const u8, "-")));
                r159 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r155))))))[1] = r158;
                r160 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r155))))))[2] = r160;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154)))))).append(r155);
                r161 = locals[2];
                r162 = 1;
                r163 = r161 +% r162;
                locals[2] = r163;
                block = 1; continue;
            },
            52 => {
                r144 = locals[1];
                r145 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r146 = @intCast(@intFromPtr(@as([*]const u8, "arrow")));
                r147 = 5;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r145))))))[0] = r146;
                r148 = @intCast(@intFromPtr(@as([*]const u8, "->")));
                r149 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r145))))))[1] = r148;
                r150 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r145))))))[2] = r150;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r144)))))).append(r145);
                r151 = locals[2];
                r152 = 2;
                r153 = r151 +% r152;
                locals[2] = r153;
                block = 1; continue;
            },
            53 => {
                block = 54;
            },
            54 => {
                block = 51; continue;
            },
            55 => {
                r167 = locals[2];
                r168 = 1;
                r169 = r167 +% r168;
                r170 = locals[4];
                r171 = if (r169 < r170) @as(i64, 1) else @as(i64, 0);
                block = if (r171 != 0) 58 else 60; continue;
            },
            56 => {
                block = 57;
            },
            57 => {
                r218 = locals[5];
                r219 = 60;
                r220 = if (r218 == r219) @as(i64, 1) else @as(i64, 0);
                block = if (r220 != 0) 67 else 69; continue;
            },
            58 => {
                r172 = locals[0];
                r173 = locals[3];
                r174 = locals[2];
                r175 = 1;
                r176 = r174 +% r175;
                r177 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r172))))))[
@intCast(@as(u64, @bitCast(r176)))];
                r178 = 62;
                r179 = if (r177 == r178) @as(i64, 1) else @as(i64, 0);
                block = if (r179 != 0) 61 else 63; continue;
            },
            59 => {
                block = 60;
            },
            60 => {
                r208 = locals[1];
                r209 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r210 = @intCast(@intFromPtr(@as([*]const u8, "eq")));
                r211 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r209))))))[0] = r210;
                r212 = @intCast(@intFromPtr(@as([*]const u8, "=")));
                r213 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r209))))))[1] = r212;
                r214 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r209))))))[2] = r214;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r208)))))).append(r209);
                r215 = locals[2];
                r216 = 1;
                r217 = r215 +% r216;
                locals[2] = r217;
                block = 1; continue;
            },
            61 => {
                r180 = locals[1];
                r181 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r182 = @intCast(@intFromPtr(@as([*]const u8, "fatarrow")));
                r183 = 8;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))))[0] = r182;
                r184 = @intCast(@intFromPtr(@as([*]const u8, "=>")));
                r185 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))))[1] = r184;
                r186 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))))[2] = r186;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r180)))))).append(r181);
                r187 = locals[2];
                r188 = 2;
                r189 = r187 +% r188;
                locals[2] = r189;
                block = 1; continue;
            },
            62 => {
                block = 63;
            },
            63 => {
                r190 = locals[0];
                r191 = locals[3];
                r192 = locals[2];
                r193 = 1;
                r194 = r192 +% r193;
                r195 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r190))))))[
@intCast(@as(u64, @bitCast(r194)))];
                r196 = 61;
                r197 = if (r195 == r196) @as(i64, 1) else @as(i64, 0);
                block = if (r197 != 0) 64 else 66; continue;
            },
            64 => {
                r198 = locals[1];
                r199 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r200 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r201 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))))[0] = r200;
                r202 = @intCast(@intFromPtr(@as([*]const u8, "==")));
                r203 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))))[1] = r202;
                r204 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))))[2] = r204;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r198)))))).append(r199);
                r205 = locals[2];
                r206 = 2;
                r207 = r205 +% r206;
                locals[2] = r207;
                block = 1; continue;
            },
            65 => {
                block = 66;
            },
            66 => {
                block = 60; continue;
            },
            67 => {
                r221 = locals[2];
                r222 = 1;
                r223 = r221 +% r222;
                r224 = locals[4];
                r225 = if (r223 < r224) @as(i64, 1) else @as(i64, 0);
                block = if (r225 != 0) 70 else 72; continue;
            },
            68 => {
                block = 69;
            },
            69 => {
                r254 = locals[5];
                r255 = 62;
                r256 = if (r254 == r255) @as(i64, 1) else @as(i64, 0);
                block = if (r256 != 0) 76 else 78; continue;
            },
            70 => {
                r226 = locals[0];
                r227 = locals[3];
                r228 = locals[2];
                r229 = 1;
                r230 = r228 +% r229;
                r231 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r226))))))[
@intCast(@as(u64, @bitCast(r230)))];
                r232 = 61;
                r233 = if (r231 == r232) @as(i64, 1) else @as(i64, 0);
                block = if (r233 != 0) 73 else 75; continue;
            },
            71 => {
                block = 72;
            },
            72 => {
                r244 = locals[1];
                r245 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r246 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r247 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r245))))))[0] = r246;
                r248 = @intCast(@intFromPtr(@as([*]const u8, "<")));
                r249 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r245))))))[1] = r248;
                r250 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r245))))))[2] = r250;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r244)))))).append(r245);
                r251 = locals[2];
                r252 = 1;
                r253 = r251 +% r252;
                locals[2] = r253;
                block = 1; continue;
            },
            73 => {
                r234 = locals[1];
                r235 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r236 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r237 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r235))))))[0] = r236;
                r238 = @intCast(@intFromPtr(@as([*]const u8, "<=")));
                r239 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r235))))))[1] = r238;
                r240 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r235))))))[2] = r240;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r234)))))).append(r235);
                r241 = locals[2];
                r242 = 2;
                r243 = r241 +% r242;
                locals[2] = r243;
                block = 1; continue;
            },
            74 => {
                block = 75;
            },
            75 => {
                block = 72; continue;
            },
            76 => {
                r257 = locals[2];
                r258 = 1;
                r259 = r257 +% r258;
                r260 = locals[4];
                r261 = if (r259 < r260) @as(i64, 1) else @as(i64, 0);
                block = if (r261 != 0) 79 else 81; continue;
            },
            77 => {
                block = 78;
            },
            78 => {
                r290 = locals[5];
                r291 = 33;
                r292 = if (r290 == r291) @as(i64, 1) else @as(i64, 0);
                block = if (r292 != 0) 85 else 87; continue;
            },
            79 => {
                r262 = locals[0];
                r263 = locals[3];
                r264 = locals[2];
                r265 = 1;
                r266 = r264 +% r265;
                r267 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r262))))))[
@intCast(@as(u64, @bitCast(r266)))];
                r268 = 61;
                r269 = if (r267 == r268) @as(i64, 1) else @as(i64, 0);
                block = if (r269 != 0) 82 else 84; continue;
            },
            80 => {
                block = 81;
            },
            81 => {
                r280 = locals[1];
                r281 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r282 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r283 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r281))))))[0] = r282;
                r284 = @intCast(@intFromPtr(@as([*]const u8, ">")));
                r285 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r281))))))[1] = r284;
                r286 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r281))))))[2] = r286;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r280)))))).append(r281);
                r287 = locals[2];
                r288 = 1;
                r289 = r287 +% r288;
                locals[2] = r289;
                block = 1; continue;
            },
            82 => {
                r270 = locals[1];
                r271 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r272 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r273 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r271))))))[0] = r272;
                r274 = @intCast(@intFromPtr(@as([*]const u8, ">=")));
                r275 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r271))))))[1] = r274;
                r276 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r271))))))[2] = r276;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r270)))))).append(r271);
                r277 = locals[2];
                r278 = 2;
                r279 = r277 +% r278;
                locals[2] = r279;
                block = 1; continue;
            },
            83 => {
                block = 84;
            },
            84 => {
                block = 81; continue;
            },
            85 => {
                r293 = locals[2];
                r294 = 1;
                r295 = r293 +% r294;
                r296 = locals[4];
                r297 = if (r295 < r296) @as(i64, 1) else @as(i64, 0);
                block = if (r297 != 0) 88 else 90; continue;
            },
            86 => {
                block = 87;
            },
            87 => {
                r326 = locals[5];
                r327 = verve_Tokenizer_single_char_kind(r326);
                locals[8] = r327;
                r328 = locals[8];
                r329 = locals[9];
                r330 = @intCast(@intFromPtr(@as([*]const u8, "none")));
                r331 = 4;
                r332 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r328))))), r329, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r330))))), r331)) @as(i64, 1) else @as(i64, 0);
                r333 = if (r332 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r333 != 0) 94 else 96; continue;
            },
            88 => {
                r298 = locals[0];
                r299 = locals[3];
                r300 = locals[2];
                r301 = 1;
                r302 = r300 +% r301;
                r303 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r298))))))[
@intCast(@as(u64, @bitCast(r302)))];
                r304 = 61;
                r305 = if (r303 == r304) @as(i64, 1) else @as(i64, 0);
                block = if (r305 != 0) 91 else 93; continue;
            },
            89 => {
                block = 90;
            },
            90 => {
                r316 = locals[1];
                r317 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r318 = @intCast(@intFromPtr(@as([*]const u8, "bang")));
                r319 = 4;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r317))))))[0] = r318;
                r320 = @intCast(@intFromPtr(@as([*]const u8, "!")));
                r321 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r317))))))[1] = r320;
                r322 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r317))))))[2] = r322;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r316)))))).append(r317);
                r323 = locals[2];
                r324 = 1;
                r325 = r323 +% r324;
                locals[2] = r325;
                block = 1; continue;
            },
            91 => {
                r306 = locals[1];
                r307 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r308 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r309 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r307))))))[0] = r308;
                r310 = @intCast(@intFromPtr(@as([*]const u8, "!=")));
                r311 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r307))))))[1] = r310;
                r312 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r307))))))[2] = r312;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r306)))))).append(r307);
                r313 = locals[2];
                r314 = 2;
                r315 = r313 +% r314;
                locals[2] = r315;
                block = 1; continue;
            },
            92 => {
                block = 93;
            },
            93 => {
                block = 90; continue;
            },
            94 => {
                r334 = locals[1];
                r335 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r336 = locals[8];
                r337 = locals[9];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r335))))))[0] = r336;
                r338 = locals[0];
                r339 = locals[3];
                r340 = locals[2];
                r341 = locals[2];
                r342 = 1;
                r343 = r341 +% r342;
                r344 = r338 +% r340;
                r345 = r343 -% r340;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r335))))))[1] = r344;
                r346 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r335))))))[2] = r346;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r334)))))).append(r335);
                r347 = locals[2];
                r348 = 1;
                r349 = r347 +% r348;
                locals[2] = r349;
                block = 1; continue;
            },
            95 => {
                block = 96;
            },
            96 => {
                r350 = locals[5];
                r351 = 34;
                r352 = if (r350 == r351) @as(i64, 1) else @as(i64, 0);
                block = if (r352 != 0) 97 else 99; continue;
            },
            97 => {
                r353 = locals[2];
                locals[7] = r353;
                r354 = locals[2];
                r355 = 1;
                r356 = r354 +% r355;
                locals[2] = r356;
                block = 100; continue;
            },
            98 => {
                block = 99;
            },
            99 => {
                r390 = locals[5];
                r391 = 58;
                r392 = if (r390 == r391) @as(i64, 1) else @as(i64, 0);
                block = if (r392 != 0) 109 else 111; continue;
            },
            100 => {
                r357 = locals[2];
                r358 = locals[4];
                r359 = if (r357 < r358) @as(i64, 1) else @as(i64, 0);
                block = if (r359 != 0) 101 else 102; continue;
            },
            101 => {
                r360 = locals[0];
                r361 = locals[3];
                r362 = locals[2];
                r363 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r360))))))[
@intCast(@as(u64, @bitCast(r362)))];
                locals[10] = r363;
                r364 = locals[10];
                r365 = 92;
                r366 = if (r364 == r365) @as(i64, 1) else @as(i64, 0);
                block = if (r366 != 0) 103 else 105; continue;
            },
            102 => {
                r376 = locals[2];
                r377 = 1;
                r378 = r376 +% r377;
                locals[2] = r378;
                r379 = locals[1];
                r380 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r381 = @intCast(@intFromPtr(@as([*]const u8, "string")));
                r382 = 6;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r380))))))[0] = r381;
                r383 = locals[0];
                r384 = locals[3];
                r385 = locals[7];
                r386 = locals[2];
                r387 = r383 +% r385;
                r388 = r386 -% r385;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r380))))))[1] = r387;
                r389 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r380))))))[2] = r389;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r379)))))).append(r380);
                block = 1; continue;
            },
            103 => {
                r367 = locals[2];
                r368 = 2;
                r369 = r367 +% r368;
                locals[2] = r369;
                block = 100; continue;
            },
            104 => {
                block = 105;
            },
            105 => {
                r370 = locals[10];
                r371 = 34;
                r372 = if (r370 == r371) @as(i64, 1) else @as(i64, 0);
                block = if (r372 != 0) 106 else 108; continue;
            },
            106 => {
                block = 102; continue;
            },
            107 => {
                block = 108;
            },
            108 => {
                r373 = locals[2];
                r374 = 1;
                r375 = r373 +% r374;
                locals[2] = r375;
                block = 100; continue;
            },
            109 => {
                r393 = locals[2];
                r394 = 1;
                r395 = r393 +% r394;
                r396 = locals[4];
                r397 = if (r395 < r396) @as(i64, 1) else @as(i64, 0);
                block = if (r397 != 0) 112 else 114; continue;
            },
            110 => {
                block = 111;
            },
            111 => {
                r454 = locals[0];
                r455 = locals[3];
                r456 = locals[2];
                r457 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r454)))))) + @as(usize, @intCast(@as(u64, @bitCast(r456))))));
                r458 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r457))))))[0]; r459 = if (b >= '0' and b <= '9') @as(i64, 1) else @as(i64, 0); }
                block = if (r459 != 0) 127 else 129; continue;
            },
            112 => {
                r398 = locals[0];
                r399 = locals[3];
                r400 = locals[2];
                r401 = 1;
                r402 = r400 +% r401;
                r403 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r398)))))) + @as(usize, @intCast(@as(u64, @bitCast(r402))))));
                r404 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r403))))))[0]; r405 = if ((b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r405 != 0) 115 else 117; continue;
            },
            113 => {
                block = 114;
            },
            114 => {
                r444 = locals[1];
                r445 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r446 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r447 = 5;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r445))))))[0] = r446;
                r448 = @intCast(@intFromPtr(@as([*]const u8, ":")));
                r449 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r445))))))[1] = r448;
                r450 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r445))))))[2] = r450;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r444)))))).append(r445);
                r451 = locals[2];
                r452 = 1;
                r453 = r451 +% r452;
                locals[2] = r453;
                block = 1; continue;
            },
            115 => {
                r406 = locals[2];
                locals[7] = r406;
                r407 = locals[2];
                r408 = 1;
                r409 = r407 +% r408;
                locals[2] = r409;
                block = 118; continue;
            },
            116 => {
                block = 117;
            },
            117 => {
                block = 114; continue;
            },
            118 => {
                r410 = locals[2];
                r411 = locals[4];
                r412 = if (r410 < r411) @as(i64, 1) else @as(i64, 0);
                block = if (r412 != 0) 119 else 120; continue;
            },
            119 => {
                r413 = locals[0];
                r414 = locals[3];
                r415 = locals[2];
                r416 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r413)))))) + @as(usize, @intCast(@as(u64, @bitCast(r415))))));
                r417 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r416))))))[0]; r418 = if ((b >= '0' and b <= '9') or (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r418 != 0) 121 else 122; continue;
            },
            120 => {
                r433 = locals[1];
                r434 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r435 = @intCast(@intFromPtr(@as([*]const u8, "tag")));
                r436 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r434))))))[0] = r435;
                r437 = locals[0];
                r438 = locals[3];
                r439 = locals[7];
                r440 = locals[2];
                r441 = r437 +% r439;
                r442 = r440 -% r439;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r434))))))[1] = r441;
                r443 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r434))))))[2] = r443;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r433)))))).append(r434);
                block = 1; continue;
            },
            121 => {
                r419 = locals[2];
                r420 = 1;
                r421 = r419 +% r420;
                locals[2] = r421;
                block = 123; continue;
            },
            122 => {
                r422 = locals[0];
                r423 = locals[3];
                r424 = locals[2];
                r425 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r422)))))) + @as(usize, @intCast(@as(u64, @bitCast(r424))))));
                r426 = 1;
                r427 = @intCast(@intFromPtr(@as([*]const u8, "_")));
                r428 = 1;
                r429 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r425))))), r426, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r427))))), r428)) @as(i64, 1) else @as(i64, 0);
                block = if (r429 != 0) 124 else 125; continue;
            },
            123 => {
                block = 118; continue;
            },
            124 => {
                r430 = locals[2];
                r431 = 1;
                r432 = r430 +% r431;
                locals[2] = r432;
                block = 126; continue;
            },
            125 => {
                block = 120; continue;
            },
            126 => {
                block = 123; continue;
            },
            127 => {
                r460 = locals[2];
                locals[7] = r460;
                block = 130; continue;
            },
            128 => {
                block = 129;
            },
            129 => {
                r485 = locals[0];
                r486 = locals[3];
                r487 = locals[2];
                r488 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r485)))))) + @as(usize, @intCast(@as(u64, @bitCast(r487))))));
                r489 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r488))))))[0]; r490 = if ((b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r490 != 0) 136 else 138; continue;
            },
            130 => {
                r461 = locals[2];
                r462 = locals[4];
                r463 = if (r461 < r462) @as(i64, 1) else @as(i64, 0);
                block = if (r463 != 0) 131 else 132; continue;
            },
            131 => {
                r464 = locals[0];
                r465 = locals[3];
                r466 = locals[2];
                r467 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r464)))))) + @as(usize, @intCast(@as(u64, @bitCast(r466))))));
                r468 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r467))))))[0]; r469 = if (b >= '0' and b <= '9') @as(i64, 1) else @as(i64, 0); }
                r470 = if (r469 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r470 != 0) 133 else 135; continue;
            },
            132 => {
                r474 = locals[1];
                r475 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r476 = @intCast(@intFromPtr(@as([*]const u8, "int")));
                r477 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r475))))))[0] = r476;
                r478 = locals[0];
                r479 = locals[3];
                r480 = locals[7];
                r481 = locals[2];
                r482 = r478 +% r480;
                r483 = r481 -% r480;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r475))))))[1] = r482;
                r484 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r475))))))[2] = r484;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r474)))))).append(r475);
                block = 1; continue;
            },
            133 => {
                block = 132; continue;
            },
            134 => {
                block = 135;
            },
            135 => {
                r471 = locals[2];
                r472 = 1;
                r473 = r471 +% r472;
                locals[2] = r473;
                block = 130; continue;
            },
            136 => {
                r491 = locals[2];
                locals[7] = r491;
                block = 139; continue;
            },
            137 => {
                block = 138;
            },
            138 => {
                r538 = locals[2];
                r539 = 1;
                r540 = r538 +% r539;
                locals[2] = r540;
                block = 1; continue;
            },
            139 => {
                r492 = locals[2];
                r493 = locals[4];
                r494 = if (r492 < r493) @as(i64, 1) else @as(i64, 0);
                block = if (r494 != 0) 140 else 141; continue;
            },
            140 => {
                r495 = locals[0];
                r496 = locals[3];
                r497 = locals[2];
                r498 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r495)))))) + @as(usize, @intCast(@as(u64, @bitCast(r497))))));
                r499 = 1;
                locals[11] = r498;
                locals[12] = r499;
                r500 = locals[11];
                r501 = locals[12];
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r500))))))[0]; r502 = if ((b >= '0' and b <= '9') or (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r502 != 0) 142 else 143; continue;
            },
            141 => {
                r514 = locals[0];
                r515 = locals[3];
                r516 = locals[7];
                r517 = locals[2];
                r518 = r514 +% r516;
                r519 = r517 -% r516;
                locals[13] = r518;
                locals[14] = r519;
                r520 = locals[15];
                r521 = locals[13];
                r522 = locals[14];
                { const list = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r520)))))); var found: i64 = 0; var si: i64 = 0; while (si + 1 < list.len) : (si += 2) { const eptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(list.get(si))))))); const elen = list.get(si + 1); const nptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r521)))))); if (strEql(eptr, elen, nptr, r522)) { found = 1; break; } } r523 = found; }
                block = if (r523 != 0) 148 else 149; continue;
            },
            142 => {
                r503 = locals[2];
                r504 = 1;
                r505 = r503 +% r504;
                locals[2] = r505;
                block = 144; continue;
            },
            143 => {
                r506 = locals[11];
                r507 = locals[12];
                r508 = @intCast(@intFromPtr(@as([*]const u8, "_")));
                r509 = 1;
                r510 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r506))))), r507, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r508))))), r509)) @as(i64, 1) else @as(i64, 0);
                block = if (r510 != 0) 145 else 146; continue;
            },
            144 => {
                block = 139; continue;
            },
            145 => {
                r511 = locals[2];
                r512 = 1;
                r513 = r511 +% r512;
                locals[2] = r513;
                block = 147; continue;
            },
            146 => {
                block = 141; continue;
            },
            147 => {
                block = 144; continue;
            },
            148 => {
                r524 = locals[1];
                r525 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r526 = @intCast(@intFromPtr(@as([*]const u8, "kw")));
                r527 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r525))))))[0] = r526;
                r528 = locals[13];
                r529 = locals[14];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r525))))))[1] = r528;
                r530 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r525))))))[2] = r530;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r524)))))).append(r525);
                block = 150; continue;
            },
            149 => {
                r531 = locals[1];
                r532 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r533 = @intCast(@intFromPtr(@as([*]const u8, "ident")));
                r534 = 5;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r532))))))[0] = r533;
                r535 = locals[13];
                r536 = locals[14];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r532))))))[1] = r535;
                r537 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r532))))))[2] = r537;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r531)))))).append(r532);
                block = 150; continue;
            },
            150 => {
                block = 1; continue;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_node(param_kind: i64, param_name: i64, param_value: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_kind;
    locals[1] = param_name;
    locals[2] = param_value;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 4) catch &.{}).ptr));
                r1 = locals[0];
                r2 = locals[3];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[0] = r1;
                r3 = locals[1];
                r4 = locals[4];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[1] = r3;
                r5 = locals[2];
                r6 = locals[5];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[2] = r5;
                var list_7 = List.init();
                r7 = @intCast(@intFromPtr(&list_7));
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[3] = r7;
                return r0;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_node_with(param_kind: i64, param_name: i64, param_value: i64, param_kids: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_kind;
    locals[1] = param_name;
    locals[2] = param_value;
    locals[3] = param_kids;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 4) catch &.{}).ptr));
                r1 = locals[0];
                r2 = locals[4];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[0] = r1;
                r3 = locals[1];
                r4 = locals[5];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[1] = r3;
                r5 = locals[2];
                r6 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[2] = r5;
                r7 = locals[3];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[3] = r7;
                return r0;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_current(param_tokens: i64, param_pos: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_pos;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[1];
                r1 = locals[0];
                r2 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r1)))))).len;
                r3 = if (r0 >= r2) @as(i64, 1) else @as(i64, 0);
                block = if (r3 != 0) 1 else 3; continue;
            },
            1 => {
                r4 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r5 = @intCast(@intFromPtr(@as([*]const u8, "eof")));
                r6 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))))[0] = r5;
                r7 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r8 = 0;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))))[1] = r7;
                r9 = 0;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))))[2] = r9;
                return r4;
            },
            2 => {
                block = 3;
            },
            3 => {
                r10 = locals[0];
                r11 = locals[1];
                r12 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r10)))))).get(r11);
                return r12;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_expect_kind(param_tokens: i64, param_pos: i64, param_kind: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_pos;
    locals[2] = param_kind;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = locals[1];
                r2 = verve_Parser_current(r0, r1);
                locals[3] = r2;
                r3 = locals[3];
                r4 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r3))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r5 = @intCast(sl); }
                r6 = locals[2];
                r7 = locals[4];
                r8 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))), r5, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r6))))), r7)) @as(i64, 1) else @as(i64, 0);
                r9 = if (r8 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r9 != 0) 1 else 3; continue;
            },
            1 => {
                r10 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r11 = 19;
                r12 = locals[3];
                r13 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r12))))))[2];
                r14 = @intCast(@intFromPtr(@as([*]const u8, ": expected ")));
                r15 = 11;
                r16 = locals[2];
                r17 = locals[4];
                r18 = @intCast(@intFromPtr(@as([*]const u8, " but got ")));
                r19 = 9;
                r20 = locals[3];
                r21 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r20))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r21)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r22 = @intCast(sl); }
                r23 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r24 = 2;
                r25 = locals[3];
                r26 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r26)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r27 = @intCast(sl); }
                r28 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r29 = 1;
                r31 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r32 = 19;
                r33 = locals[3];
                r34 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33))))))[2];
                r35 = -1;
                r36 = @intCast(@intFromPtr(@as([*]const u8, ": expected ")));
                r37 = 11;
                r38 = locals[2];
                r39 = locals[4];
                r40 = @intCast(@intFromPtr(@as([*]const u8, " but got ")));
                r41 = 9;
                r42 = locals[3];
                r43 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r42))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r44 = @intCast(sl); }
                r45 = -1;
                r46 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r47 = 2;
                r48 = locals[3];
                r49 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r48))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r49)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r50 = @intCast(sl); }
                r51 = -1;
                r52 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r53 = 1;
                if (r32 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r31}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r31))))), r32); }
                if (r35 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r34}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r34))))), r35); }
                if (r37 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r36}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36))))), r37); }
                if (r39 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r38}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r38))))), r39); }
                if (r41 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r40}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r40))))), r41); }
                if (r45 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r43}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43))))), r45); }
                if (r47 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r46}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r46))))), r47); }
                if (r51 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r49}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r49))))), r51); }
                if (r53 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r52}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r52))))), r53); }
                verve_write(1, "\n", 1);
                r30 = 0;
                r54 = locals[1];
                return r54;
            },
            2 => {
                block = 3;
            },
            3 => {
                r55 = locals[1];
                r56 = 1;
                r57 = r55 +% r56;
                return r57;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_expect_kw(param_tokens: i64, param_pos: i64, param_word: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_pos;
    locals[2] = param_word;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = locals[1];
                r2 = verve_Parser_current(r0, r1);
                locals[3] = r2;
                r3 = locals[3];
                r4 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r3))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r5 = @intCast(sl); }
                r6 = @intCast(@intFromPtr(@as([*]const u8, "kw")));
                r7 = 2;
                r8 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))), r5, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r6))))), r7)) @as(i64, 1) else @as(i64, 0);
                r9 = if (r8 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r9 != 0) 1 else 3; continue;
            },
            1 => {
                r10 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r11 = 19;
                r12 = locals[3];
                r13 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r12))))))[2];
                r14 = @intCast(@intFromPtr(@as([*]const u8, ": expected keyword '")));
                r15 = 20;
                r16 = locals[2];
                r17 = locals[4];
                r18 = @intCast(@intFromPtr(@as([*]const u8, "' but got ")));
                r19 = 10;
                r20 = locals[3];
                r21 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r20))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r21)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r22 = @intCast(sl); }
                r24 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r25 = 19;
                r26 = locals[3];
                r27 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r26))))))[2];
                r28 = -1;
                r29 = @intCast(@intFromPtr(@as([*]const u8, ": expected keyword '")));
                r30 = 20;
                r31 = locals[2];
                r32 = locals[4];
                r33 = @intCast(@intFromPtr(@as([*]const u8, "' but got ")));
                r34 = 10;
                r35 = locals[3];
                r36 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r35))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r37 = @intCast(sl); }
                r38 = -1;
                if (r25 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r24}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r24))))), r25); }
                if (r28 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r27}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r27))))), r28); }
                if (r30 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r29}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r29))))), r30); }
                if (r32 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r31}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r31))))), r32); }
                if (r34 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r33}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33))))), r34); }
                if (r38 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r36}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36))))), r38); }
                verve_write(1, "\n", 1);
                r23 = 0;
                r39 = locals[1];
                return r39;
            },
            2 => {
                block = 3;
            },
            3 => {
                r40 = locals[3];
                r41 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r40))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r41)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r42 = @intCast(sl); }
                r43 = locals[2];
                r44 = locals[4];
                r45 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r41))))), r42, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43))))), r44)) @as(i64, 1) else @as(i64, 0);
                r46 = if (r45 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r46 != 0) 4 else 6; continue;
            },
            4 => {
                r47 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r48 = 19;
                r49 = locals[3];
                r50 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r49))))))[2];
                r51 = @intCast(@intFromPtr(@as([*]const u8, ": expected '")));
                r52 = 12;
                r53 = locals[2];
                r54 = locals[4];
                r55 = @intCast(@intFromPtr(@as([*]const u8, "' but got '")));
                r56 = 11;
                r57 = locals[3];
                r58 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r57))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r58)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r59 = @intCast(sl); }
                r60 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r61 = 1;
                r63 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r64 = 19;
                r65 = locals[3];
                r66 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r65))))))[2];
                r67 = -1;
                r68 = @intCast(@intFromPtr(@as([*]const u8, ": expected '")));
                r69 = 12;
                r70 = locals[2];
                r71 = locals[4];
                r72 = @intCast(@intFromPtr(@as([*]const u8, "' but got '")));
                r73 = 11;
                r74 = locals[3];
                r75 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r74))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r75)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r76 = @intCast(sl); }
                r77 = -1;
                r78 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r79 = 1;
                if (r64 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r63}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r63))))), r64); }
                if (r67 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r66}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r66))))), r67); }
                if (r69 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r68}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r68))))), r69); }
                if (r71 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r70}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r70))))), r71); }
                if (r73 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r72}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r72))))), r73); }
                if (r77 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r75}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r75))))), r77); }
                if (r79 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r78}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r78))))), r79); }
                verve_write(1, "\n", 1);
                r62 = 0;
                r80 = locals[1];
                return r80;
            },
            5 => {
                block = 6;
            },
            6 => {
                r81 = locals[1];
                r82 = 1;
                r83 = r81 +% r82;
                return r83;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_is_kind(param_tokens: i64, param_pos: i64, param_kind: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_pos;
    locals[2] = param_kind;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = 0;
                r1 = locals[2];
                r2 = locals[3];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r3 = @intCast(sl); }
                r4 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))), r3, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r1))))), r2)) @as(i64, 1) else @as(i64, 0);
                return r4;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_is_kw(param_tokens: i64, param_pos: i64, param_word: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_pos;
    locals[2] = param_word;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = locals[1];
                r2 = verve_Parser_current(r0, r1);
                locals[3] = r2;
                r3 = locals[3];
                r4 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r3))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r5 = @intCast(sl); }
                r6 = @intCast(@intFromPtr(@as([*]const u8, "kw")));
                r7 = 2;
                r8 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))), r5, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r6))))), r7)) @as(i64, 1) else @as(i64, 0);
                r9 = if (r8 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r9 != 0) 1 else 3; continue;
            },
            1 => {
                r10 = 0;
                return r10;
            },
            2 => {
                block = 3;
            },
            3 => {
                r11 = locals[3];
                r12 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r11))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r12)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r13 = @intCast(sl); }
                r14 = locals[2];
                r15 = locals[4];
                r16 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r12))))), r13, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r14))))), r15)) @as(i64, 1) else @as(i64, 0);
                return r16;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_parse_file(param_tokens: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var r84: i64 = 0;
    _ = &r84;
    var r85: i64 = 0;
    _ = &r85;
    var r86: i64 = 0;
    _ = &r86;
    var r87: i64 = 0;
    _ = &r87;
    var r88: i64 = 0;
    _ = &r88;
    var r89: i64 = 0;
    _ = &r89;
    var r90: i64 = 0;
    _ = &r90;
    var r91: i64 = 0;
    _ = &r91;
    var r92: i64 = 0;
    _ = &r92;
    var r93: i64 = 0;
    _ = &r93;
    var r94: i64 = 0;
    _ = &r94;
    var r95: i64 = 0;
    _ = &r95;
    var r96: i64 = 0;
    _ = &r96;
    var r97: i64 = 0;
    _ = &r97;
    var r98: i64 = 0;
    _ = &r98;
    var r99: i64 = 0;
    _ = &r99;
    var r100: i64 = 0;
    _ = &r100;
    var r101: i64 = 0;
    _ = &r101;
    var r102: i64 = 0;
    _ = &r102;
    var r103: i64 = 0;
    _ = &r103;
    var r104: i64 = 0;
    _ = &r104;
    var r105: i64 = 0;
    _ = &r105;
    var r106: i64 = 0;
    _ = &r106;
    var r107: i64 = 0;
    _ = &r107;
    var r108: i64 = 0;
    _ = &r108;
    var r109: i64 = 0;
    _ = &r109;
    var r110: i64 = 0;
    _ = &r110;
    var r111: i64 = 0;
    _ = &r111;
    var r112: i64 = 0;
    _ = &r112;
    var r113: i64 = 0;
    _ = &r113;
    var r114: i64 = 0;
    _ = &r114;
    var r115: i64 = 0;
    _ = &r115;
    var r116: i64 = 0;
    _ = &r116;
    var r117: i64 = 0;
    _ = &r117;
    var r118: i64 = 0;
    _ = &r118;
    var r119: i64 = 0;
    _ = &r119;
    var r120: i64 = 0;
    _ = &r120;
    var r121: i64 = 0;
    _ = &r121;
    var r122: i64 = 0;
    _ = &r122;
    var r123: i64 = 0;
    _ = &r123;
    var r124: i64 = 0;
    _ = &r124;
    var r125: i64 = 0;
    _ = &r125;
    var r126: i64 = 0;
    _ = &r126;
    var r127: i64 = 0;
    _ = &r127;
    var r128: i64 = 0;
    _ = &r128;
    var r129: i64 = 0;
    _ = &r129;
    var r130: i64 = 0;
    _ = &r130;
    var r131: i64 = 0;
    _ = &r131;
    var r132: i64 = 0;
    _ = &r132;
    var r133: i64 = 0;
    _ = &r133;
    var r134: i64 = 0;
    _ = &r134;
    var r135: i64 = 0;
    _ = &r135;
    var r136: i64 = 0;
    _ = &r136;
    var r137: i64 = 0;
    _ = &r137;
    var r138: i64 = 0;
    _ = &r138;
    var r139: i64 = 0;
    _ = &r139;
    var r140: i64 = 0;
    _ = &r140;
    var r141: i64 = 0;
    _ = &r141;
    var r142: i64 = 0;
    _ = &r142;
    var r143: i64 = 0;
    _ = &r143;
    var r144: i64 = 0;
    _ = &r144;
    var r145: i64 = 0;
    _ = &r145;
    var r146: i64 = 0;
    _ = &r146;
    var r147: i64 = 0;
    _ = &r147;
    var r148: i64 = 0;
    _ = &r148;
    var r149: i64 = 0;
    _ = &r149;
    var r150: i64 = 0;
    _ = &r150;
    var r151: i64 = 0;
    _ = &r151;
    var r152: i64 = 0;
    _ = &r152;
    var r153: i64 = 0;
    _ = &r153;
    var r154: i64 = 0;
    _ = &r154;
    var r155: i64 = 0;
    _ = &r155;
    var r156: i64 = 0;
    _ = &r156;
    var r157: i64 = 0;
    _ = &r157;
    var r158: i64 = 0;
    _ = &r158;
    var r159: i64 = 0;
    _ = &r159;
    var r160: i64 = 0;
    _ = &r160;
    var r161: i64 = 0;
    _ = &r161;
    var r162: i64 = 0;
    _ = &r162;
    var r163: i64 = 0;
    _ = &r163;
    var r164: i64 = 0;
    _ = &r164;
    var r165: i64 = 0;
    _ = &r165;
    var r166: i64 = 0;
    _ = &r166;
    var r167: i64 = 0;
    _ = &r167;
    var r168: i64 = 0;
    _ = &r168;
    var r169: i64 = 0;
    _ = &r169;
    var r170: i64 = 0;
    _ = &r170;
    var r171: i64 = 0;
    _ = &r171;
    var r172: i64 = 0;
    _ = &r172;
    var r173: i64 = 0;
    _ = &r173;
    var r174: i64 = 0;
    _ = &r174;
    var r175: i64 = 0;
    _ = &r175;
    var r176: i64 = 0;
    _ = &r176;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                var list_0 = List.init();
                r0 = @intCast(@intFromPtr(&list_0));
                locals[1] = r0;
                r1 = 0;
                locals[2] = r1;
                block = 1; continue;
            },
            1 => {
                r2 = locals[2];
                r3 = locals[0];
                r4 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r3)))))).len;
                r5 = if (r2 < r4) @as(i64, 1) else @as(i64, 0);
                block = if (r5 != 0) 2 else 3; continue;
            },
            2 => {
                r6 = locals[0];
                r7 = locals[2];
                r8 = verve_Parser_current(r6, r7);
                locals[3] = r8;
                r9 = locals[3];
                r10 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r9))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r10)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r11 = @intCast(sl); }
                r12 = @intCast(@intFromPtr(@as([*]const u8, "doc")));
                r13 = 3;
                r14 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r10))))), r11, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r12))))), r13)) @as(i64, 1) else @as(i64, 0);
                block = if (r14 != 0) 4 else 6; continue;
            },
            3 => {
                r176 = locals[1];
                return r176;
            },
            4 => {
                r15 = locals[2];
                r16 = 1;
                r17 = r15 +% r16;
                locals[2] = r17;
                block = 1; continue;
            },
            5 => {
                block = 6;
            },
            6 => {
                r18 = 0;
                locals[4] = r18;
                r19 = locals[0];
                r20 = locals[2];
                r21 = @intCast(@intFromPtr(@as([*]const u8, "export")));
                r22 = 6;
                r23 = verve_Parser_is_kw(r19, r20, r21);
                block = if (r23 != 0) 7 else 9; continue;
            },
            7 => {
                r24 = 1;
                locals[4] = r24;
                r25 = locals[2];
                r26 = 1;
                r27 = r25 +% r26;
                locals[2] = r27;
                block = 9; continue;
            },
            8 => {
                block = 9;
            },
            9 => {
                r28 = locals[0];
                r29 = locals[2];
                r30 = @intCast(@intFromPtr(@as([*]const u8, "module")));
                r31 = 6;
                r32 = verve_Parser_is_kw(r28, r29, r30);
                block = if (r32 != 0) 10 else 11; continue;
            },
            10 => {
                r33 = locals[2];
                r34 = 1;
                r35 = r33 +% r34;
                locals[2] = r35;
                r36 = locals[0];
                r37 = locals[2];
                r38 = verve_Parser_parse_module(r36, r37);
                locals[5] = r38;
                r39 = locals[5];
                r40 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r39))))))[1];
                locals[6] = r40;
                r41 = locals[4];
                block = if (r41 != 0) 13 else 15; continue;
            },
            11 => {
                r57 = locals[0];
                r58 = locals[2];
                r59 = @intCast(@intFromPtr(@as([*]const u8, "struct")));
                r60 = 6;
                r61 = verve_Parser_is_kw(r57, r58, r59);
                block = if (r61 != 0) 16 else 17; continue;
            },
            12 => {
                block = 1; continue;
            },
            13 => {
                r42 = @intCast(@intFromPtr(@as([*]const u8, "module_exported")));
                r43 = 15;
                r44 = locals[6];
                r45 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r44))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r45)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r46 = @intCast(sl); }
                r47 = locals[6];
                r48 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r47))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r48)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r49 = @intCast(sl); }
                r50 = locals[6];
                r51 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r50))))))[3];
                r52 = verve_Parser_node_with(r42, r45, r48, r51);
                locals[6] = r52;
                block = 15; continue;
            },
            14 => {
                block = 15;
            },
            15 => {
                r53 = locals[1];
                r54 = locals[6];
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r53)))))).append(r54);
                r55 = locals[5];
                r56 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r55))))))[0];
                locals[2] = r56;
                block = 12; continue;
            },
            16 => {
                r62 = locals[2];
                r63 = 1;
                r64 = r62 +% r63;
                locals[2] = r64;
                r65 = 0;
                locals[7] = r65;
                r66 = locals[2];
                r67 = 1;
                r68 = r66 +% r67;
                locals[2] = r68;
                r69 = locals[0];
                r70 = locals[2];
                r71 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r72 = 6;
                r73 = verve_Parser_expect_kind(r69, r70, r71);
                locals[2] = r73;
                var list_74 = List.init();
                r74 = @intCast(@intFromPtr(&list_74));
                locals[8] = r74;
                block = 19; continue;
            },
            17 => {
                r121 = locals[0];
                r122 = locals[2];
                r123 = @intCast(@intFromPtr(@as([*]const u8, "import")));
                r124 = 6;
                r125 = verve_Parser_is_kw(r121, r122, r123);
                block = if (r125 != 0) 22 else 23; continue;
            },
            18 => {
                block = 12; continue;
            },
            19 => {
                r75 = locals[0];
                r76 = locals[2];
                r77 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r78 = 6;
                r79 = verve_Parser_is_kind(r75, r76, r77);
                r80 = if (r79 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r80 != 0) 20 else 21; continue;
            },
            20 => {
                r81 = 0;
                locals[9] = r81;
                r82 = locals[2];
                r83 = 1;
                r84 = r82 +% r83;
                locals[2] = r84;
                r85 = locals[0];
                r86 = locals[2];
                r87 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r88 = 5;
                r89 = verve_Parser_expect_kind(r85, r86, r87);
                locals[2] = r89;
                r90 = 0;
                locals[10] = r90;
                r91 = locals[2];
                r92 = 1;
                r93 = r91 +% r92;
                locals[2] = r93;
                r94 = locals[0];
                r95 = locals[2];
                r96 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r97 = 4;
                r98 = verve_Parser_expect_kind(r94, r95, r96);
                locals[2] = r98;
                r99 = locals[8];
                r100 = @intCast(@intFromPtr(@as([*]const u8, "field")));
                r101 = 5;
                r102 = locals[9];
                r103 = locals[11];
                r104 = locals[10];
                r105 = locals[12];
                r106 = verve_Parser_node(r100, r102, r104);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r99)))))).append(r106);
                block = 19; continue;
            },
            21 => {
                r107 = locals[0];
                r108 = locals[2];
                r109 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r110 = 6;
                r111 = verve_Parser_expect_kind(r107, r108, r109);
                locals[2] = r111;
                r112 = locals[1];
                r113 = @intCast(@intFromPtr(@as([*]const u8, "struct")));
                r114 = 6;
                r115 = locals[7];
                r116 = locals[13];
                r117 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r118 = 0;
                r119 = locals[8];
                r120 = verve_Parser_node_with(r113, r115, r117, r119);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r112)))))).append(r120);
                block = 18; continue;
            },
            22 => {
                r126 = locals[2];
                r127 = 1;
                r128 = r126 +% r127;
                locals[2] = r128;
                r129 = 0;
                locals[14] = r129;
                r130 = locals[2];
                r131 = 1;
                r132 = r130 +% r131;
                locals[2] = r132;
                r133 = locals[0];
                r134 = locals[2];
                r135 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r136 = 4;
                r137 = verve_Parser_expect_kind(r133, r134, r135);
                locals[2] = r137;
                r138 = locals[1];
                r139 = @intCast(@intFromPtr(@as([*]const u8, "import")));
                r140 = 6;
                r141 = locals[14];
                r142 = locals[15];
                r143 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r144 = 0;
                r145 = verve_Parser_node(r139, r141, r143);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r138)))))).append(r145);
                block = 24; continue;
            },
            23 => {
                r146 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected token: ")));
                r147 = 18;
                r148 = locals[3];
                r149 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r148))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r149)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r150 = @intCast(sl); }
                r151 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r152 = 2;
                r153 = locals[3];
                r154 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r153))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r155 = @intCast(sl); }
                r156 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r157 = 1;
                r159 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected token: ")));
                r160 = 18;
                r161 = locals[3];
                r162 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r161))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r162)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r163 = @intCast(sl); }
                r164 = -1;
                r165 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r166 = 2;
                r167 = locals[3];
                r168 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r167))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r168)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r169 = @intCast(sl); }
                r170 = -1;
                r171 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r172 = 1;
                if (r160 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r159}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r159))))), r160); }
                if (r164 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r162}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r162))))), r164); }
                if (r166 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r165}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r165))))), r166); }
                if (r170 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r168}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r168))))), r170); }
                if (r172 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r171}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r171))))), r172); }
                verve_write(1, "\n", 1);
                r158 = 0;
                r173 = locals[2];
                r174 = 1;
                r175 = r173 +% r174;
                locals[2] = r175;
                block = 24; continue;
            },
            24 => {
                block = 18; continue;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_parse_module(param_tokens: i64, param_start_pos: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var r84: i64 = 0;
    _ = &r84;
    var r85: i64 = 0;
    _ = &r85;
    var r86: i64 = 0;
    _ = &r86;
    var r87: i64 = 0;
    _ = &r87;
    var r88: i64 = 0;
    _ = &r88;
    var r89: i64 = 0;
    _ = &r89;
    var r90: i64 = 0;
    _ = &r90;
    var r91: i64 = 0;
    _ = &r91;
    var r92: i64 = 0;
    _ = &r92;
    var r93: i64 = 0;
    _ = &r93;
    var r94: i64 = 0;
    _ = &r94;
    var r95: i64 = 0;
    _ = &r95;
    var r96: i64 = 0;
    _ = &r96;
    var r97: i64 = 0;
    _ = &r97;
    var r98: i64 = 0;
    _ = &r98;
    var r99: i64 = 0;
    _ = &r99;
    var r100: i64 = 0;
    _ = &r100;
    var r101: i64 = 0;
    _ = &r101;
    var r102: i64 = 0;
    _ = &r102;
    var r103: i64 = 0;
    _ = &r103;
    var r104: i64 = 0;
    _ = &r104;
    var r105: i64 = 0;
    _ = &r105;
    var r106: i64 = 0;
    _ = &r106;
    var r107: i64 = 0;
    _ = &r107;
    var r108: i64 = 0;
    _ = &r108;
    var r109: i64 = 0;
    _ = &r109;
    var r110: i64 = 0;
    _ = &r110;
    var r111: i64 = 0;
    _ = &r111;
    var r112: i64 = 0;
    _ = &r112;
    var r113: i64 = 0;
    _ = &r113;
    var r114: i64 = 0;
    _ = &r114;
    var r115: i64 = 0;
    _ = &r115;
    var r116: i64 = 0;
    _ = &r116;
    var r117: i64 = 0;
    _ = &r117;
    var r118: i64 = 0;
    _ = &r118;
    var r119: i64 = 0;
    _ = &r119;
    var r120: i64 = 0;
    _ = &r120;
    var r121: i64 = 0;
    _ = &r121;
    var r122: i64 = 0;
    _ = &r122;
    var r123: i64 = 0;
    _ = &r123;
    var r124: i64 = 0;
    _ = &r124;
    var r125: i64 = 0;
    _ = &r125;
    var r126: i64 = 0;
    _ = &r126;
    var r127: i64 = 0;
    _ = &r127;
    var r128: i64 = 0;
    _ = &r128;
    var r129: i64 = 0;
    _ = &r129;
    var r130: i64 = 0;
    _ = &r130;
    var r131: i64 = 0;
    _ = &r131;
    var r132: i64 = 0;
    _ = &r132;
    var r133: i64 = 0;
    _ = &r133;
    var r134: i64 = 0;
    _ = &r134;
    var r135: i64 = 0;
    _ = &r135;
    var r136: i64 = 0;
    _ = &r136;
    var r137: i64 = 0;
    _ = &r137;
    var r138: i64 = 0;
    _ = &r138;
    var r139: i64 = 0;
    _ = &r139;
    var r140: i64 = 0;
    _ = &r140;
    var r141: i64 = 0;
    _ = &r141;
    var r142: i64 = 0;
    _ = &r142;
    var r143: i64 = 0;
    _ = &r143;
    var r144: i64 = 0;
    _ = &r144;
    var r145: i64 = 0;
    _ = &r145;
    var r146: i64 = 0;
    _ = &r146;
    var r147: i64 = 0;
    _ = &r147;
    var r148: i64 = 0;
    _ = &r148;
    var r149: i64 = 0;
    _ = &r149;
    var r150: i64 = 0;
    _ = &r150;
    var r151: i64 = 0;
    _ = &r151;
    var r152: i64 = 0;
    _ = &r152;
    var r153: i64 = 0;
    _ = &r153;
    var r154: i64 = 0;
    _ = &r154;
    var r155: i64 = 0;
    _ = &r155;
    var r156: i64 = 0;
    _ = &r156;
    var r157: i64 = 0;
    _ = &r157;
    var r158: i64 = 0;
    _ = &r158;
    var r159: i64 = 0;
    _ = &r159;
    var r160: i64 = 0;
    _ = &r160;
    var r161: i64 = 0;
    _ = &r161;
    var r162: i64 = 0;
    _ = &r162;
    var r163: i64 = 0;
    _ = &r163;
    var r164: i64 = 0;
    _ = &r164;
    var r165: i64 = 0;
    _ = &r165;
    var r166: i64 = 0;
    _ = &r166;
    var r167: i64 = 0;
    _ = &r167;
    var r168: i64 = 0;
    _ = &r168;
    var r169: i64 = 0;
    _ = &r169;
    var r170: i64 = 0;
    _ = &r170;
    var r171: i64 = 0;
    _ = &r171;
    var r172: i64 = 0;
    _ = &r172;
    var r173: i64 = 0;
    _ = &r173;
    var r174: i64 = 0;
    _ = &r174;
    var r175: i64 = 0;
    _ = &r175;
    var r176: i64 = 0;
    _ = &r176;
    var r177: i64 = 0;
    _ = &r177;
    var r178: i64 = 0;
    _ = &r178;
    var r179: i64 = 0;
    _ = &r179;
    var r180: i64 = 0;
    _ = &r180;
    var r181: i64 = 0;
    _ = &r181;
    var r182: i64 = 0;
    _ = &r182;
    var r183: i64 = 0;
    _ = &r183;
    var r184: i64 = 0;
    _ = &r184;
    var r185: i64 = 0;
    _ = &r185;
    var r186: i64 = 0;
    _ = &r186;
    var r187: i64 = 0;
    _ = &r187;
    var r188: i64 = 0;
    _ = &r188;
    var r189: i64 = 0;
    _ = &r189;
    var r190: i64 = 0;
    _ = &r190;
    var r191: i64 = 0;
    _ = &r191;
    var r192: i64 = 0;
    _ = &r192;
    var r193: i64 = 0;
    _ = &r193;
    var r194: i64 = 0;
    _ = &r194;
    var r195: i64 = 0;
    _ = &r195;
    var r196: i64 = 0;
    _ = &r196;
    var r197: i64 = 0;
    _ = &r197;
    var r198: i64 = 0;
    _ = &r198;
    var r199: i64 = 0;
    _ = &r199;
    var r200: i64 = 0;
    _ = &r200;
    var r201: i64 = 0;
    _ = &r201;
    var r202: i64 = 0;
    _ = &r202;
    var r203: i64 = 0;
    _ = &r203;
    var r204: i64 = 0;
    _ = &r204;
    var r205: i64 = 0;
    _ = &r205;
    var r206: i64 = 0;
    _ = &r206;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_start_pos;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[1];
                locals[2] = r0;
                r1 = 0;
                locals[3] = r1;
                r2 = locals[2];
                r3 = 1;
                r4 = r2 +% r3;
                locals[2] = r4;
                r5 = locals[0];
                r6 = locals[2];
                r7 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r8 = 6;
                r9 = verve_Parser_expect_kind(r5, r6, r7);
                locals[2] = r9;
                var list_10 = List.init();
                r10 = @intCast(@intFromPtr(&list_10));
                locals[4] = r10;
                block = 1; continue;
            },
            1 => {
                r11 = locals[0];
                r12 = locals[2];
                r13 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r14 = 6;
                r15 = verve_Parser_is_kind(r11, r12, r13);
                r16 = if (r15 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r16 != 0) 2 else 3; continue;
            },
            2 => {
                r17 = locals[0];
                r18 = locals[2];
                r19 = @intCast(@intFromPtr(@as([*]const u8, "doc")));
                r20 = 3;
                r21 = verve_Parser_is_kind(r17, r18, r19);
                block = if (r21 != 0) 4 else 6; continue;
            },
            3 => {
                r192 = locals[0];
                r193 = locals[2];
                r194 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r195 = 6;
                r196 = verve_Parser_expect_kind(r192, r193, r194);
                locals[2] = r196;
                r197 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 2) catch &.{}).ptr));
                r198 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r197))))))[0] = r198;
                r199 = @intCast(@intFromPtr(@as([*]const u8, "module")));
                r200 = 6;
                r201 = locals[3];
                r202 = locals[5];
                r203 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r204 = 0;
                r205 = locals[4];
                r206 = verve_Parser_node_with(r199, r201, r203, r205);
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r197))))))[1] = r206;
                return r197;
            },
            4 => {
                r22 = locals[2];
                r23 = 1;
                r24 = r22 +% r23;
                locals[2] = r24;
                block = 1; continue;
            },
            5 => {
                block = 6;
            },
            6 => {
                r25 = locals[0];
                r26 = locals[2];
                r27 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r28 = 2;
                r29 = verve_Parser_is_kw(r25, r26, r27);
                block = if (r29 != 0) 7 else 8; continue;
            },
            7 => {
                r30 = locals[2];
                r31 = 1;
                r32 = r30 +% r31;
                locals[2] = r32;
                r33 = locals[0];
                r34 = locals[2];
                r35 = verve_Parser_parse_function(r33, r34);
                locals[6] = r35;
                r36 = locals[4];
                r37 = locals[6];
                r38 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37))))))[1];
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36)))))).append(r38);
                r39 = locals[6];
                r40 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r39))))))[0];
                locals[2] = r40;
                block = 9; continue;
            },
            8 => {
                r41 = locals[0];
                r42 = locals[2];
                r43 = @intCast(@intFromPtr(@as([*]const u8, "use")));
                r44 = 3;
                r45 = verve_Parser_is_kw(r41, r42, r43);
                block = if (r45 != 0) 10 else 11; continue;
            },
            9 => {
                block = 1; continue;
            },
            10 => {
                r46 = locals[2];
                r47 = 1;
                r48 = r46 +% r47;
                locals[2] = r48;
                r49 = 0;
                locals[7] = r49;
                r50 = locals[2];
                r51 = 1;
                r52 = r50 +% r51;
                locals[2] = r52;
                r53 = locals[0];
                r54 = locals[2];
                r55 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r56 = 6;
                r57 = verve_Parser_expect_kind(r53, r54, r55);
                locals[2] = r57;
                block = 13; continue;
            },
            11 => {
                r85 = locals[0];
                r86 = locals[2];
                r87 = @intCast(@intFromPtr(@as([*]const u8, "ident")));
                r88 = 5;
                r89 = verve_Parser_is_kind(r85, r86, r87);
                block = if (r89 != 0) 16 else 17; continue;
            },
            12 => {
                block = 9; continue;
            },
            13 => {
                r58 = locals[0];
                r59 = locals[2];
                r60 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r61 = 6;
                r62 = verve_Parser_is_kind(r58, r59, r60);
                r63 = if (r62 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r63 != 0) 14 else 15; continue;
            },
            14 => {
                r64 = locals[2];
                r65 = 1;
                r66 = r64 +% r65;
                locals[2] = r66;
                block = 13; continue;
            },
            15 => {
                r67 = locals[0];
                r68 = locals[2];
                r69 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r70 = 6;
                r71 = verve_Parser_expect_kind(r67, r68, r69);
                locals[2] = r71;
                r72 = locals[0];
                r73 = locals[2];
                r74 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r75 = 4;
                r76 = verve_Parser_expect_kind(r72, r73, r74);
                locals[2] = r76;
                r77 = locals[4];
                r78 = @intCast(@intFromPtr(@as([*]const u8, "use")));
                r79 = 3;
                r80 = locals[7];
                r81 = locals[8];
                r82 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r83 = 0;
                r84 = verve_Parser_node(r78, r80, r82);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r77)))))).append(r84);
                block = 12; continue;
            },
            16 => {
                r90 = 0;
                locals[9] = r90;
                r91 = locals[2];
                r92 = 1;
                r93 = r91 +% r92;
                locals[2] = r93;
                r94 = locals[0];
                r95 = locals[2];
                r96 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r97 = 5;
                r98 = verve_Parser_expect_kind(r94, r95, r96);
                locals[2] = r98;
                r99 = 0;
                locals[10] = r99;
                r100 = locals[2];
                r101 = 1;
                r102 = r100 +% r101;
                locals[2] = r102;
                r103 = locals[0];
                r104 = locals[2];
                r105 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r106 = 2;
                r107 = verve_Parser_is_kind(r103, r104, r105);
                block = if (r107 != 0) 19 else 21; continue;
            },
            17 => {
                r170 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected in module: ")));
                r171 = 22;
                r172 = 0;
                r173 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r174 = 2;
                r175 = 0;
                r176 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r177 = 1;
                r179 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected in module: ")));
                r180 = 22;
                r181 = 0;
                r182 = -1;
                r183 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r184 = 2;
                r185 = 0;
                r186 = -1;
                r187 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r188 = 1;
                if (r180 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r179}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r179))))), r180); }
                if (r182 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r181}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))), r182); }
                if (r184 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r183}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r183))))), r184); }
                if (r186 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r185}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r185))))), r186); }
                if (r188 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r187}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r187))))), r188); }
                verve_write(1, "\n", 1);
                r178 = 0;
                r189 = locals[2];
                r190 = 1;
                r191 = r189 +% r190;
                locals[2] = r191;
                block = 18; continue;
            },
            18 => {
                block = 12; continue;
            },
            19 => {
                block = 22; continue;
            },
            20 => {
                block = 21;
            },
            21 => {
                r120 = locals[0];
                r121 = locals[2];
                r122 = @intCast(@intFromPtr(@as([*]const u8, "eq")));
                r123 = 2;
                r124 = verve_Parser_expect_kind(r120, r121, r122);
                locals[2] = r124;
                r125 = 0;
                locals[11] = r125;
                block = 25; continue;
            },
            22 => {
                r108 = locals[0];
                r109 = locals[2];
                r110 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r111 = 2;
                r112 = verve_Parser_is_kind(r108, r109, r110);
                r113 = if (r112 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r113 != 0) 23 else 24; continue;
            },
            23 => {
                r114 = locals[2];
                r115 = 1;
                r116 = r114 +% r115;
                locals[2] = r116;
                block = 22; continue;
            },
            24 => {
                r117 = locals[2];
                r118 = 1;
                r119 = r117 +% r118;
                locals[2] = r119;
                block = 21; continue;
            },
            25 => {
                r126 = locals[2];
                r127 = locals[0];
                r128 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r127)))))).len;
                r129 = if (r126 < r128) @as(i64, 1) else @as(i64, 0);
                block = if (r129 != 0) 26 else 27; continue;
            },
            26 => {
                r130 = locals[0];
                r131 = locals[2];
                r132 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r133 = 4;
                r134 = verve_Parser_is_kind(r130, r131, r132);
                block = if (r134 != 0) 28 else 30; continue;
            },
            27 => {
                r157 = locals[0];
                r158 = locals[2];
                r159 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r160 = 4;
                r161 = verve_Parser_expect_kind(r157, r158, r159);
                locals[2] = r161;
                r162 = locals[4];
                r163 = @intCast(@intFromPtr(@as([*]const u8, "const")));
                r164 = 5;
                r165 = locals[9];
                r166 = locals[12];
                r167 = locals[10];
                r168 = locals[13];
                r169 = verve_Parser_node(r163, r165, r167);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r162)))))).append(r169);
                block = 18; continue;
            },
            28 => {
                r135 = locals[11];
                r136 = 0;
                r137 = if (r135 == r136) @as(i64, 1) else @as(i64, 0);
                block = if (r137 != 0) 31 else 33; continue;
            },
            29 => {
                block = 30;
            },
            30 => {
                r138 = locals[0];
                r139 = locals[2];
                r140 = @intCast(@intFromPtr(@as([*]const u8, "lparen")));
                r141 = 6;
                r142 = verve_Parser_is_kind(r138, r139, r140);
                block = if (r142 != 0) 34 else 36; continue;
            },
            31 => {
                block = 27; continue;
            },
            32 => {
                block = 33;
            },
            33 => {
                block = 30; continue;
            },
            34 => {
                r143 = locals[11];
                r144 = 1;
                r145 = r143 +% r144;
                locals[11] = r145;
                block = 36; continue;
            },
            35 => {
                block = 36;
            },
            36 => {
                r146 = locals[0];
                r147 = locals[2];
                r148 = @intCast(@intFromPtr(@as([*]const u8, "rparen")));
                r149 = 6;
                r150 = verve_Parser_is_kind(r146, r147, r148);
                block = if (r150 != 0) 37 else 39; continue;
            },
            37 => {
                r151 = locals[11];
                r152 = 1;
                r153 = r151 -% r152;
                locals[11] = r153;
                block = 39; continue;
            },
            38 => {
                block = 39;
            },
            39 => {
                r154 = locals[2];
                r155 = 1;
                r156 = r154 +% r155;
                locals[2] = r156;
                block = 25; continue;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Parser_parse_function(param_tokens: i64, param_start_pos: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var r84: i64 = 0;
    _ = &r84;
    var r85: i64 = 0;
    _ = &r85;
    var r86: i64 = 0;
    _ = &r86;
    var r87: i64 = 0;
    _ = &r87;
    var r88: i64 = 0;
    _ = &r88;
    var r89: i64 = 0;
    _ = &r89;
    var r90: i64 = 0;
    _ = &r90;
    var r91: i64 = 0;
    _ = &r91;
    var r92: i64 = 0;
    _ = &r92;
    var r93: i64 = 0;
    _ = &r93;
    var r94: i64 = 0;
    _ = &r94;
    var r95: i64 = 0;
    _ = &r95;
    var r96: i64 = 0;
    _ = &r96;
    var r97: i64 = 0;
    _ = &r97;
    var r98: i64 = 0;
    _ = &r98;
    var r99: i64 = 0;
    _ = &r99;
    var r100: i64 = 0;
    _ = &r100;
    var r101: i64 = 0;
    _ = &r101;
    var r102: i64 = 0;
    _ = &r102;
    var r103: i64 = 0;
    _ = &r103;
    var r104: i64 = 0;
    _ = &r104;
    var r105: i64 = 0;
    _ = &r105;
    var r106: i64 = 0;
    _ = &r106;
    var r107: i64 = 0;
    _ = &r107;
    var r108: i64 = 0;
    _ = &r108;
    var r109: i64 = 0;
    _ = &r109;
    var r110: i64 = 0;
    _ = &r110;
    var r111: i64 = 0;
    _ = &r111;
    var r112: i64 = 0;
    _ = &r112;
    var r113: i64 = 0;
    _ = &r113;
    var r114: i64 = 0;
    _ = &r114;
    var r115: i64 = 0;
    _ = &r115;
    var r116: i64 = 0;
    _ = &r116;
    var r117: i64 = 0;
    _ = &r117;
    var r118: i64 = 0;
    _ = &r118;
    var r119: i64 = 0;
    _ = &r119;
    var r120: i64 = 0;
    _ = &r120;
    var r121: i64 = 0;
    _ = &r121;
    var r122: i64 = 0;
    _ = &r122;
    var r123: i64 = 0;
    _ = &r123;
    var r124: i64 = 0;
    _ = &r124;
    var r125: i64 = 0;
    _ = &r125;
    var r126: i64 = 0;
    _ = &r126;
    var r127: i64 = 0;
    _ = &r127;
    var r128: i64 = 0;
    _ = &r128;
    var r129: i64 = 0;
    _ = &r129;
    var r130: i64 = 0;
    _ = &r130;
    var r131: i64 = 0;
    _ = &r131;
    var r132: i64 = 0;
    _ = &r132;
    var r133: i64 = 0;
    _ = &r133;
    var r134: i64 = 0;
    _ = &r134;
    var r135: i64 = 0;
    _ = &r135;
    var r136: i64 = 0;
    _ = &r136;
    var r137: i64 = 0;
    _ = &r137;
    var r138: i64 = 0;
    _ = &r138;
    var r139: i64 = 0;
    _ = &r139;
    var r140: i64 = 0;
    _ = &r140;
    var r141: i64 = 0;
    _ = &r141;
    var r142: i64 = 0;
    _ = &r142;
    var r143: i64 = 0;
    _ = &r143;
    var r144: i64 = 0;
    _ = &r144;
    var r145: i64 = 0;
    _ = &r145;
    var r146: i64 = 0;
    _ = &r146;
    var r147: i64 = 0;
    _ = &r147;
    var r148: i64 = 0;
    _ = &r148;
    var r149: i64 = 0;
    _ = &r149;
    var r150: i64 = 0;
    _ = &r150;
    var r151: i64 = 0;
    _ = &r151;
    var r152: i64 = 0;
    _ = &r152;
    var r153: i64 = 0;
    _ = &r153;
    var r154: i64 = 0;
    _ = &r154;
    var r155: i64 = 0;
    _ = &r155;
    var r156: i64 = 0;
    _ = &r156;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_tokens;
    locals[1] = param_start_pos;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[1];
                locals[2] = r0;
                r1 = 0;
                locals[3] = r1;
                r2 = locals[2];
                r3 = 1;
                r4 = r2 +% r3;
                locals[2] = r4;
                r5 = locals[0];
                r6 = locals[2];
                r7 = @intCast(@intFromPtr(@as([*]const u8, "lparen")));
                r8 = 6;
                r9 = verve_Parser_expect_kind(r5, r6, r7);
                locals[2] = r9;
                var list_10 = List.init();
                r10 = @intCast(@intFromPtr(&list_10));
                locals[4] = r10;
                block = 1; continue;
            },
            1 => {
                r11 = locals[0];
                r12 = locals[2];
                r13 = @intCast(@intFromPtr(@as([*]const u8, "rparen")));
                r14 = 6;
                r15 = verve_Parser_is_kind(r11, r12, r13);
                r16 = if (r15 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r16 != 0) 2 else 3; continue;
            },
            2 => {
                r17 = 0;
                locals[5] = r17;
                r18 = locals[2];
                r19 = 1;
                r20 = r18 +% r19;
                locals[2] = r20;
                r21 = locals[0];
                r22 = locals[2];
                r23 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r24 = 5;
                r25 = verve_Parser_expect_kind(r21, r22, r23);
                locals[2] = r25;
                r26 = 0;
                locals[6] = r26;
                r27 = locals[2];
                r28 = 1;
                r29 = r27 +% r28;
                locals[2] = r29;
                r30 = locals[0];
                r31 = locals[2];
                r32 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r33 = 2;
                r34 = verve_Parser_is_kind(r30, r31, r32);
                block = if (r34 != 0) 4 else 6; continue;
            },
            3 => {
                r63 = locals[0];
                r64 = locals[2];
                r65 = @intCast(@intFromPtr(@as([*]const u8, "rparen")));
                r66 = 6;
                r67 = verve_Parser_expect_kind(r63, r64, r65);
                locals[2] = r67;
                r68 = locals[0];
                r69 = locals[2];
                r70 = @intCast(@intFromPtr(@as([*]const u8, "arrow")));
                r71 = 5;
                r72 = verve_Parser_expect_kind(r68, r69, r70);
                locals[2] = r72;
                r73 = 0;
                locals[7] = r73;
                r74 = locals[2];
                r75 = 1;
                r76 = r74 +% r75;
                locals[2] = r76;
                r77 = locals[0];
                r78 = locals[2];
                r79 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r80 = 2;
                r81 = verve_Parser_is_kind(r77, r78, r79);
                block = if (r81 != 0) 13 else 15; continue;
            },
            4 => {
                block = 7; continue;
            },
            5 => {
                block = 6;
            },
            6 => {
                r47 = locals[4];
                r48 = @intCast(@intFromPtr(@as([*]const u8, "param")));
                r49 = 5;
                r50 = locals[5];
                r51 = locals[8];
                r52 = locals[6];
                r53 = locals[9];
                r54 = verve_Parser_node(r48, r50, r52);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r47)))))).append(r54);
                r55 = locals[0];
                r56 = locals[2];
                r57 = @intCast(@intFromPtr(@as([*]const u8, "comma")));
                r58 = 5;
                r59 = verve_Parser_is_kind(r55, r56, r57);
                block = if (r59 != 0) 10 else 12; continue;
            },
            7 => {
                r35 = locals[0];
                r36 = locals[2];
                r37 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r38 = 2;
                r39 = verve_Parser_is_kind(r35, r36, r37);
                r40 = if (r39 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r40 != 0) 8 else 9; continue;
            },
            8 => {
                r41 = locals[2];
                r42 = 1;
                r43 = r41 +% r42;
                locals[2] = r43;
                block = 7; continue;
            },
            9 => {
                r44 = locals[2];
                r45 = 1;
                r46 = r44 +% r45;
                locals[2] = r46;
                block = 6; continue;
            },
            10 => {
                r60 = locals[2];
                r61 = 1;
                r62 = r60 +% r61;
                locals[2] = r62;
                block = 12; continue;
            },
            11 => {
                block = 12;
            },
            12 => {
                block = 1; continue;
            },
            13 => {
                block = 16; continue;
            },
            14 => {
                block = 15;
            },
            15 => {
                r94 = locals[0];
                r95 = locals[2];
                r96 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r97 = 6;
                r98 = verve_Parser_expect_kind(r94, r95, r96);
                locals[2] = r98;
                r99 = 1;
                locals[10] = r99;
                r100 = 0;
                locals[11] = r100;
                block = 19; continue;
            },
            16 => {
                r82 = locals[0];
                r83 = locals[2];
                r84 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r85 = 2;
                r86 = verve_Parser_is_kind(r82, r83, r84);
                r87 = if (r86 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r87 != 0) 17 else 18; continue;
            },
            17 => {
                r88 = locals[2];
                r89 = 1;
                r90 = r88 +% r89;
                locals[2] = r90;
                block = 16; continue;
            },
            18 => {
                r91 = locals[2];
                r92 = 1;
                r93 = r91 +% r92;
                locals[2] = r93;
                block = 15; continue;
            },
            19 => {
                r101 = locals[10];
                r102 = 0;
                r103 = if (r101 > r102) @as(i64, 1) else @as(i64, 0);
                block = if (r103 != 0) 20 else 21; continue;
            },
            20 => {
                r104 = locals[0];
                r105 = locals[2];
                r106 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r107 = 6;
                r108 = verve_Parser_is_kind(r104, r105, r106);
                block = if (r108 != 0) 22 else 24; continue;
            },
            21 => {
                r129 = locals[0];
                r130 = locals[2];
                r131 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r132 = 6;
                r133 = verve_Parser_expect_kind(r129, r130, r131);
                locals[2] = r133;
                r134 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r135 = 2;
                r136 = locals[3];
                r137 = locals[12];
                r138 = locals[7];
                r139 = locals[13];
                r140 = verve_Parser_node(r134, r136, r138);
                locals[14] = r140;
                r141 = 0;
                locals[15] = r141;
                block = 31; continue;
            },
            22 => {
                r109 = locals[10];
                r110 = 1;
                r111 = r109 +% r110;
                locals[10] = r111;
                block = 24; continue;
            },
            23 => {
                block = 24;
            },
            24 => {
                r112 = locals[0];
                r113 = locals[2];
                r114 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r115 = 6;
                r116 = verve_Parser_is_kind(r112, r113, r114);
                block = if (r116 != 0) 25 else 27; continue;
            },
            25 => {
                r117 = locals[10];
                r118 = 1;
                r119 = r117 -% r118;
                locals[10] = r119;
                block = 27; continue;
            },
            26 => {
                block = 27;
            },
            27 => {
                r120 = locals[10];
                r121 = 0;
                r122 = if (r120 > r121) @as(i64, 1) else @as(i64, 0);
                block = if (r122 != 0) 28 else 30; continue;
            },
            28 => {
                r123 = locals[11];
                r124 = 1;
                r125 = r123 +% r124;
                locals[11] = r125;
                r126 = locals[2];
                r127 = 1;
                r128 = r126 +% r127;
                locals[2] = r128;
                block = 30; continue;
            },
            29 => {
                block = 30;
            },
            30 => {
                block = 19; continue;
            },
            31 => {
                r142 = locals[15];
                r143 = locals[4];
                r144 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r143)))))).len;
                r145 = if (r142 < r144) @as(i64, 1) else @as(i64, 0);
                block = if (r145 != 0) 32 else 33; continue;
            },
            32 => {
                r146 = locals[14];
                r147 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r146))))))[3];
                r148 = locals[4];
                r149 = locals[15];
                r150 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r148)))))).get(r149);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r147)))))).append(r150);
                r151 = locals[15];
                r152 = 1;
                r153 = r151 +% r152;
                locals[15] = r153;
                block = 31; continue;
            },
            33 => {
                r154 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 2) catch &.{}).ptr));
                r155 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154))))))[0] = r155;
                r156 = locals[14];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154))))))[1] = r156;
                return r154;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Printer_print_node(param_n: i64, param_depth: i64) i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var r84: i64 = 0;
    _ = &r84;
    var r85: i64 = 0;
    _ = &r85;
    var r86: i64 = 0;
    _ = &r86;
    var r87: i64 = 0;
    _ = &r87;
    var r88: i64 = 0;
    _ = &r88;
    var r89: i64 = 0;
    _ = &r89;
    var r90: i64 = 0;
    _ = &r90;
    var r91: i64 = 0;
    _ = &r91;
    var r92: i64 = 0;
    _ = &r92;
    var r93: i64 = 0;
    _ = &r93;
    var r94: i64 = 0;
    _ = &r94;
    var r95: i64 = 0;
    _ = &r95;
    var r96: i64 = 0;
    _ = &r96;
    var r97: i64 = 0;
    _ = &r97;
    var r98: i64 = 0;
    _ = &r98;
    var r99: i64 = 0;
    _ = &r99;
    var r100: i64 = 0;
    _ = &r100;
    var r101: i64 = 0;
    _ = &r101;
    var r102: i64 = 0;
    _ = &r102;
    var r103: i64 = 0;
    _ = &r103;
    var r104: i64 = 0;
    _ = &r104;
    var r105: i64 = 0;
    _ = &r105;
    var r106: i64 = 0;
    _ = &r106;
    var r107: i64 = 0;
    _ = &r107;
    var r108: i64 = 0;
    _ = &r108;
    var r109: i64 = 0;
    _ = &r109;
    var r110: i64 = 0;
    _ = &r110;
    var r111: i64 = 0;
    _ = &r111;
    var r112: i64 = 0;
    _ = &r112;
    var r113: i64 = 0;
    _ = &r113;
    var r114: i64 = 0;
    _ = &r114;
    var r115: i64 = 0;
    _ = &r115;
    var r116: i64 = 0;
    _ = &r116;
    var r117: i64 = 0;
    _ = &r117;
    var r118: i64 = 0;
    _ = &r118;
    var r119: i64 = 0;
    _ = &r119;
    var r120: i64 = 0;
    _ = &r120;
    var r121: i64 = 0;
    _ = &r121;
    var r122: i64 = 0;
    _ = &r122;
    var r123: i64 = 0;
    _ = &r123;
    var r124: i64 = 0;
    _ = &r124;
    var r125: i64 = 0;
    _ = &r125;
    var r126: i64 = 0;
    _ = &r126;
    var r127: i64 = 0;
    _ = &r127;
    var r128: i64 = 0;
    _ = &r128;
    var r129: i64 = 0;
    _ = &r129;
    var r130: i64 = 0;
    _ = &r130;
    var r131: i64 = 0;
    _ = &r131;
    var r132: i64 = 0;
    _ = &r132;
    var r133: i64 = 0;
    _ = &r133;
    var r134: i64 = 0;
    _ = &r134;
    var r135: i64 = 0;
    _ = &r135;
    var r136: i64 = 0;
    _ = &r136;
    var r137: i64 = 0;
    _ = &r137;
    var r138: i64 = 0;
    _ = &r138;
    var r139: i64 = 0;
    _ = &r139;
    var r140: i64 = 0;
    _ = &r140;
    var r141: i64 = 0;
    _ = &r141;
    var r142: i64 = 0;
    _ = &r142;
    var r143: i64 = 0;
    _ = &r143;
    var r144: i64 = 0;
    _ = &r144;
    var r145: i64 = 0;
    _ = &r145;
    var r146: i64 = 0;
    _ = &r146;
    var r147: i64 = 0;
    _ = &r147;
    var r148: i64 = 0;
    _ = &r148;
    var r149: i64 = 0;
    _ = &r149;
    var r150: i64 = 0;
    _ = &r150;
    var r151: i64 = 0;
    _ = &r151;
    var r152: i64 = 0;
    _ = &r152;
    var r153: i64 = 0;
    _ = &r153;
    var r154: i64 = 0;
    _ = &r154;
    var r155: i64 = 0;
    _ = &r155;
    var r156: i64 = 0;
    _ = &r156;
    var r157: i64 = 0;
    _ = &r157;
    var r158: i64 = 0;
    _ = &r158;
    var r159: i64 = 0;
    _ = &r159;
    var r160: i64 = 0;
    _ = &r160;
    var r161: i64 = 0;
    _ = &r161;
    var r162: i64 = 0;
    _ = &r162;
    var r163: i64 = 0;
    _ = &r163;
    var r164: i64 = 0;
    _ = &r164;
    var r165: i64 = 0;
    _ = &r165;
    var r166: i64 = 0;
    _ = &r166;
    var r167: i64 = 0;
    _ = &r167;
    var r168: i64 = 0;
    _ = &r168;
    var r169: i64 = 0;
    _ = &r169;
    var r170: i64 = 0;
    _ = &r170;
    var r171: i64 = 0;
    _ = &r171;
    var r172: i64 = 0;
    _ = &r172;
    var r173: i64 = 0;
    _ = &r173;
    var r174: i64 = 0;
    _ = &r174;
    var r175: i64 = 0;
    _ = &r175;
    var r176: i64 = 0;
    _ = &r176;
    var r177: i64 = 0;
    _ = &r177;
    var r178: i64 = 0;
    _ = &r178;
    var r179: i64 = 0;
    _ = &r179;
    var r180: i64 = 0;
    _ = &r180;
    var r181: i64 = 0;
    _ = &r181;
    var r182: i64 = 0;
    _ = &r182;
    var r183: i64 = 0;
    _ = &r183;
    var r184: i64 = 0;
    _ = &r184;
    var r185: i64 = 0;
    _ = &r185;
    var r186: i64 = 0;
    _ = &r186;
    var r187: i64 = 0;
    _ = &r187;
    var r188: i64 = 0;
    _ = &r188;
    var r189: i64 = 0;
    _ = &r189;
    var r190: i64 = 0;
    _ = &r190;
    var r191: i64 = 0;
    _ = &r191;
    var r192: i64 = 0;
    _ = &r192;
    var r193: i64 = 0;
    _ = &r193;
    var r194: i64 = 0;
    _ = &r194;
    var r195: i64 = 0;
    _ = &r195;
    var r196: i64 = 0;
    _ = &r196;
    var r197: i64 = 0;
    _ = &r197;
    var r198: i64 = 0;
    _ = &r198;
    var r199: i64 = 0;
    _ = &r199;
    var r200: i64 = 0;
    _ = &r200;
    var r201: i64 = 0;
    _ = &r201;
    var r202: i64 = 0;
    _ = &r202;
    var r203: i64 = 0;
    _ = &r203;
    var r204: i64 = 0;
    _ = &r204;
    var r205: i64 = 0;
    _ = &r205;
    var r206: i64 = 0;
    _ = &r206;
    var r207: i64 = 0;
    _ = &r207;
    var r208: i64 = 0;
    _ = &r208;
    var r209: i64 = 0;
    _ = &r209;
    var r210: i64 = 0;
    _ = &r210;
    var r211: i64 = 0;
    _ = &r211;
    var r212: i64 = 0;
    _ = &r212;
    var r213: i64 = 0;
    _ = &r213;
    var r214: i64 = 0;
    _ = &r214;
    var r215: i64 = 0;
    _ = &r215;
    var r216: i64 = 0;
    _ = &r216;
    var r217: i64 = 0;
    _ = &r217;
    var r218: i64 = 0;
    _ = &r218;
    var r219: i64 = 0;
    _ = &r219;
    var r220: i64 = 0;
    _ = &r220;
    var r221: i64 = 0;
    _ = &r221;
    var r222: i64 = 0;
    _ = &r222;
    var r223: i64 = 0;
    _ = &r223;
    var r224: i64 = 0;
    _ = &r224;
    var r225: i64 = 0;
    _ = &r225;
    var r226: i64 = 0;
    _ = &r226;
    var r227: i64 = 0;
    _ = &r227;
    var r228: i64 = 0;
    _ = &r228;
    var r229: i64 = 0;
    _ = &r229;
    var r230: i64 = 0;
    _ = &r230;
    var r231: i64 = 0;
    _ = &r231;
    var r232: i64 = 0;
    _ = &r232;
    var r233: i64 = 0;
    _ = &r233;
    var r234: i64 = 0;
    _ = &r234;
    var r235: i64 = 0;
    _ = &r235;
    var r236: i64 = 0;
    _ = &r236;
    var r237: i64 = 0;
    _ = &r237;
    var r238: i64 = 0;
    _ = &r238;
    var r239: i64 = 0;
    _ = &r239;
    var r240: i64 = 0;
    _ = &r240;
    var r241: i64 = 0;
    _ = &r241;
    var r242: i64 = 0;
    _ = &r242;
    var r243: i64 = 0;
    _ = &r243;
    var r244: i64 = 0;
    _ = &r244;
    var r245: i64 = 0;
    _ = &r245;
    var r246: i64 = 0;
    _ = &r246;
    var r247: i64 = 0;
    _ = &r247;
    var r248: i64 = 0;
    _ = &r248;
    var r249: i64 = 0;
    _ = &r249;
    var r250: i64 = 0;
    _ = &r250;
    var r251: i64 = 0;
    _ = &r251;
    var r252: i64 = 0;
    _ = &r252;
    var r253: i64 = 0;
    _ = &r253;
    var r254: i64 = 0;
    _ = &r254;
    var r255: i64 = 0;
    _ = &r255;
    var r256: i64 = 0;
    _ = &r256;
    var r257: i64 = 0;
    _ = &r257;
    var r258: i64 = 0;
    _ = &r258;
    var r259: i64 = 0;
    _ = &r259;
    var r260: i64 = 0;
    _ = &r260;
    var r261: i64 = 0;
    _ = &r261;
    var r262: i64 = 0;
    _ = &r262;
    var r263: i64 = 0;
    _ = &r263;
    var r264: i64 = 0;
    _ = &r264;
    var r265: i64 = 0;
    _ = &r265;
    var r266: i64 = 0;
    _ = &r266;
    var r267: i64 = 0;
    _ = &r267;
    var r268: i64 = 0;
    _ = &r268;
    var r269: i64 = 0;
    _ = &r269;
    var r270: i64 = 0;
    _ = &r270;
    var r271: i64 = 0;
    _ = &r271;
    var r272: i64 = 0;
    _ = &r272;
    var r273: i64 = 0;
    _ = &r273;
    var r274: i64 = 0;
    _ = &r274;
    var r275: i64 = 0;
    _ = &r275;
    var r276: i64 = 0;
    _ = &r276;
    var r277: i64 = 0;
    _ = &r277;
    var r278: i64 = 0;
    _ = &r278;
    var r279: i64 = 0;
    _ = &r279;
    var r280: i64 = 0;
    _ = &r280;
    var r281: i64 = 0;
    _ = &r281;
    var r282: i64 = 0;
    _ = &r282;
    var r283: i64 = 0;
    _ = &r283;
    var r284: i64 = 0;
    _ = &r284;
    var r285: i64 = 0;
    _ = &r285;
    var r286: i64 = 0;
    _ = &r286;
    var r287: i64 = 0;
    _ = &r287;
    var r288: i64 = 0;
    _ = &r288;
    var r289: i64 = 0;
    _ = &r289;
    var r290: i64 = 0;
    _ = &r290;
    var r291: i64 = 0;
    _ = &r291;
    var r292: i64 = 0;
    _ = &r292;
    var r293: i64 = 0;
    _ = &r293;
    var r294: i64 = 0;
    _ = &r294;
    var r295: i64 = 0;
    _ = &r295;
    var r296: i64 = 0;
    _ = &r296;
    var r297: i64 = 0;
    _ = &r297;
    var r298: i64 = 0;
    _ = &r298;
    var r299: i64 = 0;
    _ = &r299;
    var r300: i64 = 0;
    _ = &r300;
    var r301: i64 = 0;
    _ = &r301;
    var r302: i64 = 0;
    _ = &r302;
    var r303: i64 = 0;
    _ = &r303;
    var r304: i64 = 0;
    _ = &r304;
    var r305: i64 = 0;
    _ = &r305;
    var r306: i64 = 0;
    _ = &r306;
    var r307: i64 = 0;
    _ = &r307;
    var r308: i64 = 0;
    _ = &r308;
    var r309: i64 = 0;
    _ = &r309;
    var r310: i64 = 0;
    _ = &r310;
    var r311: i64 = 0;
    _ = &r311;
    var r312: i64 = 0;
    _ = &r312;
    var r313: i64 = 0;
    _ = &r313;
    var r314: i64 = 0;
    _ = &r314;
    var r315: i64 = 0;
    _ = &r315;
    var r316: i64 = 0;
    _ = &r316;
    var r317: i64 = 0;
    _ = &r317;
    var r318: i64 = 0;
    _ = &r318;
    var r319: i64 = 0;
    _ = &r319;
    var r320: i64 = 0;
    _ = &r320;
    var r321: i64 = 0;
    _ = &r321;
    var r322: i64 = 0;
    _ = &r322;
    var r323: i64 = 0;
    _ = &r323;
    var r324: i64 = 0;
    _ = &r324;
    var r325: i64 = 0;
    _ = &r325;
    var r326: i64 = 0;
    _ = &r326;
    var r327: i64 = 0;
    _ = &r327;
    var r328: i64 = 0;
    _ = &r328;
    var r329: i64 = 0;
    _ = &r329;
    var r330: i64 = 0;
    _ = &r330;
    var r331: i64 = 0;
    _ = &r331;
    var r332: i64 = 0;
    _ = &r332;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_n;
    locals[1] = param_depth;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r1 = 0;
                locals[2] = r0;
                locals[3] = r1;
                r2 = 0;
                locals[4] = r2;
                block = 1; continue;
            },
            1 => {
                r3 = locals[4];
                r4 = locals[1];
                r5 = if (r3 < r4) @as(i64, 1) else @as(i64, 0);
                block = if (r5 != 0) 2 else 3; continue;
            },
            2 => {
                r6 = locals[2];
                r7 = locals[3];
                r8 = @intCast(@intFromPtr(@as([*]const u8, "  ")));
                r9 = 2;
                r10 = r6 +% r8;
                locals[2] = r10;
                r11 = locals[4];
                r12 = 1;
                r13 = r11 +% r12;
                locals[4] = r13;
                block = 1; continue;
            },
            3 => {
                r14 = locals[0];
                r15 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r14))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r15)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r16 = @intCast(sl); }
                r17 = @intCast(@intFromPtr(@as([*]const u8, "module")));
                r18 = 6;
                r19 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r15))))), r16, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r17))))), r18)) @as(i64, 1) else @as(i64, 0);
                block = if (r19 != 0) 4 else 5; continue;
            },
            4 => {
                r20 = locals[2];
                r21 = locals[3];
                r22 = @intCast(@intFromPtr(@as([*]const u8, "module ")));
                r23 = 7;
                r24 = locals[0];
                r25 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r24))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r26 = @intCast(sl); }
                r28 = locals[2];
                r29 = locals[3];
                r30 = @intCast(@intFromPtr(@as([*]const u8, "module ")));
                r31 = 7;
                r32 = locals[0];
                r33 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r32))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r34 = @intCast(sl); }
                r35 = -1;
                if (r29 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r28}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r28))))), r29); }
                if (r31 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r30}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r30))))), r31); }
                if (r35 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r33}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33))))), r35); }
                verve_write(1, "\n", 1);
                r27 = 0;
                block = 6; continue;
            },
            5 => {
                r36 = locals[0];
                r37 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r38 = @intCast(sl); }
                r39 = @intCast(@intFromPtr(@as([*]const u8, "module_exported")));
                r40 = 15;
                r41 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37))))), r38, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r39))))), r40)) @as(i64, 1) else @as(i64, 0);
                block = if (r41 != 0) 7 else 8; continue;
            },
            6 => {
                r310 = 0;
                locals[5] = r310;
                block = 37; continue;
            },
            7 => {
                r42 = locals[2];
                r43 = locals[3];
                r44 = @intCast(@intFromPtr(@as([*]const u8, "export module ")));
                r45 = 14;
                r46 = locals[0];
                r47 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r46))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r47)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r48 = @intCast(sl); }
                r50 = locals[2];
                r51 = locals[3];
                r52 = @intCast(@intFromPtr(@as([*]const u8, "export module ")));
                r53 = 14;
                r54 = locals[0];
                r55 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r54))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r55)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r56 = @intCast(sl); }
                r57 = -1;
                if (r51 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r50}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r50))))), r51); }
                if (r53 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r52}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r52))))), r53); }
                if (r57 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r55}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r55))))), r57); }
                verve_write(1, "\n", 1);
                r49 = 0;
                block = 9; continue;
            },
            8 => {
                r58 = locals[0];
                r59 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r58))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r59)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r60 = @intCast(sl); }
                r61 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r62 = 2;
                r63 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r59))))), r60, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r61))))), r62)) @as(i64, 1) else @as(i64, 0);
                block = if (r63 != 0) 10 else 11; continue;
            },
            9 => {
                block = 6; continue;
            },
            10 => {
                r64 = locals[2];
                r65 = locals[3];
                r66 = @intCast(@intFromPtr(@as([*]const u8, "fn ")));
                r67 = 3;
                r68 = locals[0];
                r69 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r68))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r69)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r70 = @intCast(sl); }
                r71 = @intCast(@intFromPtr(@as([*]const u8, "(")));
                r72 = 1;
                r74 = locals[2];
                r75 = locals[3];
                r76 = @intCast(@intFromPtr(@as([*]const u8, "fn ")));
                r77 = 3;
                r78 = locals[0];
                r79 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r78))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r79)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r80 = @intCast(sl); }
                r81 = -1;
                r82 = @intCast(@intFromPtr(@as([*]const u8, "(")));
                r83 = 1;
                if (r75 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r74}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r74))))), r75); }
                if (r77 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r76}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r76))))), r77); }
                if (r81 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r79}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r79))))), r81); }
                if (r83 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r82}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r82))))), r83); }
                r73 = 0;
                r84 = 0;
                locals[6] = r84;
                block = 13; continue;
            },
            11 => {
                r134 = locals[0];
                r135 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r134))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r135)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r136 = @intCast(sl); }
                r137 = @intCast(@intFromPtr(@as([*]const u8, "const")));
                r138 = 5;
                r139 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r135))))), r136, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r137))))), r138)) @as(i64, 1) else @as(i64, 0);
                block = if (r139 != 0) 19 else 20; continue;
            },
            12 => {
                block = 9; continue;
            },
            13 => {
                r85 = locals[6];
                r86 = 0;
                r87 = if (r85 < r86) @as(i64, 1) else @as(i64, 0);
                block = if (r87 != 0) 14 else 15; continue;
            },
            14 => {
                r88 = locals[0];
                r89 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r88))))))[3];
                r90 = locals[6];
                r91 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r89)))))).get(r90);
                locals[7] = r91;
                r92 = locals[6];
                r93 = 0;
                r94 = if (r92 > r93) @as(i64, 1) else @as(i64, 0);
                block = if (r94 != 0) 16 else 18; continue;
            },
            15 => {
                r122 = @intCast(@intFromPtr(@as([*]const u8, ") -> ")));
                r123 = 5;
                r124 = locals[0];
                r125 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r124))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r125)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r126 = @intCast(sl); }
                r128 = @intCast(@intFromPtr(@as([*]const u8, ") -> ")));
                r129 = 5;
                r130 = locals[0];
                r131 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r130))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r131)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r132 = @intCast(sl); }
                r133 = -1;
                if (r129 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r128}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r128))))), r129); }
                if (r133 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r131}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r131))))), r133); }
                verve_write(1, "\n", 1);
                r127 = 0;
                block = 12; continue;
            },
            16 => {
                r95 = @intCast(@intFromPtr(@as([*]const u8, ", ")));
                r96 = 2;
                r98 = @intCast(@intFromPtr(@as([*]const u8, ", ")));
                r99 = 2;
                if (r99 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r98}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r98))))), r99); }
                r97 = 0;
                block = 18; continue;
            },
            17 => {
                block = 18;
            },
            18 => {
                r100 = locals[7];
                r101 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r100))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r101)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r102 = @intCast(sl); }
                r103 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r104 = 2;
                r105 = locals[7];
                r106 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r105))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r106)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r107 = @intCast(sl); }
                r109 = locals[7];
                r110 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r109))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r110)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r111 = @intCast(sl); }
                r112 = -1;
                r113 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r114 = 2;
                r115 = locals[7];
                r116 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r115))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r116)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r117 = @intCast(sl); }
                r118 = -1;
                if (r112 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r110}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r110))))), r112); }
                if (r114 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r113}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r113))))), r114); }
                if (r118 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r116}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r116))))), r118); }
                r108 = 0;
                r119 = locals[6];
                r120 = 1;
                r121 = r119 +% r120;
                locals[6] = r121;
                block = 13; continue;
            },
            19 => {
                r140 = locals[2];
                r141 = locals[3];
                r142 = locals[0];
                r143 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r142))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r143)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r144 = @intCast(sl); }
                r145 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r146 = 2;
                r147 = locals[0];
                r148 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r147))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r148)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r149 = @intCast(sl); }
                r151 = locals[2];
                r152 = locals[3];
                r153 = locals[0];
                r154 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r153))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r155 = @intCast(sl); }
                r156 = -1;
                r157 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r158 = 2;
                r159 = locals[0];
                r160 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r159))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r160)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r161 = @intCast(sl); }
                r162 = -1;
                if (r152 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r151}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r151))))), r152); }
                if (r156 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r154}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154))))), r156); }
                if (r158 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r157}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r157))))), r158); }
                if (r162 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r160}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r160))))), r162); }
                verve_write(1, "\n", 1);
                r150 = 0;
                block = 21; continue;
            },
            20 => {
                r163 = locals[0];
                r164 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r163))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r164)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r165 = @intCast(sl); }
                r166 = @intCast(@intFromPtr(@as([*]const u8, "use")));
                r167 = 3;
                r168 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r164))))), r165, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r166))))), r167)) @as(i64, 1) else @as(i64, 0);
                block = if (r168 != 0) 22 else 23; continue;
            },
            21 => {
                block = 12; continue;
            },
            22 => {
                r169 = locals[2];
                r170 = locals[3];
                r171 = @intCast(@intFromPtr(@as([*]const u8, "use ")));
                r172 = 4;
                r173 = locals[0];
                r174 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r173))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r174)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r175 = @intCast(sl); }
                r177 = locals[2];
                r178 = locals[3];
                r179 = @intCast(@intFromPtr(@as([*]const u8, "use ")));
                r180 = 4;
                r181 = locals[0];
                r182 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r182)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r183 = @intCast(sl); }
                r184 = -1;
                if (r178 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r177}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r177))))), r178); }
                if (r180 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r179}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r179))))), r180); }
                if (r184 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r182}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r182))))), r184); }
                verve_write(1, "\n", 1);
                r176 = 0;
                block = 24; continue;
            },
            23 => {
                r185 = locals[0];
                r186 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r185))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r186)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r187 = @intCast(sl); }
                r188 = @intCast(@intFromPtr(@as([*]const u8, "struct")));
                r189 = 6;
                r190 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r186))))), r187, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r188))))), r189)) @as(i64, 1) else @as(i64, 0);
                block = if (r190 != 0) 25 else 26; continue;
            },
            24 => {
                block = 21; continue;
            },
            25 => {
                r191 = locals[2];
                r192 = locals[3];
                r193 = @intCast(@intFromPtr(@as([*]const u8, "struct ")));
                r194 = 7;
                r195 = locals[0];
                r196 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r195))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r196)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r197 = @intCast(sl); }
                r199 = locals[2];
                r200 = locals[3];
                r201 = @intCast(@intFromPtr(@as([*]const u8, "struct ")));
                r202 = 7;
                r203 = locals[0];
                r204 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r203))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r204)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r205 = @intCast(sl); }
                r206 = -1;
                if (r200 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r199}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))), r200); }
                if (r202 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r201}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r201))))), r202); }
                if (r206 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r204}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r204))))), r206); }
                verve_write(1, "\n", 1);
                r198 = 0;
                block = 27; continue;
            },
            26 => {
                r207 = locals[0];
                r208 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r207))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r208)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r209 = @intCast(sl); }
                r210 = @intCast(@intFromPtr(@as([*]const u8, "field")));
                r211 = 5;
                r212 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r208))))), r209, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r210))))), r211)) @as(i64, 1) else @as(i64, 0);
                block = if (r212 != 0) 28 else 29; continue;
            },
            27 => {
                block = 24; continue;
            },
            28 => {
                r213 = locals[2];
                r214 = locals[3];
                r215 = locals[0];
                r216 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r215))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r216)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r217 = @intCast(sl); }
                r218 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r219 = 2;
                r220 = locals[0];
                r221 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r220))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r221)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r222 = @intCast(sl); }
                r224 = locals[2];
                r225 = locals[3];
                r226 = locals[0];
                r227 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r226))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r227)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r228 = @intCast(sl); }
                r229 = -1;
                r230 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r231 = 2;
                r232 = locals[0];
                r233 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r232))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r233)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r234 = @intCast(sl); }
                r235 = -1;
                if (r225 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r224}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r224))))), r225); }
                if (r229 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r227}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r227))))), r229); }
                if (r231 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r230}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r230))))), r231); }
                if (r235 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r233}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r233))))), r235); }
                verve_write(1, "\n", 1);
                r223 = 0;
                block = 30; continue;
            },
            29 => {
                r236 = locals[0];
                r237 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r236))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r237)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r238 = @intCast(sl); }
                r239 = @intCast(@intFromPtr(@as([*]const u8, "import")));
                r240 = 6;
                r241 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r237))))), r238, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r239))))), r240)) @as(i64, 1) else @as(i64, 0);
                block = if (r241 != 0) 31 else 32; continue;
            },
            30 => {
                block = 27; continue;
            },
            31 => {
                r242 = locals[2];
                r243 = locals[3];
                r244 = @intCast(@intFromPtr(@as([*]const u8, "import ")));
                r245 = 7;
                r246 = locals[0];
                r247 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r246))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r247)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r248 = @intCast(sl); }
                r250 = locals[2];
                r251 = locals[3];
                r252 = @intCast(@intFromPtr(@as([*]const u8, "import ")));
                r253 = 7;
                r254 = locals[0];
                r255 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r254))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r255)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r256 = @intCast(sl); }
                r257 = -1;
                if (r251 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r250}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r250))))), r251); }
                if (r253 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r252}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r252))))), r253); }
                if (r257 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r255}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r255))))), r257); }
                verve_write(1, "\n", 1);
                r249 = 0;
                block = 33; continue;
            },
            32 => {
                r258 = locals[0];
                r259 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r258))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r259)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r260 = @intCast(sl); }
                r261 = @intCast(@intFromPtr(@as([*]const u8, "param")));
                r262 = 5;
                r263 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r259))))), r260, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r261))))), r262)) @as(i64, 1) else @as(i64, 0);
                block = if (r263 != 0) 34 else 35; continue;
            },
            33 => {
                block = 30; continue;
            },
            34 => {
                r264 = locals[2];
                r265 = locals[3];
                r266 = locals[0];
                r267 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r266))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r267)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r268 = @intCast(sl); }
                r269 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r270 = 2;
                r271 = locals[0];
                r272 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r271))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r272)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r273 = @intCast(sl); }
                r275 = locals[2];
                r276 = locals[3];
                r277 = locals[0];
                r278 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r277))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r278)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r279 = @intCast(sl); }
                r280 = -1;
                r281 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r282 = 2;
                r283 = locals[0];
                r284 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r283))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r284)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r285 = @intCast(sl); }
                r286 = -1;
                if (r276 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r275}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r275))))), r276); }
                if (r280 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r278}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r278))))), r280); }
                if (r282 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r281}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r281))))), r282); }
                if (r286 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r284}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r284))))), r286); }
                verve_write(1, "\n", 1);
                r274 = 0;
                block = 36; continue;
            },
            35 => {
                r287 = locals[2];
                r288 = locals[3];
                r289 = locals[0];
                r290 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r289))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r290)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r291 = @intCast(sl); }
                r292 = @intCast(@intFromPtr(@as([*]const u8, " ")));
                r293 = 1;
                r294 = locals[0];
                r295 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r294))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r295)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r296 = @intCast(sl); }
                r298 = locals[2];
                r299 = locals[3];
                r300 = locals[0];
                r301 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r300))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r301)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r302 = @intCast(sl); }
                r303 = -1;
                r304 = @intCast(@intFromPtr(@as([*]const u8, " ")));
                r305 = 1;
                r306 = locals[0];
                r307 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r306))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r307)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r308 = @intCast(sl); }
                r309 = -1;
                if (r299 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r298}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r298))))), r299); }
                if (r303 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r301}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r301))))), r303); }
                if (r305 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r304}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r304))))), r305); }
                if (r309 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r307}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r307))))), r309); }
                verve_write(1, "\n", 1);
                r297 = 0;
                block = 36; continue;
            },
            36 => {
                block = 33; continue;
            },
            37 => {
                r311 = locals[5];
                r312 = 0;
                r313 = if (r311 < r312) @as(i64, 1) else @as(i64, 0);
                block = if (r313 != 0) 38 else 39; continue;
            },
            38 => {
                r314 = locals[0];
                r315 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r314))))))[3];
                r316 = locals[5];
                r317 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r315)))))).get(r316);
                locals[8] = r317;
                r318 = locals[0];
                r319 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r318))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r319)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r320 = @intCast(sl); }
                r321 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r322 = 2;
                r323 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r319))))), r320, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r321))))), r322)) @as(i64, 1) else @as(i64, 0);
                r324 = if (r323 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r324 != 0) 40 else 42; continue;
            },
            39 => {
                block = 40;
            },
            40 => {
                r325 = locals[8];
                r326 = locals[1];
                r327 = 1;
                r328 = r326 +% r327;
                r329 = verve_Printer_print_node(r325, r328);
                block = 42; continue;
            },
            41 => {
                block = 42;
            },
            42 => {
                r330 = locals[5];
                r331 = 1;
                r332 = r330 +% r331;
                locals[5] = r332;
                block = 37; continue;
            },
            else => break,
        }
    }
    return 0;
}

pub fn main() void {
    var verve_args_list = List.init();
    var proc_args = std.process.argsWithAllocator(std.heap.page_allocator) catch return;
    _ = proc_args.skip(); // skip program name
    while (proc_args.next()) |arg| {
        verve_args_list.append(@intCast(@intFromPtr(arg.ptr)));
    }
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var r4: i64 = 0;
    _ = &r4;
    var r5: i64 = 0;
    _ = &r5;
    var r6: i64 = 0;
    _ = &r6;
    var r7: i64 = 0;
    _ = &r7;
    var r8: i64 = 0;
    _ = &r8;
    var r9: i64 = 0;
    _ = &r9;
    var r10: i64 = 0;
    _ = &r10;
    var r11: i64 = 0;
    _ = &r11;
    var r12: i64 = 0;
    _ = &r12;
    var r13: i64 = 0;
    _ = &r13;
    var r14: i64 = 0;
    _ = &r14;
    var r15: i64 = 0;
    _ = &r15;
    var r16: i64 = 0;
    _ = &r16;
    var r17: i64 = 0;
    _ = &r17;
    var r18: i64 = 0;
    _ = &r18;
    var r19: i64 = 0;
    _ = &r19;
    var r20: i64 = 0;
    _ = &r20;
    var r21: i64 = 0;
    _ = &r21;
    var r22: i64 = 0;
    _ = &r22;
    var r23: i64 = 0;
    _ = &r23;
    var r24: i64 = 0;
    _ = &r24;
    var r25: i64 = 0;
    _ = &r25;
    var r26: i64 = 0;
    _ = &r26;
    var r27: i64 = 0;
    _ = &r27;
    var r28: i64 = 0;
    _ = &r28;
    var r29: i64 = 0;
    _ = &r29;
    var r30: i64 = 0;
    _ = &r30;
    var r31: i64 = 0;
    _ = &r31;
    var r32: i64 = 0;
    _ = &r32;
    var r33: i64 = 0;
    _ = &r33;
    var r34: i64 = 0;
    _ = &r34;
    var r35: i64 = 0;
    _ = &r35;
    var r36: i64 = 0;
    _ = &r36;
    var r37: i64 = 0;
    _ = &r37;
    var r38: i64 = 0;
    _ = &r38;
    var r39: i64 = 0;
    _ = &r39;
    var r40: i64 = 0;
    _ = &r40;
    var r41: i64 = 0;
    _ = &r41;
    var r42: i64 = 0;
    _ = &r42;
    var r43: i64 = 0;
    _ = &r43;
    var r44: i64 = 0;
    _ = &r44;
    var r45: i64 = 0;
    _ = &r45;
    var r46: i64 = 0;
    _ = &r46;
    var r47: i64 = 0;
    _ = &r47;
    var r48: i64 = 0;
    _ = &r48;
    var r49: i64 = 0;
    _ = &r49;
    var r50: i64 = 0;
    _ = &r50;
    var r51: i64 = 0;
    _ = &r51;
    var r52: i64 = 0;
    _ = &r52;
    var r53: i64 = 0;
    _ = &r53;
    var r54: i64 = 0;
    _ = &r54;
    var r55: i64 = 0;
    _ = &r55;
    var r56: i64 = 0;
    _ = &r56;
    var r57: i64 = 0;
    _ = &r57;
    var r58: i64 = 0;
    _ = &r58;
    var r59: i64 = 0;
    _ = &r59;
    var r60: i64 = 0;
    _ = &r60;
    var r61: i64 = 0;
    _ = &r61;
    var r62: i64 = 0;
    _ = &r62;
    var r63: i64 = 0;
    _ = &r63;
    var r64: i64 = 0;
    _ = &r64;
    var r65: i64 = 0;
    _ = &r65;
    var r66: i64 = 0;
    _ = &r66;
    var r67: i64 = 0;
    _ = &r67;
    var r68: i64 = 0;
    _ = &r68;
    var r69: i64 = 0;
    _ = &r69;
    var r70: i64 = 0;
    _ = &r70;
    var r71: i64 = 0;
    _ = &r71;
    var r72: i64 = 0;
    _ = &r72;
    var r73: i64 = 0;
    _ = &r73;
    var r74: i64 = 0;
    _ = &r74;
    var r75: i64 = 0;
    _ = &r75;
    var r76: i64 = 0;
    _ = &r76;
    var r77: i64 = 0;
    _ = &r77;
    var r78: i64 = 0;
    _ = &r78;
    var r79: i64 = 0;
    _ = &r79;
    var r80: i64 = 0;
    _ = &r80;
    var r81: i64 = 0;
    _ = &r81;
    var r82: i64 = 0;
    _ = &r82;
    var r83: i64 = 0;
    _ = &r83;
    var r84: i64 = 0;
    _ = &r84;
    var r85: i64 = 0;
    _ = &r85;
    var r86: i64 = 0;
    _ = &r86;
    var r87: i64 = 0;
    _ = &r87;
    var r88: i64 = 0;
    _ = &r88;
    var r89: i64 = 0;
    _ = &r89;
    var r90: i64 = 0;
    _ = &r90;
    var r91: i64 = 0;
    _ = &r91;
    var r92: i64 = 0;
    _ = &r92;
    var r93: i64 = 0;
    _ = &r93;
    var r94: i64 = 0;
    _ = &r94;
    var r95: i64 = 0;
    _ = &r95;
    var r96: i64 = 0;
    _ = &r96;
    var r97: i64 = 0;
    _ = &r97;
    var r98: i64 = 0;
    _ = &r98;
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = @intCast(@intFromPtr(&verve_args_list));
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0)))))).len;
                r2 = 1;
                r3 = if (r1 < r2) @as(i64, 1) else @as(i64, 0);
                block = if (r3 != 0) 1 else 3; continue;
            },
            1 => {
                r4 = @intCast(@intFromPtr(@as([*]const u8, "Usage: verve run parser.vv <file.vv>")));
                r5 = 36;
                r7 = @intCast(@intFromPtr(@as([*]const u8, "Usage: verve run parser.vv <file.vv>")));
                r8 = 36;
                if (r8 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r7}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r7))))), r8); }
                verve_write(1, "\n", 1);
                r6 = 0;
                r9 = 1;
                std.posix.exit(@intCast(@as(u64, @bitCast(r9))));
            },
            2 => {
                block = 3;
            },
            3 => {
                r10 = locals[0];
                r11 = 0;
                r12 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r10)))))).get(r11);
                locals[1] = r12;
                r13 = locals[1];
                r14 = locals[2];
                r15 = @intCast(@intFromPtr(@as([*]const u8, "r")));
                r16 = 1;
                r18 = locals[1];
                r19 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r18)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r20 = @intCast(sl); }
                r21 = @intCast(@intFromPtr(@as([*]const u8, "r")));
                r22 = 1;
                r23 = 1;
                r17 = fileOpen(r18, r20);
                locals[3] = r17;
                r24 = locals[3];
                r25 = getTag(r24);
                r26 = 0;
                r27 = if (r25 == r26) @as(i64, 1) else @as(i64, 0);
                block = if (r27 != 0) 5 else 6; continue;
            },
            4 => {
                block = 5;
            },
            5 => {
                r28 = getTagValue(r24);
                locals[4] = r28;
                r29 = locals[4];
                r30 = streamReadAll(r29);
                locals[5] = r30;
                r31 = locals[4];
                r32 = 0; // stream close (no-op)
                r33 = locals[5];
                r34 = locals[6];
                r35 = verve_Tokenizer_tokenize(r33);
                locals[7] = r35;
                r36 = @intCast(@intFromPtr(@as([*]const u8, "Tokenized: ")));
                r37 = 11;
                r38 = locals[7];
                r39 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r38)))))).len;
                r40 = @intCast(@intFromPtr(@as([*]const u8, " tokens")));
                r41 = 7;
                r43 = @intCast(@intFromPtr(@as([*]const u8, "Tokenized: ")));
                r44 = 11;
                r45 = locals[7];
                r46 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r45)))))).len;
                r47 = -1;
                r48 = @intCast(@intFromPtr(@as([*]const u8, " tokens")));
                r49 = 7;
                if (r44 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r43}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43))))), r44); }
                if (r47 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r46}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r46))))), r47); }
                if (r49 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r48}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r48))))), r49); }
                verve_write(1, "\n", 1);
                r42 = 0;
                r50 = locals[7];
                r51 = verve_Parser_parse_file(r50);
                locals[8] = r51;
                r52 = @intCast(@intFromPtr(@as([*]const u8, "Parsed: ")));
                r53 = 8;
                r54 = locals[8];
                r55 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r54)))))).len;
                r56 = @intCast(@intFromPtr(@as([*]const u8, " declarations")));
                r57 = 13;
                r59 = @intCast(@intFromPtr(@as([*]const u8, "Parsed: ")));
                r60 = 8;
                r61 = locals[8];
                r62 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r61)))))).len;
                r63 = -1;
                r64 = @intCast(@intFromPtr(@as([*]const u8, " declarations")));
                r65 = 13;
                if (r60 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r59}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r59))))), r60); }
                if (r63 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r62}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r62))))), r63); }
                if (r65 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r64}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r64))))), r65); }
                verve_write(1, "\n", 1);
                r58 = 0;
                r66 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r67 = 0;
                r69 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r70 = 0;
                if (r70 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r69}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r69))))), r70); }
                verve_write(1, "\n", 1);
                r68 = 0;
                r71 = 0;
                locals[9] = r71;
                block = 7; continue;
            },
            6 => {
                r85 = getTag(r24);
                r86 = 1;
                r87 = if (r85 == r86) @as(i64, 1) else @as(i64, 0);
                block = if (r87 != 0) 10 else 11; continue;
            },
            7 => {
                r72 = locals[9];
                r73 = locals[8];
                r74 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r73)))))).len;
                r75 = if (r72 < r74) @as(i64, 1) else @as(i64, 0);
                block = if (r75 != 0) 8 else 9; continue;
            },
            8 => {
                r76 = locals[8];
                r77 = locals[9];
                r78 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r76)))))).get(r77);
                r79 = 0;
                r80 = verve_Printer_print_node(r78, r79);
                r81 = locals[9];
                r82 = 1;
                r83 = r81 +% r82;
                locals[9] = r83;
                block = 7; continue;
            },
            9 => {
                r84 = 0;
                std.posix.exit(@intCast(@as(u64, @bitCast(r84))));
            },
            10 => {
                r88 = getTagValue(r24);
                locals[10] = r88;
                r89 = @intCast(@intFromPtr(@as([*]const u8, "Error: could not open ")));
                r90 = 22;
                r91 = locals[1];
                r92 = locals[2];
                r94 = @intCast(@intFromPtr(@as([*]const u8, "Error: could not open ")));
                r95 = 22;
                r96 = locals[1];
                r97 = locals[2];
                if (r95 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r94}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r94))))), r95); }
                if (r97 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r96}) catch "?"; verve_write(1, s.ptr, @intCast(s.len)); } else { verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r96))))), r97); }
                verve_write(1, "\n", 1);
                r93 = 0;
                r98 = 1;
                std.posix.exit(@intCast(@as(u64, @bitCast(r98))));
            },
            11 => {
                block = 4; continue;
            },
            else => break,
        }
    }
}
