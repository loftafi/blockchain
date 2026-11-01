pub const hash_length = 32;
pub const zero: [hash_length]u8 = @splat(0);

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

    /// A block contains both an aribrary `data` byte sequence,
    /// and the `previous_hash` of the previous block.
    pub const Block = struct {
        data: []const u8,
        when: i96,
        previous_hash: [hash_length]u8,
        hash: [hash_length]u8,

        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            data: []const u8,
            previous_hash: *const [hash_length]u8,
        ) Allocator.Error!Block {
            const now = std.Io.Clock.now(.real, io).toNanoseconds();
            return .{
                .data = try allocator.dupe(u8, data),
                .when = now,
                .previous_hash = previous_hash.*,
                .hash = calculateHash(data, now, previous_hash),
            };
        }

        pub fn deinit(self: *Block, allocator: Allocator) void {
            allocator.free(self.data);
            self.* = undefined;
        }

        fn calculateHash(
            data: []const u8,
            now: i96,
            previous_hash: []const u8,
        ) [hash_length]u8 {
            var h = std.crypto.hash.sha2.Sha256.init(.{});
            h.update(data);
            var buffer: [12]u8 = undefined;
            std.mem.writeInt(i96, &buffer, now, .little);
            h.update(&buffer);
            h.update(previous_hash);
            return h.finalResult();
        }
    };

    /// Load a new `Blockchain` object using the
    /// contents of a blockchain file.
    pub fn load(file: std.Io.File) Allocator.Error!Blockchain {
        _ = file;
        //TODO
        return .{
            .blocks = .empty,
        };
    }

    /// Create or update a blockchain file by writing, or
    /// appending new blocks to the data file.
    pub fn save(self: *Blockchain, file: std.Io.File) Allocator.Error!void {
        _ = self;
        _ = file;
        //TODO:
    }

    /// Verify the hash of each block to confirm no blocks
    /// have been altered or deleted.
    pub fn validate(self: *Blockchain) bool {
        var previous: ?*Block = null;
        for (self.blocks.items) |*block| {
            const hash = Block.calculateHash(block.data, block.when, &block.previous_hash);
            if (!std.mem.eql(u8, &hash, &block.hash)) return false;
            previous = block;
        }
        return true;
    }

    pub fn append(
        self: *Blockchain,
        allocator: Allocator,
        io: std.Io,
        data: []const u8,
    ) Allocator.Error!void {
        if (self.blocks.lastPtr()) |block| {
            try self.blocks.append(allocator, try .init(allocator, io, data, &block.previous_hash));
        } else {
            try self.blocks.append(allocator, try .init(allocator, io, data, &zero));
        }
    }
};

test "block" {
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
        .when = b.blocks.items[1].when,
        .previous_hash = b.blocks.items[1].previous_hash,
    };
    try expectEqual(false, b.validate());
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
