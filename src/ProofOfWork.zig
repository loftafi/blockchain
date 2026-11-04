const targetBits = if (builtin.is_test) 8 else 24;
/// Check for this many zero bytes at the start of the hash
const targetBytes = targetBits / @bitSizeOf(u8);
const targetBitsHex = std.fmt.comptimePrint("{x}", .{targetBits});

const builtin = @import("builtin");

/// Given the data related to a block, find a nonce that
/// produces a hash that beings with zeros.
pub fn proof_of_work(
    data: []const u8,
    when: i96,
    previous_hash: []const u8,
) error{Unsolvable}!struct { hash: [Block.hash_length]u8, nonce: usize } {
    var hash: [Block.hash_length]u8 = undefined;

    var time_buffer: [@bitSizeOf(i96) / @bitSizeOf(u8)]u8 = undefined;
    std.mem.writeInt(i96, &time_buffer, when, .little);

    var nonce: usize = 0;

    //var data = std.Io.Writer.Allocating.init(gpa);
    next: while (nonce < std.math.maxInt(@TypeOf(nonce))) {
        calculateHash(
            previous_hash,
            data,
            &time_buffer,
            nonce,
            &hash,
        );
        for (hash[0..targetBytes]) |b| {
            if (b != 0) {
                nonce += 1;
                continue :next;
            }
        }
        return .{ .hash = hash, .nonce = nonce };
    }
    return error.Unsolvable;
}

pub fn calculateHash(
    previous_hash: []const u8,
    data: []const u8,
    when: []const u8,
    nonce: usize,
    hash: *[Block.hash_length]u8,
) void {
    var nonce_buffer: [20]u8 = undefined;
    const nonce_value = std.fmt.bufPrint(&nonce_buffer, "{d}", .{nonce}) catch unreachable;

    var h = std.crypto.hash.sha3.Keccak256.init(.{});
    h.update(previous_hash);
    h.update(data);
    h.update(when);
    h.update(targetBitsHex);
    h.update(nonce_value);
    h.final(hash);

    //std.log.info("try data={s} nonce={d} hash={x}", .{ data, nonce, hash[0..8] });
}

test proof_of_work {
    const result = try proof_of_work("block data", 12345, "previous_hash");
    try std.testing.expectEqual(0, result.hash[0]);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Block = @import("root.zig").Blockchain.Block;

// SPDX-FileCopyrightText: 2026 Jay Rhoden.
// SPDX-License-Identifier: MIT
