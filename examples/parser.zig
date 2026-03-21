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
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r2)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r3 = @intCast(sl); }
                locals[3] = r3;
                block = 1; continue;
            },
            1 => {
                r4 = locals[2];
                r5 = locals[3];
                r6 = if (r4 < r5) @as(i64, 1) else @as(i64, 0);
                block = if (r6 != 0) 2 else 3; continue;
            },
            2 => {
                r7 = locals[0];
                r8 = locals[2];
                r9 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r7))))))[
@intCast(@as(u64, @bitCast(r8)))];
                locals[4] = r9;
                r10 = locals[4];
                r11 = 32;
                r12 = if (r10 == r11) @as(i64, 1) else @as(i64, 0);
                block = if (r12 != 0) 4 else 6; continue;
            },
            3 => {
                r505 = locals[1];
                return r505;
            },
            4 => {
                r13 = locals[2];
                r14 = 1;
                r15 = r13 +% r14;
                locals[2] = r15;
                block = 1; continue;
            },
            5 => {
                block = 6;
            },
            6 => {
                r16 = locals[4];
                r17 = 9;
                r18 = if (r16 == r17) @as(i64, 1) else @as(i64, 0);
                block = if (r18 != 0) 7 else 9; continue;
            },
            7 => {
                r19 = locals[2];
                r20 = 1;
                r21 = r19 +% r20;
                locals[2] = r21;
                block = 1; continue;
            },
            8 => {
                block = 9;
            },
            9 => {
                r22 = locals[4];
                r23 = 10;
                r24 = if (r22 == r23) @as(i64, 1) else @as(i64, 0);
                block = if (r24 != 0) 10 else 12; continue;
            },
            10 => {
                r25 = locals[2];
                r26 = 1;
                r27 = r25 +% r26;
                locals[2] = r27;
                block = 1; continue;
            },
            11 => {
                block = 12;
            },
            12 => {
                r28 = locals[4];
                r29 = 13;
                r30 = if (r28 == r29) @as(i64, 1) else @as(i64, 0);
                block = if (r30 != 0) 13 else 15; continue;
            },
            13 => {
                r31 = locals[2];
                r32 = 1;
                r33 = r31 +% r32;
                locals[2] = r33;
                block = 1; continue;
            },
            14 => {
                block = 15;
            },
            15 => {
                r34 = locals[4];
                r35 = 47;
                r36 = if (r34 == r35) @as(i64, 1) else @as(i64, 0);
                block = if (r36 != 0) 16 else 18; continue;
            },
            16 => {
                r37 = locals[2];
                r38 = 1;
                r39 = r37 +% r38;
                r40 = locals[3];
                r41 = if (r39 < r40) @as(i64, 1) else @as(i64, 0);
                block = if (r41 != 0) 19 else 21; continue;
            },
            17 => {
                block = 18;
            },
            18 => {
                r95 = locals[4];
                r96 = 123;
                r97 = if (r95 == r96) @as(i64, 1) else @as(i64, 0);
                block = if (r97 != 0) 40 else 42; continue;
            },
            19 => {
                r42 = locals[0];
                r43 = locals[2];
                r44 = 1;
                r45 = r43 +% r44;
                r46 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r42))))))[
@intCast(@as(u64, @bitCast(r45)))];
                r47 = 47;
                r48 = if (r46 == r47) @as(i64, 1) else @as(i64, 0);
                block = if (r48 != 0) 22 else 24; continue;
            },
            20 => {
                block = 21;
            },
            21 => {
                r85 = locals[1];
                r86 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r87 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r88 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r86))))))[0] = r87;
                r89 = @intCast(@intFromPtr(@as([*]const u8, "/")));
                r90 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r86))))))[1] = r89;
                r91 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r86))))))[2] = r91;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r85)))))).append(r86);
                r92 = locals[2];
                r93 = 1;
                r94 = r92 +% r93;
                locals[2] = r94;
                block = 1; continue;
            },
            22 => {
                r49 = 0;
                locals[5] = r49;
                r50 = locals[2];
                r51 = 2;
                r52 = r50 +% r51;
                r53 = locals[3];
                r54 = if (r52 < r53) @as(i64, 1) else @as(i64, 0);
                block = if (r54 != 0) 25 else 27; continue;
            },
            23 => {
                block = 24;
            },
            24 => {
                block = 21; continue;
            },
            25 => {
                r55 = locals[0];
                r56 = locals[2];
                r57 = 2;
                r58 = r56 +% r57;
                r59 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r55))))))[
@intCast(@as(u64, @bitCast(r58)))];
                r60 = 47;
                r61 = if (r59 == r60) @as(i64, 1) else @as(i64, 0);
                block = if (r61 != 0) 28 else 30; continue;
            },
            26 => {
                block = 27;
            },
            27 => {
                r63 = locals[2];
                locals[6] = r63;
                block = 31; continue;
            },
            28 => {
                r62 = 1;
                locals[5] = r62;
                block = 30; continue;
            },
            29 => {
                block = 30;
            },
            30 => {
                block = 27; continue;
            },
            31 => {
                r64 = locals[2];
                r65 = locals[3];
                r66 = if (r64 < r65) @as(i64, 1) else @as(i64, 0);
                block = if (r66 != 0) 32 else 33; continue;
            },
            32 => {
                r67 = locals[0];
                r68 = locals[2];
                r69 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r67))))))[
@intCast(@as(u64, @bitCast(r68)))];
                r70 = 10;
                r71 = if (r69 == r70) @as(i64, 1) else @as(i64, 0);
                block = if (r71 != 0) 34 else 36; continue;
            },
            33 => {
                r75 = locals[5];
                block = if (r75 != 0) 37 else 39; continue;
            },
            34 => {
                block = 33; continue;
            },
            35 => {
                block = 36;
            },
            36 => {
                r72 = locals[2];
                r73 = 1;
                r74 = r72 +% r73;
                locals[2] = r74;
                block = 31; continue;
            },
            37 => {
                r76 = locals[1];
                r77 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r78 = @intCast(@intFromPtr(@as([*]const u8, "doc")));
                r79 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r77))))))[0] = r78;
                r80 = locals[0];
                r81 = locals[6];
                r82 = locals[2];
                r83 = r80 + r81;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r77))))))[1] = r83;
                r84 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r77))))))[2] = r84;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r76)))))).append(r77);
                block = 39; continue;
            },
            38 => {
                block = 39;
            },
            39 => {
                block = 1; continue;
            },
            40 => {
                r98 = locals[1];
                r99 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r100 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r101 = 6;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r99))))))[0] = r100;
                r102 = @intCast(@intFromPtr(@as([*]const u8, "{")));
                r103 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r99))))))[1] = r102;
                r104 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r99))))))[2] = r104;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r98)))))).append(r99);
                r105 = locals[2];
                r106 = 1;
                r107 = r105 +% r106;
                locals[2] = r107;
                block = 1; continue;
            },
            41 => {
                block = 42;
            },
            42 => {
                r108 = locals[4];
                r109 = 125;
                r110 = if (r108 == r109) @as(i64, 1) else @as(i64, 0);
                block = if (r110 != 0) 43 else 45; continue;
            },
            43 => {
                r111 = locals[1];
                r112 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r113 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r114 = 6;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r112))))))[0] = r113;
                r115 = @intCast(@intFromPtr(@as([*]const u8, "}")));
                r116 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r112))))))[1] = r115;
                r117 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r112))))))[2] = r117;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r111)))))).append(r112);
                r118 = locals[2];
                r119 = 1;
                r120 = r118 +% r119;
                locals[2] = r120;
                block = 1; continue;
            },
            44 => {
                block = 45;
            },
            45 => {
                r121 = locals[4];
                r122 = 45;
                r123 = if (r121 == r122) @as(i64, 1) else @as(i64, 0);
                block = if (r123 != 0) 46 else 48; continue;
            },
            46 => {
                r124 = locals[2];
                r125 = 1;
                r126 = r124 +% r125;
                r127 = locals[3];
                r128 = if (r126 < r127) @as(i64, 1) else @as(i64, 0);
                block = if (r128 != 0) 49 else 51; continue;
            },
            47 => {
                block = 48;
            },
            48 => {
                r156 = locals[4];
                r157 = 61;
                r158 = if (r156 == r157) @as(i64, 1) else @as(i64, 0);
                block = if (r158 != 0) 55 else 57; continue;
            },
            49 => {
                r129 = locals[0];
                r130 = locals[2];
                r131 = 1;
                r132 = r130 +% r131;
                r133 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r129))))))[
@intCast(@as(u64, @bitCast(r132)))];
                r134 = 62;
                r135 = if (r133 == r134) @as(i64, 1) else @as(i64, 0);
                block = if (r135 != 0) 52 else 54; continue;
            },
            50 => {
                block = 51;
            },
            51 => {
                r146 = locals[1];
                r147 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r148 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r149 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r147))))))[0] = r148;
                r150 = @intCast(@intFromPtr(@as([*]const u8, "-")));
                r151 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r147))))))[1] = r150;
                r152 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r147))))))[2] = r152;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r146)))))).append(r147);
                r153 = locals[2];
                r154 = 1;
                r155 = r153 +% r154;
                locals[2] = r155;
                block = 1; continue;
            },
            52 => {
                r136 = locals[1];
                r137 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r138 = @intCast(@intFromPtr(@as([*]const u8, "arrow")));
                r139 = 5;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r137))))))[0] = r138;
                r140 = @intCast(@intFromPtr(@as([*]const u8, "->")));
                r141 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r137))))))[1] = r140;
                r142 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r137))))))[2] = r142;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r136)))))).append(r137);
                r143 = locals[2];
                r144 = 2;
                r145 = r143 +% r144;
                locals[2] = r145;
                block = 1; continue;
            },
            53 => {
                block = 54;
            },
            54 => {
                block = 51; continue;
            },
            55 => {
                r159 = locals[2];
                r160 = 1;
                r161 = r159 +% r160;
                r162 = locals[3];
                r163 = if (r161 < r162) @as(i64, 1) else @as(i64, 0);
                block = if (r163 != 0) 58 else 60; continue;
            },
            56 => {
                block = 57;
            },
            57 => {
                r208 = locals[4];
                r209 = 60;
                r210 = if (r208 == r209) @as(i64, 1) else @as(i64, 0);
                block = if (r210 != 0) 67 else 69; continue;
            },
            58 => {
                r164 = locals[0];
                r165 = locals[2];
                r166 = 1;
                r167 = r165 +% r166;
                r168 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r164))))))[
@intCast(@as(u64, @bitCast(r167)))];
                r169 = 62;
                r170 = if (r168 == r169) @as(i64, 1) else @as(i64, 0);
                block = if (r170 != 0) 61 else 63; continue;
            },
            59 => {
                block = 60;
            },
            60 => {
                r198 = locals[1];
                r199 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r200 = @intCast(@intFromPtr(@as([*]const u8, "eq")));
                r201 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))))[0] = r200;
                r202 = @intCast(@intFromPtr(@as([*]const u8, "=")));
                r203 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))))[1] = r202;
                r204 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))))[2] = r204;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r198)))))).append(r199);
                r205 = locals[2];
                r206 = 1;
                r207 = r205 +% r206;
                locals[2] = r207;
                block = 1; continue;
            },
            61 => {
                r171 = locals[1];
                r172 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r173 = @intCast(@intFromPtr(@as([*]const u8, "fatarrow")));
                r174 = 8;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r172))))))[0] = r173;
                r175 = @intCast(@intFromPtr(@as([*]const u8, "=>")));
                r176 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r172))))))[1] = r175;
                r177 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r172))))))[2] = r177;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r171)))))).append(r172);
                r178 = locals[2];
                r179 = 2;
                r180 = r178 +% r179;
                locals[2] = r180;
                block = 1; continue;
            },
            62 => {
                block = 63;
            },
            63 => {
                r181 = locals[0];
                r182 = locals[2];
                r183 = 1;
                r184 = r182 +% r183;
                r185 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))))[
@intCast(@as(u64, @bitCast(r184)))];
                r186 = 61;
                r187 = if (r185 == r186) @as(i64, 1) else @as(i64, 0);
                block = if (r187 != 0) 64 else 66; continue;
            },
            64 => {
                r188 = locals[1];
                r189 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r190 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r191 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r189))))))[0] = r190;
                r192 = @intCast(@intFromPtr(@as([*]const u8, "==")));
                r193 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r189))))))[1] = r192;
                r194 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r189))))))[2] = r194;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r188)))))).append(r189);
                r195 = locals[2];
                r196 = 2;
                r197 = r195 +% r196;
                locals[2] = r197;
                block = 1; continue;
            },
            65 => {
                block = 66;
            },
            66 => {
                block = 60; continue;
            },
            67 => {
                r211 = locals[2];
                r212 = 1;
                r213 = r211 +% r212;
                r214 = locals[3];
                r215 = if (r213 < r214) @as(i64, 1) else @as(i64, 0);
                block = if (r215 != 0) 70 else 72; continue;
            },
            68 => {
                block = 69;
            },
            69 => {
                r243 = locals[4];
                r244 = 62;
                r245 = if (r243 == r244) @as(i64, 1) else @as(i64, 0);
                block = if (r245 != 0) 76 else 78; continue;
            },
            70 => {
                r216 = locals[0];
                r217 = locals[2];
                r218 = 1;
                r219 = r217 +% r218;
                r220 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r216))))))[
@intCast(@as(u64, @bitCast(r219)))];
                r221 = 61;
                r222 = if (r220 == r221) @as(i64, 1) else @as(i64, 0);
                block = if (r222 != 0) 73 else 75; continue;
            },
            71 => {
                block = 72;
            },
            72 => {
                r233 = locals[1];
                r234 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r235 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r236 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r234))))))[0] = r235;
                r237 = @intCast(@intFromPtr(@as([*]const u8, "<")));
                r238 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r234))))))[1] = r237;
                r239 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r234))))))[2] = r239;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r233)))))).append(r234);
                r240 = locals[2];
                r241 = 1;
                r242 = r240 +% r241;
                locals[2] = r242;
                block = 1; continue;
            },
            73 => {
                r223 = locals[1];
                r224 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r225 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r226 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r224))))))[0] = r225;
                r227 = @intCast(@intFromPtr(@as([*]const u8, "<=")));
                r228 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r224))))))[1] = r227;
                r229 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r224))))))[2] = r229;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r223)))))).append(r224);
                r230 = locals[2];
                r231 = 2;
                r232 = r230 +% r231;
                locals[2] = r232;
                block = 1; continue;
            },
            74 => {
                block = 75;
            },
            75 => {
                block = 72; continue;
            },
            76 => {
                r246 = locals[2];
                r247 = 1;
                r248 = r246 +% r247;
                r249 = locals[3];
                r250 = if (r248 < r249) @as(i64, 1) else @as(i64, 0);
                block = if (r250 != 0) 79 else 81; continue;
            },
            77 => {
                block = 78;
            },
            78 => {
                r278 = locals[4];
                r279 = 33;
                r280 = if (r278 == r279) @as(i64, 1) else @as(i64, 0);
                block = if (r280 != 0) 85 else 87; continue;
            },
            79 => {
                r251 = locals[0];
                r252 = locals[2];
                r253 = 1;
                r254 = r252 +% r253;
                r255 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r251))))))[
@intCast(@as(u64, @bitCast(r254)))];
                r256 = 61;
                r257 = if (r255 == r256) @as(i64, 1) else @as(i64, 0);
                block = if (r257 != 0) 82 else 84; continue;
            },
            80 => {
                block = 81;
            },
            81 => {
                r268 = locals[1];
                r269 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r270 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r271 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r269))))))[0] = r270;
                r272 = @intCast(@intFromPtr(@as([*]const u8, ">")));
                r273 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r269))))))[1] = r272;
                r274 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r269))))))[2] = r274;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r268)))))).append(r269);
                r275 = locals[2];
                r276 = 1;
                r277 = r275 +% r276;
                locals[2] = r277;
                block = 1; continue;
            },
            82 => {
                r258 = locals[1];
                r259 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r260 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r261 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r259))))))[0] = r260;
                r262 = @intCast(@intFromPtr(@as([*]const u8, ">=")));
                r263 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r259))))))[1] = r262;
                r264 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r259))))))[2] = r264;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r258)))))).append(r259);
                r265 = locals[2];
                r266 = 2;
                r267 = r265 +% r266;
                locals[2] = r267;
                block = 1; continue;
            },
            83 => {
                block = 84;
            },
            84 => {
                block = 81; continue;
            },
            85 => {
                r281 = locals[2];
                r282 = 1;
                r283 = r281 +% r282;
                r284 = locals[3];
                r285 = if (r283 < r284) @as(i64, 1) else @as(i64, 0);
                block = if (r285 != 0) 88 else 90; continue;
            },
            86 => {
                block = 87;
            },
            87 => {
                r313 = locals[4];
                r314 = verve_Tokenizer_single_char_kind(r313);
                locals[7] = r314;
                r315 = locals[7];
                r316 = @intCast(@intFromPtr(@as([*]const u8, "none")));
                r317 = 4;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r315)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r318 = @intCast(sl); }
                r319 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r315))))), r318, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r316))))), r317)) @as(i64, 1) else @as(i64, 0);
                r320 = if (r319 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r320 != 0) 94 else 96; continue;
            },
            88 => {
                r286 = locals[0];
                r287 = locals[2];
                r288 = 1;
                r289 = r287 +% r288;
                r290 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r286))))))[
@intCast(@as(u64, @bitCast(r289)))];
                r291 = 61;
                r292 = if (r290 == r291) @as(i64, 1) else @as(i64, 0);
                block = if (r292 != 0) 91 else 93; continue;
            },
            89 => {
                block = 90;
            },
            90 => {
                r303 = locals[1];
                r304 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r305 = @intCast(@intFromPtr(@as([*]const u8, "bang")));
                r306 = 4;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r304))))))[0] = r305;
                r307 = @intCast(@intFromPtr(@as([*]const u8, "!")));
                r308 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r304))))))[1] = r307;
                r309 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r304))))))[2] = r309;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r303)))))).append(r304);
                r310 = locals[2];
                r311 = 1;
                r312 = r310 +% r311;
                locals[2] = r312;
                block = 1; continue;
            },
            91 => {
                r293 = locals[1];
                r294 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r295 = @intCast(@intFromPtr(@as([*]const u8, "op")));
                r296 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r294))))))[0] = r295;
                r297 = @intCast(@intFromPtr(@as([*]const u8, "!=")));
                r298 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r294))))))[1] = r297;
                r299 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r294))))))[2] = r299;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r293)))))).append(r294);
                r300 = locals[2];
                r301 = 2;
                r302 = r300 +% r301;
                locals[2] = r302;
                block = 1; continue;
            },
            92 => {
                block = 93;
            },
            93 => {
                block = 90; continue;
            },
            94 => {
                r321 = locals[1];
                r322 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r323 = locals[7];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r322))))))[0] = r323;
                r324 = locals[0];
                r325 = locals[2];
                r326 = locals[2];
                r327 = 1;
                r328 = r326 +% r327;
                r329 = r324 + r325;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r322))))))[1] = r329;
                r330 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r322))))))[2] = r330;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r321)))))).append(r322);
                r331 = locals[2];
                r332 = 1;
                r333 = r331 +% r332;
                locals[2] = r333;
                block = 1; continue;
            },
            95 => {
                block = 96;
            },
            96 => {
                r334 = locals[4];
                r335 = 34;
                r336 = if (r334 == r335) @as(i64, 1) else @as(i64, 0);
                block = if (r336 != 0) 97 else 99; continue;
            },
            97 => {
                r337 = locals[2];
                locals[6] = r337;
                r338 = locals[2];
                r339 = 1;
                r340 = r338 +% r339;
                locals[2] = r340;
                block = 100; continue;
            },
            98 => {
                block = 99;
            },
            99 => {
                r371 = locals[4];
                r372 = 58;
                r373 = if (r371 == r372) @as(i64, 1) else @as(i64, 0);
                block = if (r373 != 0) 109 else 111; continue;
            },
            100 => {
                r341 = locals[2];
                r342 = locals[3];
                r343 = if (r341 < r342) @as(i64, 1) else @as(i64, 0);
                block = if (r343 != 0) 101 else 102; continue;
            },
            101 => {
                r344 = locals[0];
                r345 = locals[2];
                r346 = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r344))))))[
@intCast(@as(u64, @bitCast(r345)))];
                locals[8] = r346;
                r347 = locals[8];
                r348 = 92;
                r349 = if (r347 == r348) @as(i64, 1) else @as(i64, 0);
                block = if (r349 != 0) 103 else 105; continue;
            },
            102 => {
                r359 = locals[2];
                r360 = 1;
                r361 = r359 +% r360;
                locals[2] = r361;
                r362 = locals[1];
                r363 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r364 = @intCast(@intFromPtr(@as([*]const u8, "string")));
                r365 = 6;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r363))))))[0] = r364;
                r366 = locals[0];
                r367 = locals[6];
                r368 = locals[2];
                r369 = r366 + r367;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r363))))))[1] = r369;
                r370 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r363))))))[2] = r370;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r362)))))).append(r363);
                block = 1; continue;
            },
            103 => {
                r350 = locals[2];
                r351 = 2;
                r352 = r350 +% r351;
                locals[2] = r352;
                block = 100; continue;
            },
            104 => {
                block = 105;
            },
            105 => {
                r353 = locals[8];
                r354 = 34;
                r355 = if (r353 == r354) @as(i64, 1) else @as(i64, 0);
                block = if (r355 != 0) 106 else 108; continue;
            },
            106 => {
                block = 102; continue;
            },
            107 => {
                block = 108;
            },
            108 => {
                r356 = locals[2];
                r357 = 1;
                r358 = r356 +% r357;
                locals[2] = r358;
                block = 100; continue;
            },
            109 => {
                r374 = locals[2];
                r375 = 1;
                r376 = r374 +% r375;
                r377 = locals[3];
                r378 = if (r376 < r377) @as(i64, 1) else @as(i64, 0);
                block = if (r378 != 0) 112 else 114; continue;
            },
            110 => {
                block = 111;
            },
            111 => {
                r430 = locals[0];
                r431 = locals[2];
                r432 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r430)))))) + @as(usize, @intCast(@as(u64, @bitCast(r431))))));
                r433 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r432))))))[0]; r434 = if (b >= '0' and b <= '9') @as(i64, 1) else @as(i64, 0); }
                block = if (r434 != 0) 127 else 129; continue;
            },
            112 => {
                r379 = locals[0];
                r380 = locals[2];
                r381 = 1;
                r382 = r380 +% r381;
                r383 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r379)))))) + @as(usize, @intCast(@as(u64, @bitCast(r382))))));
                r384 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r383))))))[0]; r385 = if ((b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r385 != 0) 115 else 117; continue;
            },
            113 => {
                block = 114;
            },
            114 => {
                r420 = locals[1];
                r421 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r422 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r423 = 5;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r421))))))[0] = r422;
                r424 = @intCast(@intFromPtr(@as([*]const u8, ":")));
                r425 = 1;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r421))))))[1] = r424;
                r426 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r421))))))[2] = r426;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r420)))))).append(r421);
                r427 = locals[2];
                r428 = 1;
                r429 = r427 +% r428;
                locals[2] = r429;
                block = 1; continue;
            },
            115 => {
                r386 = locals[2];
                locals[6] = r386;
                r387 = locals[2];
                r388 = 1;
                r389 = r387 +% r388;
                locals[2] = r389;
                block = 118; continue;
            },
            116 => {
                block = 117;
            },
            117 => {
                block = 114; continue;
            },
            118 => {
                r390 = locals[2];
                r391 = locals[3];
                r392 = if (r390 < r391) @as(i64, 1) else @as(i64, 0);
                block = if (r392 != 0) 119 else 120; continue;
            },
            119 => {
                r393 = locals[0];
                r394 = locals[2];
                r395 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r393)))))) + @as(usize, @intCast(@as(u64, @bitCast(r394))))));
                r396 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r395))))))[0]; r397 = if ((b >= '0' and b <= '9') or (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r397 != 0) 121 else 122; continue;
            },
            120 => {
                r411 = locals[1];
                r412 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r413 = @intCast(@intFromPtr(@as([*]const u8, "tag")));
                r414 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r412))))))[0] = r413;
                r415 = locals[0];
                r416 = locals[6];
                r417 = locals[2];
                r418 = r415 + r416;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r412))))))[1] = r418;
                r419 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r412))))))[2] = r419;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r411)))))).append(r412);
                block = 1; continue;
            },
            121 => {
                r398 = locals[2];
                r399 = 1;
                r400 = r398 +% r399;
                locals[2] = r400;
                block = 123; continue;
            },
            122 => {
                r401 = locals[0];
                r402 = locals[2];
                r403 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r401)))))) + @as(usize, @intCast(@as(u64, @bitCast(r402))))));
                r404 = 1;
                r405 = @intCast(@intFromPtr(@as([*]const u8, "_")));
                r406 = 1;
                r407 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r403))))), r404, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r405))))), r406)) @as(i64, 1) else @as(i64, 0);
                block = if (r407 != 0) 124 else 125; continue;
            },
            123 => {
                block = 118; continue;
            },
            124 => {
                r408 = locals[2];
                r409 = 1;
                r410 = r408 +% r409;
                locals[2] = r410;
                block = 126; continue;
            },
            125 => {
                block = 120; continue;
            },
            126 => {
                block = 123; continue;
            },
            127 => {
                r435 = locals[2];
                locals[6] = r435;
                block = 130; continue;
            },
            128 => {
                block = 129;
            },
            129 => {
                r457 = locals[0];
                r458 = locals[2];
                r459 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r457)))))) + @as(usize, @intCast(@as(u64, @bitCast(r458))))));
                r460 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r459))))))[0]; r461 = if ((b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r461 != 0) 136 else 138; continue;
            },
            130 => {
                r436 = locals[2];
                r437 = locals[3];
                r438 = if (r436 < r437) @as(i64, 1) else @as(i64, 0);
                block = if (r438 != 0) 131 else 132; continue;
            },
            131 => {
                r439 = locals[0];
                r440 = locals[2];
                r441 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r439)))))) + @as(usize, @intCast(@as(u64, @bitCast(r440))))));
                r442 = 1;
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r441))))))[0]; r443 = if (b >= '0' and b <= '9') @as(i64, 1) else @as(i64, 0); }
                r444 = if (r443 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r444 != 0) 133 else 135; continue;
            },
            132 => {
                r448 = locals[1];
                r449 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r450 = @intCast(@intFromPtr(@as([*]const u8, "int")));
                r451 = 3;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r449))))))[0] = r450;
                r452 = locals[0];
                r453 = locals[6];
                r454 = locals[2];
                r455 = r452 + r453;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r449))))))[1] = r455;
                r456 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r449))))))[2] = r456;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r448)))))).append(r449);
                block = 1; continue;
            },
            133 => {
                block = 132; continue;
            },
            134 => {
                block = 135;
            },
            135 => {
                r445 = locals[2];
                r446 = 1;
                r447 = r445 +% r446;
                locals[2] = r447;
                block = 130; continue;
            },
            136 => {
                r462 = locals[2];
                locals[6] = r462;
                block = 139; continue;
            },
            137 => {
                block = 138;
            },
            138 => {
                r502 = locals[2];
                r503 = 1;
                r504 = r502 +% r503;
                locals[2] = r504;
                block = 1; continue;
            },
            139 => {
                r463 = locals[2];
                r464 = locals[3];
                r465 = if (r463 < r464) @as(i64, 1) else @as(i64, 0);
                block = if (r465 != 0) 140 else 141; continue;
            },
            140 => {
                r466 = locals[0];
                r467 = locals[2];
                r468 = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r466)))))) + @as(usize, @intCast(@as(u64, @bitCast(r467))))));
                r469 = 1;
                locals[9] = r468;
                locals[10] = r469;
                r470 = locals[9];
                { const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r470))))))[0]; r471 = if ((b >= '0' and b <= '9') or (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }
                block = if (r471 != 0) 142 else 143; continue;
            },
            141 => {
                r483 = locals[0];
                r484 = locals[6];
                r485 = locals[2];
                r486 = r483 + r484;
                locals[11] = r486;
                r487 = locals[12];
                r488 = locals[11];
                { const list = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r487)))))); var found: i64 = 0; var si: i64 = 0; while (si < list.len) : (si += 1) { if (list.get(si) == r488) { found = 1; break; } } r489 = found; }
                block = if (r489 != 0) 148 else 149; continue;
            },
            142 => {
                r472 = locals[2];
                r473 = 1;
                r474 = r472 +% r473;
                locals[2] = r474;
                block = 144; continue;
            },
            143 => {
                r475 = locals[9];
                r476 = @intCast(@intFromPtr(@as([*]const u8, "_")));
                r477 = 1;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r475)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r478 = @intCast(sl); }
                r479 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r475))))), r478, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r476))))), r477)) @as(i64, 1) else @as(i64, 0);
                block = if (r479 != 0) 145 else 146; continue;
            },
            144 => {
                block = 139; continue;
            },
            145 => {
                r480 = locals[2];
                r481 = 1;
                r482 = r480 +% r481;
                locals[2] = r482;
                block = 147; continue;
            },
            146 => {
                block = 141; continue;
            },
            147 => {
                block = 144; continue;
            },
            148 => {
                r490 = locals[1];
                r491 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r492 = @intCast(@intFromPtr(@as([*]const u8, "kw")));
                r493 = 2;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r491))))))[0] = r492;
                r494 = locals[11];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r491))))))[1] = r494;
                r495 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r491))))))[2] = r495;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r490)))))).append(r491);
                block = 150; continue;
            },
            149 => {
                r496 = locals[1];
                r497 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 3) catch &.{}).ptr));
                r498 = @intCast(@intFromPtr(@as([*]const u8, "ident")));
                r499 = 5;
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r497))))))[0] = r498;
                r500 = locals[11];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r497))))))[1] = r500;
                r501 = locals[6];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r497))))))[2] = r501;
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r496)))))).append(r497);
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
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[0] = r1;
                r2 = locals[1];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[1] = r2;
                r3 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[2] = r3;
                var list_4 = List.init();
                r4 = @intCast(@intFromPtr(&list_4));
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[3] = r4;
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
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[0] = r1;
                r2 = locals[1];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[1] = r2;
                r3 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[2] = r3;
                r4 = locals[3];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r0))))))[3] = r4;
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
                r5 = locals[2];
                r6 = if (r4 != r5) @as(i64, 1) else @as(i64, 0);
                block = if (r6 != 0) 1 else 3; continue;
            },
            1 => {
                r7 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r8 = 19;
                r9 = locals[3];
                r10 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r9))))))[2];
                r11 = @intCast(@intFromPtr(@as([*]const u8, ": expected ")));
                r12 = 11;
                r13 = locals[2];
                r14 = @intCast(@intFromPtr(@as([*]const u8, " but got ")));
                r15 = 9;
                r16 = locals[3];
                r17 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r16))))))[0];
                r18 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r19 = 2;
                r20 = locals[3];
                r21 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r20))))))[1];
                r22 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r23 = 1;
                r25 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r26 = 19;
                r27 = locals[3];
                r28 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r27))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r28)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r29 = @intCast(sl); }
                r30 = @intCast(@intFromPtr(@as([*]const u8, ": expected ")));
                r31 = 11;
                r32 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r32)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r33 = @intCast(sl); }
                r34 = @intCast(@intFromPtr(@as([*]const u8, " but got ")));
                r35 = 9;
                r36 = locals[3];
                r37 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r38 = @intCast(sl); }
                r39 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r40 = 2;
                r41 = locals[3];
                r42 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r41))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r42)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r43 = @intCast(sl); }
                r44 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r45 = 1;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25))))), r26);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r28))))), r29);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r30))))), r31);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r32))))), r33);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r34))))), r35);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37))))), r38);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r39))))), r40);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r42))))), r43);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r44))))), r45);
                verve_write(1, "\n", 1);
                r24 = 0;
                r46 = locals[1];
                return r46;
            },
            2 => {
                block = 3;
            },
            3 => {
                r47 = locals[1];
                r48 = 1;
                r49 = r47 +% r48;
                return r49;
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
                r5 = @intCast(@intFromPtr(@as([*]const u8, "kw")));
                r6 = 2;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r7 = @intCast(sl); }
                r8 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))), r7, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r5))))), r6)) @as(i64, 1) else @as(i64, 0);
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
                r17 = @intCast(@intFromPtr(@as([*]const u8, "' but got ")));
                r18 = 10;
                r19 = locals[3];
                r20 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r19))))))[0];
                r22 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r23 = 19;
                r24 = locals[3];
                r25 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r24))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r26 = @intCast(sl); }
                r27 = @intCast(@intFromPtr(@as([*]const u8, ": expected keyword '")));
                r28 = 20;
                r29 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r29)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r30 = @intCast(sl); }
                r31 = @intCast(@intFromPtr(@as([*]const u8, "' but got ")));
                r32 = 10;
                r33 = locals[3];
                r34 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r34)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r35 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r22))))), r23);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25))))), r26);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r27))))), r28);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r29))))), r30);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r31))))), r32);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r34))))), r35);
                verve_write(1, "\n", 1);
                r21 = 0;
                r36 = locals[1];
                return r36;
            },
            2 => {
                block = 3;
            },
            3 => {
                r37 = locals[3];
                r38 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37))))))[1];
                r39 = locals[2];
                r40 = if (r38 != r39) @as(i64, 1) else @as(i64, 0);
                block = if (r40 != 0) 4 else 6; continue;
            },
            4 => {
                r41 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r42 = 19;
                r43 = locals[3];
                r44 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43))))))[2];
                r45 = @intCast(@intFromPtr(@as([*]const u8, ": expected '")));
                r46 = 12;
                r47 = locals[2];
                r48 = @intCast(@intFromPtr(@as([*]const u8, "' but got '")));
                r49 = 11;
                r50 = locals[3];
                r51 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r50))))))[1];
                r52 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r53 = 1;
                r55 = @intCast(@intFromPtr(@as([*]const u8, "Parse error at pos ")));
                r56 = 19;
                r57 = locals[3];
                r58 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r57))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r58)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r59 = @intCast(sl); }
                r60 = @intCast(@intFromPtr(@as([*]const u8, ": expected '")));
                r61 = 12;
                r62 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r62)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r63 = @intCast(sl); }
                r64 = @intCast(@intFromPtr(@as([*]const u8, "' but got '")));
                r65 = 11;
                r66 = locals[3];
                r67 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r66))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r67)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r68 = @intCast(sl); }
                r69 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r70 = 1;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r55))))), r56);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r58))))), r59);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r60))))), r61);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r62))))), r63);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r64))))), r65);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r67))))), r68);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r69))))), r70);
                verve_write(1, "\n", 1);
                r54 = 0;
                r71 = locals[1];
                return r71;
            },
            5 => {
                block = 6;
            },
            6 => {
                r72 = locals[1];
                r73 = 1;
                r74 = r72 +% r73;
                return r74;
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
                r2 = if (r0 == r1) @as(i64, 1) else @as(i64, 0);
                return r2;
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
                r5 = @intCast(@intFromPtr(@as([*]const u8, "kw")));
                r6 = 2;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r7 = @intCast(sl); }
                r8 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4))))), r7, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r5))))), r6)) @as(i64, 1) else @as(i64, 0);
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
                r13 = locals[2];
                r14 = if (r12 == r13) @as(i64, 1) else @as(i64, 0);
                return r14;
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
                r11 = @intCast(@intFromPtr(@as([*]const u8, "doc")));
                r12 = 3;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r10)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r13 = @intCast(sl); }
                r14 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r10))))), r13, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r11))))), r12)) @as(i64, 1) else @as(i64, 0);
                block = if (r14 != 0) 4 else 6; continue;
            },
            3 => {
                r166 = locals[1];
                return r166;
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
                r55 = locals[0];
                r56 = locals[2];
                r57 = @intCast(@intFromPtr(@as([*]const u8, "struct")));
                r58 = 6;
                r59 = verve_Parser_is_kw(r55, r56, r57);
                block = if (r59 != 0) 16 else 17; continue;
            },
            12 => {
                block = 1; continue;
            },
            13 => {
                r42 = @intCast(@intFromPtr(@as([*]const u8, "module_exported")));
                r43 = 15;
                r44 = locals[6];
                r45 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r44))))))[1];
                r46 = locals[6];
                r47 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r46))))))[2];
                r48 = locals[6];
                r49 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r48))))))[3];
                r50 = verve_Parser_node_with(r42, r45, r47, r49);
                locals[6] = r50;
                block = 15; continue;
            },
            14 => {
                block = 15;
            },
            15 => {
                r51 = locals[1];
                r52 = locals[6];
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r51)))))).append(r52);
                r53 = locals[5];
                r54 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r53))))))[0];
                locals[2] = r54;
                block = 12; continue;
            },
            16 => {
                r60 = locals[2];
                r61 = 1;
                r62 = r60 +% r61;
                locals[2] = r62;
                r63 = 0;
                locals[7] = r63;
                r64 = locals[2];
                r65 = 1;
                r66 = r64 +% r65;
                locals[2] = r66;
                r67 = locals[0];
                r68 = locals[2];
                r69 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r70 = 6;
                r71 = verve_Parser_expect_kind(r67, r68, r69);
                locals[2] = r71;
                var list_72 = List.init();
                r72 = @intCast(@intFromPtr(&list_72));
                locals[8] = r72;
                block = 19; continue;
            },
            17 => {
                r116 = locals[0];
                r117 = locals[2];
                r118 = @intCast(@intFromPtr(@as([*]const u8, "import")));
                r119 = 6;
                r120 = verve_Parser_is_kw(r116, r117, r118);
                block = if (r120 != 0) 22 else 23; continue;
            },
            18 => {
                block = 12; continue;
            },
            19 => {
                r73 = locals[0];
                r74 = locals[2];
                r75 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r76 = 6;
                r77 = verve_Parser_is_kind(r73, r74, r75);
                r78 = if (r77 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r78 != 0) 20 else 21; continue;
            },
            20 => {
                r79 = 0;
                locals[9] = r79;
                r80 = locals[2];
                r81 = 1;
                r82 = r80 +% r81;
                locals[2] = r82;
                r83 = locals[0];
                r84 = locals[2];
                r85 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r86 = 5;
                r87 = verve_Parser_expect_kind(r83, r84, r85);
                locals[2] = r87;
                r88 = 0;
                locals[10] = r88;
                r89 = locals[2];
                r90 = 1;
                r91 = r89 +% r90;
                locals[2] = r91;
                r92 = locals[0];
                r93 = locals[2];
                r94 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r95 = 4;
                r96 = verve_Parser_expect_kind(r92, r93, r94);
                locals[2] = r96;
                r97 = locals[8];
                r98 = @intCast(@intFromPtr(@as([*]const u8, "field")));
                r99 = 5;
                r100 = locals[9];
                r101 = locals[10];
                r102 = verve_Parser_node(r98, r100, r101);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r97)))))).append(r102);
                block = 19; continue;
            },
            21 => {
                r103 = locals[0];
                r104 = locals[2];
                r105 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r106 = 6;
                r107 = verve_Parser_expect_kind(r103, r104, r105);
                locals[2] = r107;
                r108 = locals[1];
                r109 = @intCast(@intFromPtr(@as([*]const u8, "struct")));
                r110 = 6;
                r111 = locals[7];
                r112 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r113 = 0;
                r114 = locals[8];
                r115 = verve_Parser_node_with(r109, r111, r112, r114);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r108)))))).append(r115);
                block = 18; continue;
            },
            22 => {
                r121 = locals[2];
                r122 = 1;
                r123 = r121 +% r122;
                locals[2] = r123;
                r124 = 0;
                locals[11] = r124;
                r125 = locals[2];
                r126 = 1;
                r127 = r125 +% r126;
                locals[2] = r127;
                r128 = locals[0];
                r129 = locals[2];
                r130 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r131 = 4;
                r132 = verve_Parser_expect_kind(r128, r129, r130);
                locals[2] = r132;
                r133 = locals[1];
                r134 = @intCast(@intFromPtr(@as([*]const u8, "import")));
                r135 = 6;
                r136 = locals[11];
                r137 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r138 = 0;
                r139 = verve_Parser_node(r134, r136, r137);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r133)))))).append(r139);
                block = 24; continue;
            },
            23 => {
                r140 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected token: ")));
                r141 = 18;
                r142 = locals[3];
                r143 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r142))))))[0];
                r144 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r145 = 2;
                r146 = locals[3];
                r147 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r146))))))[1];
                r148 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r149 = 1;
                r151 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected token: ")));
                r152 = 18;
                r153 = locals[3];
                r154 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r153))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r155 = @intCast(sl); }
                r156 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r157 = 2;
                r158 = locals[3];
                r159 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r158))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r159)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r160 = @intCast(sl); }
                r161 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r162 = 1;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r151))))), r152);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154))))), r155);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r156))))), r157);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r159))))), r160);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r161))))), r162);
                verve_write(1, "\n", 1);
                r150 = 0;
                r163 = locals[2];
                r164 = 1;
                r165 = r163 +% r164;
                locals[2] = r165;
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
                r189 = locals[0];
                r190 = locals[2];
                r191 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r192 = 6;
                r193 = verve_Parser_expect_kind(r189, r190, r191);
                locals[2] = r193;
                r194 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 2) catch &.{}).ptr));
                r195 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r194))))))[0] = r195;
                r196 = @intCast(@intFromPtr(@as([*]const u8, "module")));
                r197 = 6;
                r198 = locals[3];
                r199 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r200 = 0;
                r201 = locals[4];
                r202 = verve_Parser_node_with(r196, r198, r199, r201);
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r194))))))[1] = r202;
                return r194;
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
                locals[5] = r35;
                r36 = locals[4];
                r37 = locals[5];
                r38 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r37))))))[1];
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r36)))))).append(r38);
                r39 = locals[5];
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
                locals[6] = r49;
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
                r84 = locals[0];
                r85 = locals[2];
                r86 = @intCast(@intFromPtr(@as([*]const u8, "ident")));
                r87 = 5;
                r88 = verve_Parser_is_kind(r84, r85, r86);
                block = if (r88 != 0) 16 else 17; continue;
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
                r80 = locals[6];
                r81 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r82 = 0;
                r83 = verve_Parser_node(r78, r80, r81);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r77)))))).append(r83);
                block = 12; continue;
            },
            16 => {
                r89 = 0;
                locals[7] = r89;
                r90 = locals[2];
                r91 = 1;
                r92 = r90 +% r91;
                locals[2] = r92;
                r93 = locals[0];
                r94 = locals[2];
                r95 = @intCast(@intFromPtr(@as([*]const u8, "colon")));
                r96 = 5;
                r97 = verve_Parser_expect_kind(r93, r94, r95);
                locals[2] = r97;
                r98 = 0;
                locals[8] = r98;
                r99 = locals[2];
                r100 = 1;
                r101 = r99 +% r100;
                locals[2] = r101;
                r102 = locals[0];
                r103 = locals[2];
                r104 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r105 = 2;
                r106 = verve_Parser_is_kind(r102, r103, r104);
                block = if (r106 != 0) 19 else 21; continue;
            },
            17 => {
                r167 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected in module: ")));
                r168 = 22;
                r169 = 0;
                r170 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r171 = 2;
                r172 = 0;
                r173 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r174 = 1;
                r176 = @intCast(@intFromPtr(@as([*]const u8, "Unexpected in module: ")));
                r177 = 22;
                r178 = 0;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r178)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r179 = @intCast(sl); }
                r180 = @intCast(@intFromPtr(@as([*]const u8, " '")));
                r181 = 2;
                r182 = 0;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r182)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r183 = @intCast(sl); }
                r184 = @intCast(@intFromPtr(@as([*]const u8, "'")));
                r185 = 1;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r176))))), r177);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r178))))), r179);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r180))))), r181);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r182))))), r183);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r184))))), r185);
                verve_write(1, "\n", 1);
                r175 = 0;
                r186 = locals[2];
                r187 = 1;
                r188 = r186 +% r187;
                locals[2] = r188;
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
                r119 = locals[0];
                r120 = locals[2];
                r121 = @intCast(@intFromPtr(@as([*]const u8, "eq")));
                r122 = 2;
                r123 = verve_Parser_expect_kind(r119, r120, r121);
                locals[2] = r123;
                r124 = 0;
                locals[9] = r124;
                block = 25; continue;
            },
            22 => {
                r107 = locals[0];
                r108 = locals[2];
                r109 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r110 = 2;
                r111 = verve_Parser_is_kind(r107, r108, r109);
                r112 = if (r111 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r112 != 0) 23 else 24; continue;
            },
            23 => {
                r113 = locals[2];
                r114 = 1;
                r115 = r113 +% r114;
                locals[2] = r115;
                block = 22; continue;
            },
            24 => {
                r116 = locals[2];
                r117 = 1;
                r118 = r116 +% r117;
                locals[2] = r118;
                block = 21; continue;
            },
            25 => {
                r125 = locals[2];
                r126 = locals[0];
                r127 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r126)))))).len;
                r128 = if (r125 < r127) @as(i64, 1) else @as(i64, 0);
                block = if (r128 != 0) 26 else 27; continue;
            },
            26 => {
                r129 = locals[0];
                r130 = locals[2];
                r131 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r132 = 4;
                r133 = verve_Parser_is_kind(r129, r130, r131);
                block = if (r133 != 0) 28 else 30; continue;
            },
            27 => {
                r156 = locals[0];
                r157 = locals[2];
                r158 = @intCast(@intFromPtr(@as([*]const u8, "semi")));
                r159 = 4;
                r160 = verve_Parser_expect_kind(r156, r157, r158);
                locals[2] = r160;
                r161 = locals[4];
                r162 = @intCast(@intFromPtr(@as([*]const u8, "const")));
                r163 = 5;
                r164 = locals[7];
                r165 = locals[8];
                r166 = verve_Parser_node(r162, r164, r165);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r161)))))).append(r166);
                block = 18; continue;
            },
            28 => {
                r134 = locals[9];
                r135 = 0;
                r136 = if (r134 == r135) @as(i64, 1) else @as(i64, 0);
                block = if (r136 != 0) 31 else 33; continue;
            },
            29 => {
                block = 30;
            },
            30 => {
                r137 = locals[0];
                r138 = locals[2];
                r139 = @intCast(@intFromPtr(@as([*]const u8, "lparen")));
                r140 = 6;
                r141 = verve_Parser_is_kind(r137, r138, r139);
                block = if (r141 != 0) 34 else 36; continue;
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
                r142 = locals[9];
                r143 = 1;
                r144 = r142 +% r143;
                locals[9] = r144;
                block = 36; continue;
            },
            35 => {
                block = 36;
            },
            36 => {
                r145 = locals[0];
                r146 = locals[2];
                r147 = @intCast(@intFromPtr(@as([*]const u8, "rparen")));
                r148 = 6;
                r149 = verve_Parser_is_kind(r145, r146, r147);
                block = if (r149 != 0) 37 else 39; continue;
            },
            37 => {
                r150 = locals[9];
                r151 = 1;
                r152 = r150 -% r151;
                locals[9] = r152;
                block = 39; continue;
            },
            38 => {
                block = 39;
            },
            39 => {
                r153 = locals[2];
                r154 = 1;
                r155 = r153 +% r154;
                locals[2] = r155;
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
                r61 = locals[0];
                r62 = locals[2];
                r63 = @intCast(@intFromPtr(@as([*]const u8, "rparen")));
                r64 = 6;
                r65 = verve_Parser_expect_kind(r61, r62, r63);
                locals[2] = r65;
                r66 = locals[0];
                r67 = locals[2];
                r68 = @intCast(@intFromPtr(@as([*]const u8, "arrow")));
                r69 = 5;
                r70 = verve_Parser_expect_kind(r66, r67, r68);
                locals[2] = r70;
                r71 = 0;
                locals[7] = r71;
                r72 = locals[2];
                r73 = 1;
                r74 = r72 +% r73;
                locals[2] = r74;
                r75 = locals[0];
                r76 = locals[2];
                r77 = @intCast(@intFromPtr(@as([*]const u8, "lt")));
                r78 = 2;
                r79 = verve_Parser_is_kind(r75, r76, r77);
                block = if (r79 != 0) 13 else 15; continue;
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
                r51 = locals[6];
                r52 = verve_Parser_node(r48, r50, r51);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r47)))))).append(r52);
                r53 = locals[0];
                r54 = locals[2];
                r55 = @intCast(@intFromPtr(@as([*]const u8, "comma")));
                r56 = 5;
                r57 = verve_Parser_is_kind(r53, r54, r55);
                block = if (r57 != 0) 10 else 12; continue;
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
                r58 = locals[2];
                r59 = 1;
                r60 = r58 +% r59;
                locals[2] = r60;
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
                r92 = locals[0];
                r93 = locals[2];
                r94 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r95 = 6;
                r96 = verve_Parser_expect_kind(r92, r93, r94);
                locals[2] = r96;
                r97 = 1;
                locals[8] = r97;
                r98 = 0;
                locals[9] = r98;
                block = 19; continue;
            },
            16 => {
                r80 = locals[0];
                r81 = locals[2];
                r82 = @intCast(@intFromPtr(@as([*]const u8, "gt")));
                r83 = 2;
                r84 = verve_Parser_is_kind(r80, r81, r82);
                r85 = if (r84 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r85 != 0) 17 else 18; continue;
            },
            17 => {
                r86 = locals[2];
                r87 = 1;
                r88 = r86 +% r87;
                locals[2] = r88;
                block = 16; continue;
            },
            18 => {
                r89 = locals[2];
                r90 = 1;
                r91 = r89 +% r90;
                locals[2] = r91;
                block = 15; continue;
            },
            19 => {
                r99 = locals[8];
                r100 = 0;
                r101 = if (r99 > r100) @as(i64, 1) else @as(i64, 0);
                block = if (r101 != 0) 20 else 21; continue;
            },
            20 => {
                r102 = locals[0];
                r103 = locals[2];
                r104 = @intCast(@intFromPtr(@as([*]const u8, "lbrace")));
                r105 = 6;
                r106 = verve_Parser_is_kind(r102, r103, r104);
                block = if (r106 != 0) 22 else 24; continue;
            },
            21 => {
                r127 = locals[0];
                r128 = locals[2];
                r129 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r130 = 6;
                r131 = verve_Parser_expect_kind(r127, r128, r129);
                locals[2] = r131;
                r132 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r133 = 2;
                r134 = locals[3];
                r135 = locals[7];
                r136 = verve_Parser_node(r132, r134, r135);
                locals[10] = r136;
                r137 = 0;
                locals[11] = r137;
                block = 31; continue;
            },
            22 => {
                r107 = locals[8];
                r108 = 1;
                r109 = r107 +% r108;
                locals[8] = r109;
                block = 24; continue;
            },
            23 => {
                block = 24;
            },
            24 => {
                r110 = locals[0];
                r111 = locals[2];
                r112 = @intCast(@intFromPtr(@as([*]const u8, "rbrace")));
                r113 = 6;
                r114 = verve_Parser_is_kind(r110, r111, r112);
                block = if (r114 != 0) 25 else 27; continue;
            },
            25 => {
                r115 = locals[8];
                r116 = 1;
                r117 = r115 -% r116;
                locals[8] = r117;
                block = 27; continue;
            },
            26 => {
                block = 27;
            },
            27 => {
                r118 = locals[8];
                r119 = 0;
                r120 = if (r118 > r119) @as(i64, 1) else @as(i64, 0);
                block = if (r120 != 0) 28 else 30; continue;
            },
            28 => {
                r121 = locals[9];
                r122 = 1;
                r123 = r121 +% r122;
                locals[9] = r123;
                r124 = locals[2];
                r125 = 1;
                r126 = r124 +% r125;
                locals[2] = r126;
                block = 30; continue;
            },
            29 => {
                block = 30;
            },
            30 => {
                block = 19; continue;
            },
            31 => {
                r138 = locals[11];
                r139 = locals[4];
                r140 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r139)))))).len;
                r141 = if (r138 < r140) @as(i64, 1) else @as(i64, 0);
                block = if (r141 != 0) 32 else 33; continue;
            },
            32 => {
                r142 = locals[10];
                r143 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r142))))))[3];
                r144 = locals[4];
                r145 = locals[11];
                r146 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r144)))))).get(r145);
                @as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r143)))))).append(r146);
                r147 = locals[11];
                r148 = 1;
                r149 = r147 +% r148;
                locals[11] = r149;
                block = 31; continue;
            },
            33 => {
                r150 = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, 2) catch &.{}).ptr));
                r151 = locals[2];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r150))))))[0] = r151;
                r152 = locals[10];
                @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r150))))))[1] = r152;
                return r150;
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
                r7 = @intCast(@intFromPtr(@as([*]const u8, "  ")));
                r8 = 2;
                r9 = r6 +% r7;
                locals[2] = r9;
                r10 = locals[4];
                r11 = 1;
                r12 = r10 +% r11;
                locals[4] = r12;
                block = 1; continue;
            },
            3 => {
                r13 = locals[0];
                r14 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r13))))))[0];
                r15 = @intCast(@intFromPtr(@as([*]const u8, "module")));
                r16 = 6;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r14)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r17 = @intCast(sl); }
                r18 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r14))))), r17, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r15))))), r16)) @as(i64, 1) else @as(i64, 0);
                block = if (r18 != 0) 4 else 5; continue;
            },
            4 => {
                r19 = locals[2];
                r20 = @intCast(@intFromPtr(@as([*]const u8, "module ")));
                r21 = 7;
                r22 = locals[0];
                r23 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r22))))))[1];
                r25 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r26 = @intCast(sl); }
                r27 = @intCast(@intFromPtr(@as([*]const u8, "module ")));
                r28 = 7;
                r29 = locals[0];
                r30 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r29))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r30)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r31 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r25))))), r26);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r27))))), r28);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r30))))), r31);
                verve_write(1, "\n", 1);
                r24 = 0;
                block = 6; continue;
            },
            5 => {
                r32 = locals[0];
                r33 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r32))))))[0];
                r34 = @intCast(@intFromPtr(@as([*]const u8, "module_exported")));
                r35 = 15;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r36 = @intCast(sl); }
                r37 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33))))), r36, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r34))))), r35)) @as(i64, 1) else @as(i64, 0);
                block = if (r37 != 0) 7 else 8; continue;
            },
            6 => {
                r265 = 0;
                locals[5] = r265;
                block = 37; continue;
            },
            7 => {
                r38 = locals[2];
                r39 = @intCast(@intFromPtr(@as([*]const u8, "export module ")));
                r40 = 14;
                r41 = locals[0];
                r42 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r41))))))[1];
                r44 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r44)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r45 = @intCast(sl); }
                r46 = @intCast(@intFromPtr(@as([*]const u8, "export module ")));
                r47 = 14;
                r48 = locals[0];
                r49 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r48))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r49)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r50 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r44))))), r45);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r46))))), r47);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r49))))), r50);
                verve_write(1, "\n", 1);
                r43 = 0;
                block = 9; continue;
            },
            8 => {
                r51 = locals[0];
                r52 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r51))))))[0];
                r53 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r54 = 2;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r52)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r55 = @intCast(sl); }
                r56 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r52))))), r55, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r53))))), r54)) @as(i64, 1) else @as(i64, 0);
                block = if (r56 != 0) 10 else 11; continue;
            },
            9 => {
                block = 6; continue;
            },
            10 => {
                r57 = locals[2];
                r58 = @intCast(@intFromPtr(@as([*]const u8, "fn ")));
                r59 = 3;
                r60 = locals[0];
                r61 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r60))))))[1];
                r62 = @intCast(@intFromPtr(@as([*]const u8, "(")));
                r63 = 1;
                r65 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r65)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r66 = @intCast(sl); }
                r67 = @intCast(@intFromPtr(@as([*]const u8, "fn ")));
                r68 = 3;
                r69 = locals[0];
                r70 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r69))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r70)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r71 = @intCast(sl); }
                r72 = @intCast(@intFromPtr(@as([*]const u8, "(")));
                r73 = 1;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r65))))), r66);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r67))))), r68);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r70))))), r71);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r72))))), r73);
                r64 = 0;
                r74 = 0;
                locals[6] = r74;
                block = 13; continue;
            },
            11 => {
                r118 = locals[0];
                r119 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r118))))))[0];
                r120 = @intCast(@intFromPtr(@as([*]const u8, "const")));
                r121 = 5;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r119)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r122 = @intCast(sl); }
                r123 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r119))))), r122, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r120))))), r121)) @as(i64, 1) else @as(i64, 0);
                block = if (r123 != 0) 19 else 20; continue;
            },
            12 => {
                block = 9; continue;
            },
            13 => {
                r75 = locals[6];
                r76 = 0;
                r77 = if (r75 < r76) @as(i64, 1) else @as(i64, 0);
                block = if (r77 != 0) 14 else 15; continue;
            },
            14 => {
                r78 = locals[0];
                r79 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r78))))))[3];
                r80 = locals[6];
                r81 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r79)))))).get(r80);
                locals[7] = r81;
                r82 = locals[6];
                r83 = 0;
                r84 = if (r82 > r83) @as(i64, 1) else @as(i64, 0);
                block = if (r84 != 0) 16 else 18; continue;
            },
            15 => {
                r108 = @intCast(@intFromPtr(@as([*]const u8, ") -> ")));
                r109 = 5;
                r110 = locals[0];
                r111 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r110))))))[2];
                r113 = @intCast(@intFromPtr(@as([*]const u8, ") -> ")));
                r114 = 5;
                r115 = locals[0];
                r116 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r115))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r116)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r117 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r113))))), r114);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r116))))), r117);
                verve_write(1, "\n", 1);
                r112 = 0;
                block = 12; continue;
            },
            16 => {
                r85 = @intCast(@intFromPtr(@as([*]const u8, ", ")));
                r86 = 2;
                r88 = @intCast(@intFromPtr(@as([*]const u8, ", ")));
                r89 = 2;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r88))))), r89);
                r87 = 0;
                block = 18; continue;
            },
            17 => {
                block = 18;
            },
            18 => {
                r90 = locals[7];
                r91 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r90))))))[1];
                r92 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r93 = 2;
                r94 = locals[7];
                r95 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r94))))))[2];
                r97 = locals[7];
                r98 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r97))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r98)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r99 = @intCast(sl); }
                r100 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r101 = 2;
                r102 = locals[7];
                r103 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r102))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r103)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r104 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r98))))), r99);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r100))))), r101);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r103))))), r104);
                r96 = 0;
                r105 = locals[6];
                r106 = 1;
                r107 = r105 +% r106;
                locals[6] = r107;
                block = 13; continue;
            },
            19 => {
                r124 = locals[2];
                r125 = locals[0];
                r126 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r125))))))[1];
                r127 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r128 = 2;
                r129 = locals[0];
                r130 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r129))))))[2];
                r132 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r132)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r133 = @intCast(sl); }
                r134 = locals[0];
                r135 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r134))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r135)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r136 = @intCast(sl); }
                r137 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r138 = 2;
                r139 = locals[0];
                r140 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r139))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r140)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r141 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r132))))), r133);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r135))))), r136);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r137))))), r138);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r140))))), r141);
                verve_write(1, "\n", 1);
                r131 = 0;
                block = 21; continue;
            },
            20 => {
                r142 = locals[0];
                r143 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r142))))))[0];
                r144 = @intCast(@intFromPtr(@as([*]const u8, "use")));
                r145 = 3;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r143)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r146 = @intCast(sl); }
                r147 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r143))))), r146, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r144))))), r145)) @as(i64, 1) else @as(i64, 0);
                block = if (r147 != 0) 22 else 23; continue;
            },
            21 => {
                block = 12; continue;
            },
            22 => {
                r148 = locals[2];
                r149 = @intCast(@intFromPtr(@as([*]const u8, "use ")));
                r150 = 4;
                r151 = locals[0];
                r152 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r151))))))[1];
                r154 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r155 = @intCast(sl); }
                r156 = @intCast(@intFromPtr(@as([*]const u8, "use ")));
                r157 = 4;
                r158 = locals[0];
                r159 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r158))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r159)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r160 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r154))))), r155);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r156))))), r157);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r159))))), r160);
                verve_write(1, "\n", 1);
                r153 = 0;
                block = 24; continue;
            },
            23 => {
                r161 = locals[0];
                r162 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r161))))))[0];
                r163 = @intCast(@intFromPtr(@as([*]const u8, "struct")));
                r164 = 6;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r162)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r165 = @intCast(sl); }
                r166 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r162))))), r165, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r163))))), r164)) @as(i64, 1) else @as(i64, 0);
                block = if (r166 != 0) 25 else 26; continue;
            },
            24 => {
                block = 21; continue;
            },
            25 => {
                r167 = locals[2];
                r168 = @intCast(@intFromPtr(@as([*]const u8, "struct ")));
                r169 = 7;
                r170 = locals[0];
                r171 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r170))))))[1];
                r173 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r173)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r174 = @intCast(sl); }
                r175 = @intCast(@intFromPtr(@as([*]const u8, "struct ")));
                r176 = 7;
                r177 = locals[0];
                r178 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r177))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r178)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r179 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r173))))), r174);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r175))))), r176);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r178))))), r179);
                verve_write(1, "\n", 1);
                r172 = 0;
                block = 27; continue;
            },
            26 => {
                r180 = locals[0];
                r181 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r180))))))[0];
                r182 = @intCast(@intFromPtr(@as([*]const u8, "field")));
                r183 = 5;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r184 = @intCast(sl); }
                r185 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r181))))), r184, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r182))))), r183)) @as(i64, 1) else @as(i64, 0);
                block = if (r185 != 0) 28 else 29; continue;
            },
            27 => {
                block = 24; continue;
            },
            28 => {
                r186 = locals[2];
                r187 = locals[0];
                r188 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r187))))))[1];
                r189 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r190 = 2;
                r191 = locals[0];
                r192 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r191))))))[2];
                r194 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r194)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r195 = @intCast(sl); }
                r196 = locals[0];
                r197 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r196))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r197)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r198 = @intCast(sl); }
                r199 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r200 = 2;
                r201 = locals[0];
                r202 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r201))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r202)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r203 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r194))))), r195);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r197))))), r198);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r199))))), r200);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r202))))), r203);
                verve_write(1, "\n", 1);
                r193 = 0;
                block = 30; continue;
            },
            29 => {
                r204 = locals[0];
                r205 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r204))))))[0];
                r206 = @intCast(@intFromPtr(@as([*]const u8, "import")));
                r207 = 6;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r205)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r208 = @intCast(sl); }
                r209 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r205))))), r208, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r206))))), r207)) @as(i64, 1) else @as(i64, 0);
                block = if (r209 != 0) 31 else 32; continue;
            },
            30 => {
                block = 27; continue;
            },
            31 => {
                r210 = locals[2];
                r211 = @intCast(@intFromPtr(@as([*]const u8, "import ")));
                r212 = 7;
                r213 = locals[0];
                r214 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r213))))))[1];
                r216 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r216)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r217 = @intCast(sl); }
                r218 = @intCast(@intFromPtr(@as([*]const u8, "import ")));
                r219 = 7;
                r220 = locals[0];
                r221 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r220))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r221)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r222 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r216))))), r217);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r218))))), r219);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r221))))), r222);
                verve_write(1, "\n", 1);
                r215 = 0;
                block = 33; continue;
            },
            32 => {
                r223 = locals[0];
                r224 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r223))))))[0];
                r225 = @intCast(@intFromPtr(@as([*]const u8, "param")));
                r226 = 5;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r224)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r227 = @intCast(sl); }
                r228 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r224))))), r227, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r225))))), r226)) @as(i64, 1) else @as(i64, 0);
                block = if (r228 != 0) 34 else 35; continue;
            },
            33 => {
                block = 30; continue;
            },
            34 => {
                r229 = locals[2];
                r230 = locals[0];
                r231 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r230))))))[1];
                r232 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r233 = 2;
                r234 = locals[0];
                r235 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r234))))))[2];
                r237 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r237)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r238 = @intCast(sl); }
                r239 = locals[0];
                r240 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r239))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r240)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r241 = @intCast(sl); }
                r242 = @intCast(@intFromPtr(@as([*]const u8, ": ")));
                r243 = 2;
                r244 = locals[0];
                r245 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r244))))))[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r245)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r246 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r237))))), r238);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r240))))), r241);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r242))))), r243);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r245))))), r246);
                verve_write(1, "\n", 1);
                r236 = 0;
                block = 36; continue;
            },
            35 => {
                r247 = locals[2];
                r248 = locals[0];
                r249 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r248))))))[0];
                r250 = @intCast(@intFromPtr(@as([*]const u8, " ")));
                r251 = 1;
                r252 = locals[0];
                r253 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r252))))))[1];
                r255 = locals[2];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r255)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r256 = @intCast(sl); }
                r257 = locals[0];
                r258 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r257))))))[0];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r258)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r259 = @intCast(sl); }
                r260 = @intCast(@intFromPtr(@as([*]const u8, " ")));
                r261 = 1;
                r262 = locals[0];
                r263 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r262))))))[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r263)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r264 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r255))))), r256);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r258))))), r259);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r260))))), r261);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r263))))), r264);
                verve_write(1, "\n", 1);
                r254 = 0;
                block = 36; continue;
            },
            36 => {
                block = 33; continue;
            },
            37 => {
                r266 = locals[5];
                r267 = 0;
                r268 = if (r266 < r267) @as(i64, 1) else @as(i64, 0);
                block = if (r268 != 0) 38 else 39; continue;
            },
            38 => {
                r269 = locals[0];
                r270 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r269))))))[3];
                r271 = locals[5];
                r272 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r270)))))).get(r271);
                locals[8] = r272;
                r273 = locals[0];
                r274 = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r273))))))[0];
                r275 = @intCast(@intFromPtr(@as([*]const u8, "fn")));
                r276 = 2;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r274)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r277 = @intCast(sl); }
                r278 = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r274))))), r277, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r275))))), r276)) @as(i64, 1) else @as(i64, 0);
                r279 = if (r278 == 0) @as(i64, 1) else @as(i64, 0);
                block = if (r279 != 0) 40 else 42; continue;
            },
            39 => {
                block = 40;
            },
            40 => {
                r280 = locals[8];
                r281 = locals[1];
                r282 = 1;
                r283 = r281 +% r282;
                r284 = verve_Printer_print_node(r280, r283);
                block = 42; continue;
            },
            41 => {
                block = 42;
            },
            42 => {
                r285 = locals[5];
                r286 = 1;
                r287 = r285 +% r286;
                locals[5] = r287;
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
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r7))))), r8);
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
                r14 = @intCast(@intFromPtr(@as([*]const u8, "r")));
                r15 = 1;
                r17 = locals[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r17)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r18 = @intCast(sl); }
                r19 = @intCast(@intFromPtr(@as([*]const u8, "r")));
                r20 = 1;
                r21 = 1;
                r16 = fileOpen(r17, r18);
                locals[2] = r16;
                r22 = locals[2];
                r23 = getTag(r22);
                r24 = 0;
                r25 = if (r23 == r24) @as(i64, 1) else @as(i64, 0);
                block = if (r25 != 0) 5 else 6; continue;
            },
            4 => {
                block = 5;
            },
            5 => {
                r26 = getTagValue(r22);
                locals[3] = r26;
                r27 = locals[3];
                r28 = streamReadAll(r27);
                locals[4] = r28;
                r29 = locals[3];
                r30 = 0; // stream close (no-op)
                r31 = locals[4];
                r32 = verve_Tokenizer_tokenize(r31);
                locals[5] = r32;
                r33 = @intCast(@intFromPtr(@as([*]const u8, "Tokenized: ")));
                r34 = 11;
                r35 = locals[5];
                r36 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r35)))))).len;
                r37 = @intCast(@intFromPtr(@as([*]const u8, " tokens")));
                r38 = 7;
                r40 = @intCast(@intFromPtr(@as([*]const u8, "Tokenized: ")));
                r41 = 11;
                r42 = locals[5];
                r43 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r42)))))).len;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r44 = @intCast(sl); }
                r45 = @intCast(@intFromPtr(@as([*]const u8, " tokens")));
                r46 = 7;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r40))))), r41);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r43))))), r44);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r45))))), r46);
                verve_write(1, "\n", 1);
                r39 = 0;
                r47 = locals[5];
                r48 = verve_Parser_parse_file(r47);
                locals[6] = r48;
                r49 = @intCast(@intFromPtr(@as([*]const u8, "Parsed: ")));
                r50 = 8;
                r51 = locals[6];
                r52 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r51)))))).len;
                r53 = @intCast(@intFromPtr(@as([*]const u8, " declarations")));
                r54 = 13;
                r56 = @intCast(@intFromPtr(@as([*]const u8, "Parsed: ")));
                r57 = 8;
                r58 = locals[6];
                r59 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r58)))))).len;
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r59)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r60 = @intCast(sl); }
                r61 = @intCast(@intFromPtr(@as([*]const u8, " declarations")));
                r62 = 13;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r56))))), r57);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r59))))), r60);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r61))))), r62);
                verve_write(1, "\n", 1);
                r55 = 0;
                r63 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r64 = 0;
                r66 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r67 = 0;
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r66))))), r67);
                verve_write(1, "\n", 1);
                r65 = 0;
                r68 = 0;
                locals[7] = r68;
                block = 7; continue;
            },
            6 => {
                r82 = getTag(r22);
                r83 = 1;
                r84 = if (r82 == r83) @as(i64, 1) else @as(i64, 0);
                block = if (r84 != 0) 10 else 11; continue;
            },
            7 => {
                r69 = locals[7];
                r70 = locals[6];
                r71 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r70)))))).len;
                r72 = if (r69 < r71) @as(i64, 1) else @as(i64, 0);
                block = if (r72 != 0) 8 else 9; continue;
            },
            8 => {
                r73 = locals[6];
                r74 = locals[7];
                r75 = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r73)))))).get(r74);
                r76 = 0;
                r77 = verve_Printer_print_node(r75, r76);
                r78 = locals[7];
                r79 = 1;
                r80 = r78 +% r79;
                locals[7] = r80;
                block = 7; continue;
            },
            9 => {
                r81 = 0;
                std.posix.exit(@intCast(@as(u64, @bitCast(r81))));
            },
            10 => {
                r85 = getTagValue(r22);
                locals[8] = r85;
                r86 = @intCast(@intFromPtr(@as([*]const u8, "Error: could not open ")));
                r87 = 22;
                r88 = locals[1];
                r90 = @intCast(@intFromPtr(@as([*]const u8, "Error: could not open ")));
                r91 = 22;
                r92 = locals[1];
                { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r92)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r93 = @intCast(sl); }
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r90))))), r91);
                verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r92))))), r93);
                verve_write(1, "\n", 1);
                r89 = 0;
                r94 = 1;
                std.posix.exit(@intCast(@as(u64, @bitCast(r94))));
            },
            11 => {
                block = 4; continue;
            },
            else => break,
        }
    }
}
