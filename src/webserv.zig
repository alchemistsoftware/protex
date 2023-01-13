//
// Original server code here:
//  https://gitlab.com/Palethorpe/portfolio/-/blob/master/src/self-serve.zig
//

const std = @import("std");
const net = std.net;
const mem = std.mem;
const fs = std.fs;
const io = std.io;

const BUFSIZ = 8196;

const ServeFileError = error {
    RecvHeaderEOF,
    RecvHeaderExceededBuffer,
    HeaderDidNotMatch,
};

fn ServeFile(Stream: *const net.Stream, dir: fs.Dir) !void
{
    var RecvBuf: [BUFSIZ]u8 = undefined;
    var RecvTotal: usize = 0;

    while (Stream.read(RecvBuf[RecvTotal..])) |RecvLen| {
        if (RecvLen == 0)
            return ServeFileError.RecvHeaderEOF;

        RecvTotal += RecvLen;

        if (mem.containsAtLeast(u8, RecvBuf[0..RecvTotal], 1, "\r\n\r\n"))
            break;

        if (RecvTotal >= RecvBuf.len)
            return ServeFileError.RecvHeaderExceededBuffer;
    } else |read_err| {
        return read_err;
    }

    const recv_slice = RecvBuf[0..RecvTotal];
    std.log.info(" <<<\n{s}", .{recv_slice});

    var FilePath: []const u8 = undefined;
    var tok_itr = mem.tokenize(u8, recv_slice, " ");

    if (!mem.eql(u8, tok_itr.next() orelse "", "GET"))
        return ServeFileError.HeaderDidNotMatch;

    const path = tok_itr.next() orelse "";
    if (path[0] != '/')
        return ServeFileError.HeaderDidNotMatch;

    if (mem.eql(u8, path, "/"))
        FilePath = "index"
    else
        FilePath = path[1..];

    if (!mem.startsWith(u8, tok_itr.rest(), "HTTP/1.1\r\n"))
        return ServeFileError.HeaderDidNotMatch;

    var FileExt = fs.path.extension(FilePath);
    var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    const GETs = .{
        .PyIncludePath = "py-include-path",
    };
    const HTTPHead =
        "HTTP/1.1 200 OK\r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: {s}\r\n" ++
        "Content-Length: {}\r\n" ++
        "\r\n";
    const Mimes = .{
        .{".html", "text/html"},
        .{".js", "text/javascript"},
        .{".css", "text/css"},
        .{".map", "application/json"},
        .{".svg", "image/svg+xml"},
        .{".jpg", "image/jpg"},
        .{".png", "image/png"}
    };

    // GET request
    if (mem.eql(u8, FilePath, GETs.PyIncludePath))
    {
        const Mime: []const u8 = "application/json";

        var ResBackBuf: [1024]u8 = undefined;
        var ResFBS = io.fixedBufferStream(&ResBackBuf);
        var W = std.json.writeStream(ResFBS.writer(), 4);

        try W.beginObject();
        try W.objectField("PyIncludePath");
        try W.emitString("./plugins");
        try W.objectField("Entries");
        try W.beginArray();

        var PluginsDir = try fs.cwd().openIterableDir("./data/plugins", .{});
        defer PluginsDir.close();
        var PluginsDirIterator = PluginsDir.iterate();
        while (try PluginsDirIterator.next()) |Entry|
        {
            try W.arrayElem();
            try W.emitString(Entry.name);
        }
        try W.endArray();
        try W.endObject();

        std.log.info(" >>>\n" ++ HTTPHead, .{Mime, ResFBS.getWritten().len});
        try Stream.writer().print(HTTPHead, .{Mime, ResFBS.getWritten().len});
        try Stream.writer().writeAll(ResFBS.getWritten());
    }
    else // Orelse handle serving up a file.
    {
        if (FileExt.len == 0) {
            var path_fbs = io.fixedBufferStream(&path_buf);

            try path_fbs.writer().print("{s}.html", .{FilePath});
            FileExt = ".html";
            FilePath = path_fbs.getWritten();
        }

        std.log.info("Opening {s}", .{FilePath});

        var body_file = dir.openFile(FilePath, .{}) catch |err| {
            const http_404 = "HTTP/1.1 404 Not Found\r\n\r\n404";
            std.log.info(" >>>\n" ++ http_404, .{});
            try Stream.writer().print(http_404, .{});
            return err;
        };
        defer body_file.close();

        const file_len = try body_file.getEndPos();

        var Mime: []const u8 = "text/plain";
        inline for (Mimes) |KV| {
            if (mem.eql(u8, FileExt, KV[0]))
                Mime = KV[1];
        }

        std.log.info(" >>>\n" ++ HTTPHead, .{Mime, file_len});
        try Stream.writer().print(HTTPHead, .{Mime, file_len});

        const zero_iovec = &[0]std.os.iovec_const{};
        var send_total: usize = 0;

        while (true) {
            const send_len = try std.os.sendfile(
                Stream.handle,
                body_file.handle,
                send_total,
                file_len,
                zero_iovec,
                zero_iovec,
                0
            );

            if (send_len == 0)
                break;

            send_total += send_len;
        }
    }
}

pub fn main() !void
{
    var Args = std.process.args();
    const ExeName = Args.next() orelse "self-serve";
    const PublicPath = Args.next() orelse
    {
        std.log.err("Usage: {s} <dir to serve files from>", .{ExeName});
        return;
    };

    var Dir = try fs.cwd().openDir(PublicPath, .{});
    const SelfAddr = try net.Address.resolveIp("127.0.0.1", 1024);
    var Listener = net.StreamServer.init(.{});
    try (&Listener).listen(SelfAddr);

    std.log.info("Listening on {}; press Ctrl-C to exit...", .{SelfAddr});

    while ((&Listener).accept()) |Conn|
    {
        std.log.info("Accepted Connection from: {}", .{Conn.address});

        ServeFile(&Conn.stream, Dir) catch |Err|
        {
            if (@errorReturnTrace()) |Bt| {
                std.log.err("Failed to serve client: {}: {}", .{Err, Bt});
            } else {
                std.log.err("Failed to serve client: {}", .{Err});
            }
        };

        Conn.stream.close();
    } else |Err| {
        return Err;
    }
}
