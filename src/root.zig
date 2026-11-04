/// An ordered list of blocks. Each block is hashed along with
/// the `previous_hash` of the previous block to verify the integrity
/// and sequence of the previous blocks.
pub const Blockchain = struct {
    blocks: std.ArrayList(Block),

    pub const empty: Blockchain = .{
        .blocks = .empty,
    };

    pub fn deinit(self: *Blockchain, allocator: Allocator) void {
        for (self.blocks.items) |*block| {
            block.deinit(allocator);
        }
        self.blocks.deinit(allocator);
        self.* = undefined;
    }

    pub fn append(
        self: *Blockchain,
        allocator: Allocator,
        io: std.Io,
        data: []const u8,
    ) (error{Unsolvable} || Allocator.Error)!void {
        if (self.blocks.lastPtr()) |block| {
            try self.blocks.append(allocator, try .init(allocator, io, data, &block.hash));
        } else {
            try self.blocks.append(allocator, try .init(allocator, io, data, null));
        }
    }

    /// A block contains both an aribrary `data` byte sequence,
    /// and the `previous_hash` of the previous block.
    pub const Block = struct {
        pub const hash_length = std.crypto.hash.sha3.Keccak256.digest_length;
        pub const zero: [hash_length]u8 = @splat(0);

        data: []const u8,
        when: i96,
        hash: [hash_length]u8,
        nonce: usize,

        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            data: []const u8,
            previous_hash: ?*const [hash_length]u8,
        ) (error{Unsolvable} || Allocator.Error)!Block {
            const now = std.Io.Clock.now(.real, io).toNanoseconds();
            const result = try proofOfWork(data, now, previous_hash orelse &zero);
            return .{
                .data = try allocator.dupe(u8, data),
                .when = now,
                .hash = result.hash,
                .nonce = result.nonce,
            };
        }

        pub fn deinit(self: *Block, allocator: Allocator) void {
            allocator.free(self.data);
            self.* = undefined;
        }

        fn calculateHash(
            data: []const u8,
            now: i96,
            nonce: usize,
            previous_hash: []const u8,
        ) [hash_length]u8 {
            var time_buffer: [@bitSizeOf(i96) / @bitSizeOf(u8)]u8 = undefined;
            std.mem.writeInt(i96, &time_buffer, now, .little);

            var hash: [Block.hash_length]u8 = undefined;
            ProofOfWork.calculateHash(
                previous_hash,
                data,
                &time_buffer,
                nonce,
                &hash,
            );
            return hash;
        }
    };

    /// Load a new `Blockchain` object using the
    /// contents of a blockchain file.
    pub fn load(allocator: std.mem.Allocator, io: std.Io, file: *const std.Io.File) (std.Io.File.ReadStreamingError || std.Io.Reader.Error || Allocator.Error || Error)!Blockchain {
        var blocks: std.ArrayList(Block) = .empty;
        errdefer blocks.deinit(allocator);

        var buffer: [5000]u8 = undefined;
        var in = file.readerStreaming(io, &buffer);

        var header: [file_header.len]u8 = undefined;
        try in.interface.readSliceAll(&header);
        if (!std.mem.eql(u8, &header, file_header)) return Error.InvalidFile;

        if (try in.interface.takeByte() != 1) return Error.InvalidFileVersion;

        while (true) {
            const len = try in.interface.takeInt(usize, .big);
            if (len == 0) break;
            const data = try allocator.alloc(u8, len);
            errdefer allocator.free(data);
            try in.interface.readSliceAll(data);
            const when = try in.interface.takeInt(i96, .big);
            const nonce = try in.interface.takeInt(usize, .big);
            var hash: [Block.hash_length]u8 = undefined;
            try in.interface.readSliceAll(&hash);
            try blocks.append(allocator, .{
                .data = data,
                .when = when,
                .hash = hash,
                .nonce = nonce,
            });
        }
        std.log.debug("loaded {d} blocks.", .{blocks.items.len});

        return .{
            .blocks = blocks,
        };
    }

    pub const file_header = "BLKCNL";

    /// Create or update a blockchain file by writing, or
    /// appending new blocks to the data file.
    pub fn save(
        self: *Blockchain,
        io: std.Io,
        file: *const std.Io.File,
    ) (std.Io.Writer.Error || Allocator.Error)!void {
        var buffer: [5000]u8 = undefined;
        var out = file.writerStreaming(io, &buffer);
        try out.interface.writeAll(file_header);
        try out.interface.writeByte(1);
        for (self.blocks.items) |*block| {
            try out.interface.writeInt(usize, block.data.len, .big);
            try out.interface.writeAll(block.data);
            try out.interface.writeInt(i96, block.when, .big);
            try out.interface.writeInt(usize, block.nonce, .big);
            try out.interface.writeAll(&block.hash);
        }
        try out.interface.writeInt(usize, 0, .big);
        try out.interface.flush();
        std.log.debug("wrote {d} blocks.", .{self.blocks.items.len});
    }

    /// Verify the hash of each block to confirm no blocks
    /// have been altered or deleted.
    pub fn validate(self: *Blockchain) bool {
        var previous: ?*Block = null;
        for (self.blocks.items) |*block| {
            const hash = Block.calculateHash(
                block.data,
                block.when,
                block.nonce,
                if (previous) |p| &p.hash else &Block.zero,
            );
            if (!std.mem.eql(u8, &hash, &block.hash)) return false;
            previous = block;
        }
        return true;
    }
};

pub const Error = error{
    InvalidFile,
    InvalidFileVersion,
};

test "block_validate" {
    var b: Blockchain = .empty;
    defer b.deinit(std.testing.allocator);

    try b.append(std.testing.allocator, std.testing.io, "abc");
    try b.append(std.testing.allocator, std.testing.io, "def");

    try expectEqual(2, b.blocks.items.len);
    try expectEqualStrings("abc", b.blocks.items[0].data);
    try expectEqualStrings("def", b.blocks.items[1].data);

    try expectEqual(true, b.validate());
    var data = @constCast(b.blocks.items[1].data);
    data[0] = '.';
    b.blocks.items[1] = .{
        .data = data,
        .hash = b.blocks.items[1].hash,
        .nonce = b.blocks.items[1].nonce,
        .when = b.blocks.items[1].when,
    };
    try expectEqual(false, b.validate());
}

test "block_save" {
    var b: Blockchain = .empty;
    defer b.deinit(std.testing.allocator);

    try b.append(std.testing.allocator, std.testing.io, "123");
    try b.append(std.testing.allocator, std.testing.io, "abcd");

    var dir = std.testing.tmpDir(.{});
    var file = try dir.dir.createFile(std.testing.io, "bc", .{
        .read = true,
        .truncate = true,
    });
    defer file.close(std.testing.io);

    try b.save(std.testing.io, &file);
    try file.sync(std.testing.io);
    file.close(std.testing.io);

    file = try dir.dir.openFile(std.testing.io, "bc", .{});
    var b2 = try Blockchain.load(std.testing.allocator, std.testing.io, &file);
    defer b2.deinit(std.testing.allocator);

    try expectEqual(2, b2.blocks.items.len);
    try expectEqualStrings("123", b2.blocks.items[0].data);
    try expectEqualStrings("abcd", b2.blocks.items[1].data);
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

pub const ProofOfWork = @import("ProofOfWork.zig");
pub const proofOfWork = ProofOfWork.proofOfWork;

test {
    _ = @import("ProofOfWork.zig");
}

// SPDX-FileCopyrightText: 2026 Jay Rhoden.
// SPDX-License-Identifier: MIT
