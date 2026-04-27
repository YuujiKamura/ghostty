//! The datastruct package contains data structures or anything closely
//! related to data structures.

const blocking_queue = @import("blocking_queue.zig");
const bounded_mailbox = @import("bounded_mailbox.zig");
const cache_table = @import("cache_table.zig");
const circ_buf = @import("circ_buf.zig");
const intrusive_linked_list = @import("intrusive_linked_list.zig");
const segmented_pool = @import("segmented_pool.zig");
const split_tree = @import("split_tree.zig");

pub const lru = @import("lru.zig");
pub const BlockingQueue = blocking_queue.BlockingQueue;
pub const BoundedMailbox = bounded_mailbox.BoundedMailbox;
pub const ShutdownToken = bounded_mailbox.ShutdownToken;
/// Phase-2 sentinel for `pushUntilShutdown` — see #232. Use only when no
/// App-scoped shutdown bus is wired in yet.
pub const bounded_mailbox_never_signal = &bounded_mailbox.never_signal;
pub const CacheTable = cache_table.CacheTable;
pub const CircBuf = circ_buf.CircBuf;
pub const IntrusiveDoublyLinkedList = intrusive_linked_list.DoublyLinkedList;
pub const MessageData = @import("message_data.zig").MessageData;
pub const SegmentedPool = segmented_pool.SegmentedPool;
pub const SplitTree = split_tree.SplitTree;

test {
    @import("std").testing.refAllDecls(@This());

    _ = @import("comparison.zig");
}
