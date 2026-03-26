const std = @import("std");
const rt = @import("verve_runtime.zig");

fn verve_dispatch_0(handler_id: i64, args: [*]const i64, arg_count: i64) i64 {
    _ = arg_count;
    _ = &args;
    return switch (handler_id) {
        0 => verve_Counter_Increment(),
        1 => verve_Counter_GetCount(),
        2 => verve_Counter_Add(args[0]),
        else => rt.makeTagged(1, 0),
    };
}

fn verve_init_dispatch() void {
    rt.dispatch_table[0] = &verve_dispatch_0;
}

fn verve_Counter_Increment() i64 {
    var r0: i64 = 0;
    _ = &r0;
    var r1: i64 = 0;
    _ = &r1;
    var r2: i64 = 0;
    _ = &r2;
    var r3: i64 = 0;
    _ = &r3;
    var locals: [256]i64 = undefined;
    _ = &locals;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = rt.verve_state_get(0);
                r1 = 1;
                r2 = r0 +% r1;
                rt.verve_state_set(0, r2);
                r3 = rt.verve_state_get(0);
                return r3;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Counter_GetCount() i64 {
    var r0: i64 = 0;
    _ = &r0;
    var locals: [256]i64 = undefined;
    _ = &locals;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = rt.verve_state_get(0);
                return r0;
            },
            else => break,
        }
    }
    return 0;
}

fn verve_Counter_Add(param_n: i64) i64 {
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
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_n;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = 0;
                r2 = if (r0 > r1) @as(i64, 1) else @as(i64, 0);
                block = if (r2 != 0) 1 else 2; continue;
            },
            1 => {
                r6 = rt.verve_state_get(0);
                r7 = locals[0];
                r8 = r6 +% r7;
                rt.verve_state_set(0, r8);
                r9 = rt.verve_state_get(0);
                return r9;
            },
            2 => {
                r3 = 1;
                r4 = 99;
                r5 = rt.makeTagged(r3, r4);
                return r5;
            },
            else => break,
        }
    }
    return 0;
}

pub fn main() void {
    rt.verve_runtime_init();
    verve_init_dispatch();
    var verve_args_list = rt.List.init();
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
    var locals: [256]i64 = undefined;
    _ = &locals;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = @intCast(@intFromPtr(@as([*]const u8, "=== Verve Process Test ===")));
                r1 = 26;
                r3 = @intCast(@intFromPtr(@as([*]const u8, "=== Verve Process Test ===")));
                r4 = 26;
                if (r4 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r3}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r3))))), r4); }
                rt.verve_write(1, "\n", 1);
                r2 = 0;
                r5 = rt.verve_spawn(0);
                locals[0] = r5;
                r6 = @intCast(@intFromPtr(@as([*]const u8, "Spawned counter process")));
                r7 = 23;
                r9 = @intCast(@intFromPtr(@as([*]const u8, "Spawned counter process")));
                r10 = 23;
                if (r10 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r9}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r9))))), r10); }
                rt.verve_write(1, "\n", 1);
                r8 = 0;
                r12 = locals[0];
                { const send_args = [_]i64{0}; r11 = rt.verve_send(r12, 0, &send_args, 0); }
                r13 = rt.getTag(r11);
                r14 = 0;
                r15 = if (r13 == r14) @as(i64, 1) else @as(i64, 0);
                block = if (r15 != 0) 2 else 3; continue;
            },
            1 => {
                r38 = locals[0];
                { const send_args = [_]i64{0}; r37 = rt.verve_send(r38, 0, &send_args, 0); }
                r39 = rt.getTag(r37);
                r40 = 0;
                r41 = if (r39 == r40) @as(i64, 1) else @as(i64, 0);
                block = if (r41 != 0) 7 else 8; continue;
            },
            2 => {
                r16 = rt.getTagValue(r11);
                locals[1] = r16;
                r17 = @intCast(@intFromPtr(@as([*]const u8, "After increment: ")));
                r18 = 17;
                r19 = locals[1];
                r21 = @intCast(@intFromPtr(@as([*]const u8, "After increment: ")));
                r22 = 17;
                r23 = locals[1];
                r24 = -1;
                if (r22 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r21}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r21))))), r22); }
                if (r24 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r23}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r23))))), r24); }
                rt.verve_write(1, "\n", 1);
                r20 = 0;
                block = 1; continue;
            },
            3 => {
                r25 = rt.getTag(r11);
                r26 = 1;
                r27 = if (r25 == r26) @as(i64, 1) else @as(i64, 0);
                block = if (r27 != 0) 4 else 5; continue;
            },
            4 => {
                r28 = rt.getTagValue(r11);
                locals[2] = r28;
                r29 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r30 = 7;
                r31 = locals[2];
                r33 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r34 = 7;
                r35 = locals[2];
                r36 = -1;
                if (r34 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r33}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r33))))), r34); }
                if (r36 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r35}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r35))))), r36); }
                rt.verve_write(1, "\n", 1);
                r32 = 0;
                block = 1; continue;
            },
            5 => {
                block = 1; continue;
            },
            6 => {
                r64 = locals[0];
                { const send_args = [_]i64{0}; r63 = rt.verve_send(r64, 0, &send_args, 0); }
                r65 = rt.getTag(r63);
                r66 = 0;
                r67 = if (r65 == r66) @as(i64, 1) else @as(i64, 0);
                block = if (r67 != 0) 12 else 13; continue;
            },
            7 => {
                r42 = rt.getTagValue(r37);
                locals[1] = r42;
                r43 = @intCast(@intFromPtr(@as([*]const u8, "After increment: ")));
                r44 = 17;
                r45 = locals[1];
                r47 = @intCast(@intFromPtr(@as([*]const u8, "After increment: ")));
                r48 = 17;
                r49 = locals[1];
                r50 = -1;
                if (r48 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r47}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r47))))), r48); }
                if (r50 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r49}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r49))))), r50); }
                rt.verve_write(1, "\n", 1);
                r46 = 0;
                block = 6; continue;
            },
            8 => {
                r51 = rt.getTag(r37);
                r52 = 1;
                r53 = if (r51 == r52) @as(i64, 1) else @as(i64, 0);
                block = if (r53 != 0) 9 else 10; continue;
            },
            9 => {
                r54 = rt.getTagValue(r37);
                locals[2] = r54;
                r55 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r56 = 7;
                r57 = locals[2];
                r59 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r60 = 7;
                r61 = locals[2];
                r62 = -1;
                if (r60 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r59}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r59))))), r60); }
                if (r62 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r61}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r61))))), r62); }
                rt.verve_write(1, "\n", 1);
                r58 = 0;
                block = 6; continue;
            },
            10 => {
                block = 6; continue;
            },
            11 => {
                r89 = 10;
                r91 = locals[0];
                { const send_args = [_]i64{ r89 }; r90 = rt.verve_send(r91, 2, &send_args, 1); }
                r92 = rt.getTag(r90);
                r93 = 0;
                r94 = if (r92 == r93) @as(i64, 1) else @as(i64, 0);
                block = if (r94 != 0) 17 else 18; continue;
            },
            12 => {
                r68 = rt.getTagValue(r63);
                locals[1] = r68;
                r69 = @intCast(@intFromPtr(@as([*]const u8, "After increment: ")));
                r70 = 17;
                r71 = locals[1];
                r73 = @intCast(@intFromPtr(@as([*]const u8, "After increment: ")));
                r74 = 17;
                r75 = locals[1];
                r76 = -1;
                if (r74 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r73}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r73))))), r74); }
                if (r76 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r75}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r75))))), r76); }
                rt.verve_write(1, "\n", 1);
                r72 = 0;
                block = 11; continue;
            },
            13 => {
                r77 = rt.getTag(r63);
                r78 = 1;
                r79 = if (r77 == r78) @as(i64, 1) else @as(i64, 0);
                block = if (r79 != 0) 14 else 15; continue;
            },
            14 => {
                r80 = rt.getTagValue(r63);
                locals[2] = r80;
                r81 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r82 = 7;
                r83 = locals[2];
                r85 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r86 = 7;
                r87 = locals[2];
                r88 = -1;
                if (r86 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r85}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r85))))), r86); }
                if (r88 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r87}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r87))))), r88); }
                rt.verve_write(1, "\n", 1);
                r84 = 0;
                block = 11; continue;
            },
            15 => {
                block = 11; continue;
            },
            16 => {
                r117 = locals[0];
                { const send_args = [_]i64{0}; r116 = rt.verve_send(r117, 1, &send_args, 0); }
                r118 = rt.getTag(r116);
                r119 = 0;
                r120 = if (r118 == r119) @as(i64, 1) else @as(i64, 0);
                block = if (r120 != 0) 22 else 23; continue;
            },
            17 => {
                r95 = rt.getTagValue(r90);
                locals[1] = r95;
                r96 = @intCast(@intFromPtr(@as([*]const u8, "After add 10: ")));
                r97 = 14;
                r98 = locals[1];
                r100 = @intCast(@intFromPtr(@as([*]const u8, "After add 10: ")));
                r101 = 14;
                r102 = locals[1];
                r103 = -1;
                if (r101 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r100}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r100))))), r101); }
                if (r103 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r102}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r102))))), r103); }
                rt.verve_write(1, "\n", 1);
                r99 = 0;
                block = 16; continue;
            },
            18 => {
                r104 = rt.getTag(r90);
                r105 = 1;
                r106 = if (r104 == r105) @as(i64, 1) else @as(i64, 0);
                block = if (r106 != 0) 19 else 20; continue;
            },
            19 => {
                r107 = rt.getTagValue(r90);
                locals[2] = r107;
                r108 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r109 = 7;
                r110 = locals[2];
                r112 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r113 = 7;
                r114 = locals[2];
                r115 = -1;
                if (r113 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r112}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r112))))), r113); }
                if (r115 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r114}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r114))))), r115); }
                rt.verve_write(1, "\n", 1);
                r111 = 0;
                block = 16; continue;
            },
            20 => {
                block = 16; continue;
            },
            21 => {
                r142 = @intCast(@intFromPtr(@as([*]const u8, "=== Done ===")));
                r143 = 12;
                r145 = @intCast(@intFromPtr(@as([*]const u8, "=== Done ===")));
                r146 = 12;
                if (r146 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r145}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r145))))), r146); }
                rt.verve_write(1, "\n", 1);
                r144 = 0;
                r147 = 0;
                std.posix.exit(@intCast(@as(u64, @bitCast(r147))));
            },
            22 => {
                r121 = rt.getTagValue(r116);
                locals[1] = r121;
                r122 = @intCast(@intFromPtr(@as([*]const u8, "Final count: ")));
                r123 = 13;
                r124 = locals[1];
                r126 = @intCast(@intFromPtr(@as([*]const u8, "Final count: ")));
                r127 = 13;
                r128 = locals[1];
                r129 = -1;
                if (r127 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r126}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r126))))), r127); }
                if (r129 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r128}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r128))))), r129); }
                rt.verve_write(1, "\n", 1);
                r125 = 0;
                block = 21; continue;
            },
            23 => {
                r130 = rt.getTag(r116);
                r131 = 1;
                r132 = if (r130 == r131) @as(i64, 1) else @as(i64, 0);
                block = if (r132 != 0) 24 else 25; continue;
            },
            24 => {
                r133 = rt.getTagValue(r116);
                locals[2] = r133;
                r134 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r135 = 7;
                r136 = locals[2];
                r138 = @intCast(@intFromPtr(@as([*]const u8, "Error: ")));
                r139 = 7;
                r140 = locals[2];
                r141 = -1;
                if (r139 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r138}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r138))))), r139); }
                if (r141 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r140}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r140))))), r141); }
                rt.verve_write(1, "\n", 1);
                r137 = 0;
                block = 21; continue;
            },
            25 => {
                block = 21; continue;
            },
            else => break,
        }
    }
}
