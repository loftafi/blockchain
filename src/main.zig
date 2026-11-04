const std = @import("std");
const Io = std.Io;

const blockchain = @import("blockchain");

pub fn main(init: std.process.Init) !void {
    var iter = init.minimal.args.iterate();
    _ = iter.skip();

    var filename: ?[]const u8 = null;

    if (iter.next()) |f| {
        filename = try init.arena.allocator().dupe(u8, f);
    } else {
        std.log.err("usage: blockchain filename data", .{});
        return;
    }

    if (iter.next()) |data| {
        var b: blockchain.Blockchain = .empty;
        defer b.deinit(init.gpa);
        if (std.Io.Dir.cwd().openFile(init.io, filename.?, .{ .mode = .read_only })) |*file| {
            b = try blockchain.Blockchain.load(init.gpa, init.io, file);
            defer file.close(init.io);
        } else |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.debug("existing file {s} not found. beginning new file.", .{filename.?});
                },
                else => return err,
            }
        }

        try b.append(init.gpa, init.io, data);

        if (std.Io.Dir.cwd().createFile(init.io, filename.?, .{})) |*file| {
            defer file.close(init.io);
            std.log.debug("update file: {s}", .{filename.?});
            try b.save(init.io, file);
            for (b.blocks.items) |block| {
                std.log.info("{d} {x} {x}... {s}", .{
                    block.when,
                    block.nonce,
                    block.hash[0..8],
                    block.data,
                });
            }
        } else |err| {
            return err;
        }
    } else std.log.err("usage: zig build run -- filename data", .{});
}

// SPDX-FileCopyrightText: 2026 Jay Rhoden.
// SPDX-License-Identifier: MIT
