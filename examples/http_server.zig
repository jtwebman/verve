const std = @import("std");
const rt = @import("verve_runtime.zig");

const VerveStruct_HandlerState = struct {
    id: i64 = 0,
};

fn verve_json_parse_HandlerState(data_ptr: i64, data_len: i64) i64 {
    const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(data_ptr))))));
    const len: usize = @intCast(@as(u64, @bitCast(data_len)));
    const slice = ptr[0..len];
const parsed = std.json.parseFromSlice(VerveStruct_HandlerState, std.heap.page_allocator, slice, .{ .ignore_unknown_fields = true }) catch return rt.makeTagged(1, 0);
    const val = parsed.value;
    const struct_mem = rt.arena_alloc(1 * @sizeOf(i64)) orelse return rt.makeTagged(1, 0);
    const fields = @as([*]i64, @ptrCast(@alignCast(struct_mem)));
    fields[0] = val.id;
    return rt.makeTagged(0, @intCast(@intFromPtr(fields)));
}

fn verve_dispatch_0(handler_id: i64, args: [*]const i64, arg_count: i64) i64 {
    _ = arg_count;
    _ = &args;
    return switch (handler_id) {
        0 => verve_ConnectionHandler_Handle(args[0], args[1]),
        else => rt.makeTagged(1, 0),
    };
}

fn verve_init_dispatch() void {
    rt.ensureProcessCapacity(1);
    rt.dispatch_table[0] = &verve_dispatch_0;
}

fn verve_ConnectionHandler_Handle(param_client_fd: i64, param_request_num: i64) i64 {
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
    var locals: [256]i64 = undefined;
    _ = &locals;
    locals[0] = param_client_fd;
    locals[1] = param_request_num;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = locals[0];
                r1 = 4096;
                r2 = rt.stream_read_bytes(r0, r1);
                r3 = rt.stream_read_bytes_len();
                locals[2] = r2;
                locals[3] = r3;
                r4 = locals[2];
                r5 = locals[3];
                if (r4 == 0) { r6 = 0; } else { const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r4)))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; r6 = @intCast(sl); }
                r7 = 0;
                r8 = if (r6 > r7) @as(i64, 1) else @as(i64, 0);
                block = if (r8 != 0) 1 else 3; continue;
            },
            1 => {
                r9 = locals[2];
                r10 = locals[3];
                r12 = locals[2];
                r13 = locals[3];
                r11 = rt.http_parse_request(r12, r13);
                locals[4] = r11;
                r14 = locals[4];
                r15 = rt.http_req_path(r14);
                r16 = rt.http_req_path_len(r14);
                locals[5] = r15;
                locals[6] = r16;
                r17 = @intCast(@intFromPtr(@as([*]const u8, "")));
                r18 = 0;
                locals[7] = r17;
                locals[8] = r18;
                r19 = locals[5];
                r20 = locals[6];
                r21 = @intCast(@intFromPtr(@as([*]const u8, "/json")));
                r22 = 5;
                r23 = if (rt.strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r19))))), r20, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r21))))), r22)) @as(i64, 1) else @as(i64, 0);
                block = if (r23 != 0) 4 else 5; continue;
            },
            2 => {
                block = 3;
            },
            3 => {
                r111 = locals[0];
                rt.stream_close(r111);
                r112 = 0;
                rt.verve_exit_self();
                r113 = 0;
                r114 = 0;
                return r114;
            },
            4 => {
                r24 = rt.json_build_object();
                locals[9] = r24;
                r25 = locals[9];
                r26 = @intCast(@intFromPtr(@as([*]const u8, "status")));
                r27 = 6;
                r28 = @intCast(@intFromPtr(@as([*]const u8, "ok")));
                r29 = 2;
                r31 = locals[9];
                r32 = @intCast(@intFromPtr(@as([*]const u8, "status")));
                r33 = 6;
                r34 = @intCast(@intFromPtr(@as([*]const u8, "ok")));
                r35 = 2;
                rt.json_build_add_string(r31, r32, r33, r34, r35);
                r30 = 0;
                r36 = locals[9];
                r37 = @intCast(@intFromPtr(@as([*]const u8, "request")));
                r38 = 7;
                r39 = locals[1];
                r41 = locals[9];
                r42 = @intCast(@intFromPtr(@as([*]const u8, "request")));
                r43 = 7;
                r44 = locals[1];
                rt.json_build_add_int(r41, r42, r43, r44);
                r40 = 0;
                r45 = locals[9];
                r46 = rt.json_build_end(r45);
                r47 = rt.json_build_end_len(r45);
                locals[10] = r46;
                locals[11] = r47;
                r48 = 200;
                r49 = @intCast(@intFromPtr(@as([*]const u8, "application/json")));
                r50 = 16;
                r51 = locals[10];
                r52 = locals[11];
                r54 = 200;
                r55 = @intCast(@intFromPtr(@as([*]const u8, "application/json")));
                r56 = 16;
                r57 = locals[10];
                r58 = locals[11];
                r53 = rt.http_build_response(r54, r55, r56, r57, r58);
                r60 = 200;
                r61 = @intCast(@intFromPtr(@as([*]const u8, "application/json")));
                r62 = 16;
                r63 = locals[10];
                r64 = locals[11];
                r59 = rt.http_build_response_len(r60, r61, r62, r63, r64);
                locals[7] = r53;
                locals[8] = r59;
                block = 6; continue;
            },
            5 => {
                r65 = locals[5];
                r66 = locals[6];
                r67 = @intCast(@intFromPtr(@as([*]const u8, "/health")));
                r68 = 7;
                r69 = if (rt.strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r65))))), r66, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r67))))), r68)) @as(i64, 1) else @as(i64, 0);
                block = if (r69 != 0) 7 else 8; continue;
            },
            6 => {
                r104 = locals[0];
                r105 = locals[7];
                r106 = locals[8];
                r108 = locals[0];
                r109 = locals[7];
                r110 = locals[8];
                rt.stream_write(r108, r109, r110);
                r107 = 0;
                block = 3; continue;
            },
            7 => {
                r70 = 200;
                r71 = @intCast(@intFromPtr(@as([*]const u8, "text/plain")));
                r72 = 10;
                r73 = @intCast(@intFromPtr(@as([*]const u8, "ok")));
                r74 = 2;
                r76 = 200;
                r77 = @intCast(@intFromPtr(@as([*]const u8, "text/plain")));
                r78 = 10;
                r79 = @intCast(@intFromPtr(@as([*]const u8, "ok")));
                r80 = 2;
                r75 = rt.http_build_response(r76, r77, r78, r79, r80);
                r82 = 200;
                r83 = @intCast(@intFromPtr(@as([*]const u8, "text/plain")));
                r84 = 10;
                r85 = @intCast(@intFromPtr(@as([*]const u8, "ok")));
                r86 = 2;
                r81 = rt.http_build_response_len(r82, r83, r84, r85, r86);
                locals[7] = r75;
                locals[8] = r81;
                block = 9; continue;
            },
            8 => {
                r87 = 200;
                r88 = @intCast(@intFromPtr(@as([*]const u8, "text/plain")));
                r89 = 10;
                r90 = @intCast(@intFromPtr(@as([*]const u8, "Hello from Verve!")));
                r91 = 17;
                r93 = 200;
                r94 = @intCast(@intFromPtr(@as([*]const u8, "text/plain")));
                r95 = 10;
                r96 = @intCast(@intFromPtr(@as([*]const u8, "Hello from Verve!")));
                r97 = 17;
                r92 = rt.http_build_response(r93, r94, r95, r96, r97);
                r99 = 200;
                r100 = @intCast(@intFromPtr(@as([*]const u8, "text/plain")));
                r101 = 10;
                r102 = @intCast(@intFromPtr(@as([*]const u8, "Hello from Verve!")));
                r103 = 17;
                r98 = rt.http_build_response_len(r99, r100, r101, r102, r103);
                locals[7] = r92;
                locals[8] = r98;
                block = 9; continue;
            },
            9 => {
                block = 6; continue;
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
    var locals: [256]i64 = undefined;
    _ = &locals;
    var block: u32 = 0;
    _ = &block;
    while (true) {
        switch (block) {
            0 => {
                r0 = @intCast(@intFromPtr(@as([*]const u8, "127.0.0.1")));
                r1 = 9;
                r2 = 8080;
                r4 = @intCast(@intFromPtr(@as([*]const u8, "127.0.0.1")));
                r5 = 9;
                r6 = 9;
                r7 = 8080;
                r3 = rt.tcp_listen(r4, r6, r7);
                r8 = rt.getTag(r3);
                r9 = 0;
                r10 = if (r8 == r9) @as(i64, 1) else @as(i64, 0);
                block = if (r10 != 0) 2 else 3; continue;
            },
            1 => {
                r50 = 0;
                std.posix.exit(@intCast(@as(u64, @bitCast(r50))));
            },
            2 => {
                r11 = rt.getTagValue(r3);
                locals[0] = r11;
                r12 = @intCast(@intFromPtr(@as([*]const u8, "HTTP server on http://127.0.0.1:8080 (spawn per connection)")));
                r13 = 59;
                r15 = @intCast(@intFromPtr(@as([*]const u8, "HTTP server on http://127.0.0.1:8080 (spawn per connection)")));
                r16 = 59;
                if (r16 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r15}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r15))))), r16); }
                rt.verve_write(1, "\n", 1);
                r14 = 0;
                r17 = 0;
                locals[1] = r17;
                block = 4; continue;
            },
            3 => {
                r41 = rt.getTag(r3);
                r42 = 1;
                r43 = if (r41 == r42) @as(i64, 1) else @as(i64, 0);
                block = if (r43 != 0) 12 else 13; continue;
            },
            4 => {
                r18 = locals[1];
                r19 = 1000000;
                r20 = if (r18 < r19) @as(i64, 1) else @as(i64, 0);
                block = if (r20 != 0) 5 else 6; continue;
            },
            5 => {
                r21 = locals[0];
                r22 = rt.tcp_accept(r21);
                r23 = rt.getTag(r22);
                r24 = 0;
                r25 = if (r23 == r24) @as(i64, 1) else @as(i64, 0);
                block = if (r25 != 0) 8 else 9; continue;
            },
            6 => {
                r39 = locals[0];
                rt.stream_close(r39);
                r40 = 0;
                block = 1; continue;
            },
            7 => {
                r36 = locals[1];
                r37 = 1;
                r38 = rt.verve_add_checked(r36, r37);
                locals[1] = r38;
                block = 4; continue;
            },
            8 => {
                r26 = rt.getTagValue(r22);
                locals[2] = r26;
                r27 = rt.verve_spawn(0);
                locals[3] = r27;
                r28 = locals[3];
                r29 = locals[2];
                r30 = locals[1];
                { const tell_args = [_]i64{ r29, r30 }; rt.verve_tell(r28, 0, &tell_args, 2); }
                block = 7; continue;
            },
            9 => {
                r31 = rt.getTag(r22);
                r32 = 1;
                r33 = if (r31 == r32) @as(i64, 1) else @as(i64, 0);
                block = if (r33 != 0) 10 else 11; continue;
            },
            10 => {
                r34 = rt.getTagValue(r22);
                locals[4] = r34;
                r35 = locals[1];
                locals[1] = r35;
                block = 7; continue;
            },
            11 => {
                block = 7; continue;
            },
            12 => {
                r44 = rt.getTagValue(r3);
                locals[4] = r44;
                r45 = @intCast(@intFromPtr(@as([*]const u8, "Listen failed")));
                r46 = 13;
                r48 = @intCast(@intFromPtr(@as([*]const u8, "Listen failed")));
                r49 = 13;
                if (r49 == -1) { var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, "{d}", .{r48}) catch "?"; rt.verve_write(1, s.ptr, @intCast(s.len)); } else { rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(r48))))), r49); }
                rt.verve_write(1, "\n", 1);
                r47 = 0;
                block = 1; continue;
            },
            13 => {
                block = 1; continue;
            },
            else => break,
        }
    }
}
