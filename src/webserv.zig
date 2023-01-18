//
// Original server code here:
//  https://gitlab.com/Palethorpe/portfolio/-/blob/master/src/self-serve.zig
//

const std = @import("std");
const packager = @import("./packager.zig");

const net = std.net;
const mem = std.mem;
const fs = std.fs;
const io = std.io;

const BUFSIZ = 8196;

const handle_request_error = error {
    RecvHeaderEOF,
    RecvHeaderExceededBuffer,
    HeaderDidNotMatch,
    NoBody,
    BadBody,
};

fn IsValidRequestMethod(Method: []const u8) bool
{
    return (mem.eql(u8, Method, "GET") or mem.eql(u8, Method, "PUT"));
}

const http_response_header = struct
{
    const BasicResponse =
        "HTTP/1.1 {} OK\r\n" ++
        "Connection: close\r\n";

    const ContentTypeAndLength =
        "Content-Type: {s}\r\n" ++
        "Content-Length: {}\r\n";

    var HeaderBuf: [1024]u8 = undefined;

    Status: u16,
    Mime: []const u8,
    ContentLength: usize,

    pub fn StringifyWithContent(Self: http_response_header) ![]const u8
    {
        return try std.fmt.bufPrint(&HeaderBuf, BasicResponse ++ ContentTypeAndLength ++ "\r\n",
            .{Self.Status, Self.Mime, Self.ContentLength});
    }

    pub fn StringifyBasic(Self: http_response_header) ![]const u8
    {
        return try std.fmt.bufPrint(&HeaderBuf, BasicResponse ++ "\r\n", .{Self.Status});
    }
};

fn HandleRequest(Stream: *const net.Stream, WebDir: fs.Dir, DataDir: fs.Dir) !void
{
    const GETs = .{
        .PyIncludePath = "get-py-include-path",
        .ExtractorOut = "get-extractor-out",
    };
    const PUTs = .{
        .Config = "put-config",
    };

    var RecvBuf: [BUFSIZ]u8 = undefined;
    var RecvTotal: usize = 0;
    while (Stream.read(RecvBuf[RecvTotal..])) |RecvLen|
    {
        if (RecvLen == 0)
            return handle_request_error.RecvHeaderEOF;
        RecvTotal += RecvLen;
        if (mem.containsAtLeast(u8, RecvBuf[0..RecvTotal], 1, "\r\n\r\n"))
            break;
        if (RecvTotal >= RecvBuf.len)
            return handle_request_error.RecvHeaderExceededBuffer;
    }
    else |read_err|
        return read_err;

    const RecvSlice = RecvBuf[0..RecvTotal];
    std.log.info(" <<<\n{s}", .{RecvSlice});

    var ResourcePath: []const u8 = undefined;
    var TokItr = mem.tokenize(u8, RecvSlice, " ");

    const Method = TokItr.next() orelse "";
    if (!IsValidRequestMethod(Method))
        return handle_request_error.HeaderDidNotMatch;

    // Parse resource path
    const Path = TokItr.next() orelse "";
    if (Path[0] != '/')
        return handle_request_error.HeaderDidNotMatch;

    if (mem.eql(u8, Path, "/"))
        ResourcePath = "index"
    else
        ResourcePath = Path[1..];

    if (!mem.startsWith(u8, TokItr.rest(), "HTTP/1.1\r\n"))
        return handle_request_error.HeaderDidNotMatch;

    if (mem.eql(u8, ResourcePath, GETs.PyIncludePath))
    {
        var ResBackBuf: [1024]u8 = undefined;
        var ResFBS = io.fixedBufferStream(&ResBackBuf);
        var W = std.json.writeStream(ResFBS.writer(), 4);

        try W.beginObject();
        try W.objectField("PyIncludePath");
        try W.emitString("./plugins");
        try W.objectField("Entries");
        try W.beginArray();

        var PluginsDir = try DataDir.openIterableDir("./plugins", .{});
        defer PluginsDir.close();
        var PluginsDirIterator = PluginsDir.iterate();
        while (try PluginsDirIterator.next()) |Entry|
        {
            try W.arrayElem();
            try W.emitString(Entry.name);
        }
        try W.endArray();
        try W.endObject();

        var ResponseHeader = http_response_header{.Status=200, .Mime="application/json",
            .ContentLength = ResFBS.getWritten().len};
        const ResponseHeaderStr = try ResponseHeader.StringifyWithContent();
        std.log.info(" >>>\n{s}", .{ResponseHeaderStr});
        try Stream.writer().writeAll(ResponseHeaderStr);
        try Stream.writer().writeAll(ResFBS.getWritten());
    }
//    else if (mem.eql(u8, ResourcePath, GETs.ExtractorOut))
//    {
//        var ResponseHeader = http_response_header{.Status=200, .Mime="basic", .ContentLength=0};
//        const ResponseHeaderStr = try ResponseHeader.StringifyBasic();
//        std.log.info(" >>>\n{s}", .{ResponseHeaderStr});
//        try Stream.writer().writeAll(ResponseHeaderStr);
//    }
    else if (mem.eql(u8, ResourcePath, PUTs.Config))
    {

        var BodyItr = mem.split(u8, RecvSlice, "\r\n\r\n");
        _ = BodyItr.next() orelse {
            var ResponseHeader = http_response_header{.Status=400, .Mime="basic",
                .ContentLength=0};
            const ResponseHeaderStr = try ResponseHeader.StringifyBasic();
            std.log.info(" >>>\n{s}", .{ResponseHeaderStr});
            return handle_request_error.NoBody;
        };
        const ConfigStr = BodyItr.rest();

        var ResBackBuf: [BUFSIZ]u8 = undefined;
        var ResFBA = std.heap.FixedBufferAllocator.init(&ResBackBuf);
        var Parser = std.json.Parser.init(ResFBA.allocator(), false);

        // Verify writing a valid json string
        if (std.json.validate(ConfigStr))
        {
            const ParseTree = try Parser.parse(ConfigStr);
            const Root = ParseTree.root;
            const ConfName = Root.Object.get("ConfName") orelse {
                return handle_request_error.BadBody;
            };

            // Write configuration
            const ConfF = try DataDir.createFile(ConfName.String, .{});
            defer ConfF.close();
            try std.json.stringify(Root, .{}, ConfF.writer());
        }
        else
        {
            var ResponseHeader = http_response_header{.Status=400, .Mime="basic",
                .ContentLength=0};
            const ResponseHeaderStr = try ResponseHeader.StringifyBasic();
            std.log.info(" >>>\n{s}", .{ResponseHeaderStr});
            try Stream.writer().writeAll(ResponseHeaderStr);
            return handle_request_error.BadBody;
        }

        var ResponseHeader = http_response_header{.Status=201, .Mime="basic",
            .ContentLength=0};
        const ResponseHeaderStr = try ResponseHeader.StringifyBasic();
        std.log.info(" >>>\n{s}", .{ResponseHeaderStr});
        try Stream.writer().writeAll(ResponseHeaderStr);
    }
    else // Orelse handle serving up a file.
    {
        const Mimes = .{
            .{".html", "text/html"},
            .{".js", "text/javascript"},
            .{".css", "text/css"},
            .{".map", "application/json"},
            .{".svg", "image/svg+xml"},
            .{".jpg", "image/jpg"},
            .{".png", "image/png"}
        };

        var PathBuf: [fs.MAX_PATH_BYTES]u8 = undefined;
        var FileExt = fs.path.extension(ResourcePath);
        if (FileExt.len == 0) {
            var path_fbs = io.fixedBufferStream(&PathBuf);

            try path_fbs.writer().print("{s}.html", .{ResourcePath});
            FileExt = ".html";
            ResourcePath = path_fbs.getWritten();
        }

        std.log.info("Opening {s}", .{ResourcePath});

        var body_file = WebDir.openFile(ResourcePath, .{}) catch |err| {
            const http_404 = "HTTP/1.1 404 Not Found\r\n\r\n404";
            std.log.info(" >>>\n" ++ http_404, .{});
            try Stream.writer().print(http_404, .{});
            return err;
        };
        defer body_file.close();

        const FileLen = try body_file.getEndPos();

        // Try to determine mime type from file extension
        var Mime: []const u8 = "text/plain";
        inline for (Mimes) |KV|
        {
            if (mem.eql(u8, FileExt, KV[0]))
                Mime = KV[1];
        }

        const ResponseHeader = http_response_header{.Status=200, .Mime=Mime,
            .ContentLength = FileLen};
        const ResponseHeaderStr = try ResponseHeader.StringifyWithContent();
        std.log.info(" >>>\n{s}", .{ResponseHeaderStr});
        try Stream.writer().writeAll(ResponseHeaderStr);

        const zero_iovec = &[0]std.os.iovec_const{};
        var send_total: usize = 0;

        while (true) {
            const send_len = try std.os.sendfile(
                Stream.handle,
                body_file.handle,
                send_total,
                FileLen,
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

fn PrintUsage(ExeName: []const u8) void
{
    std.log.err("Usage: {s} <dir to serve files from> <dir to write data to>", .{ExeName});
}

pub fn main() !void
{
    var Args = std.process.args();
    const ExeName = Args.next() orelse "serverexe";
    const PublicPath = Args.next() orelse { PrintUsage(ExeName); return; };
    const DataPath = Args.next() orelse { PrintUsage(ExeName); return; };

    var WebDir = try fs.cwd().openDir(PublicPath, .{});
    var DataDir = try fs.cwd().openDir(DataPath, .{});

    const SelfAddr = try net.Address.resolveIp("127.0.0.1", 1024);
    var Listener = net.StreamServer.init(.{.reuse_address=true});
    try (&Listener).listen(SelfAddr);

    std.log.info("Listening on {}; press Ctrl-C to exit...", .{SelfAddr});

    while ((&Listener).accept()) |Conn|
    {
        std.log.info("Accepted Connection from: {}", .{Conn.address});
        HandleRequest(&Conn.stream, WebDir, DataDir) catch |Err|
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
