//
// Original server code here:
//  https://gitlab.com/Palethorpe/portfolio/-/blob/master/src/self-serve.zig
//

const std = @import("std");
const packager = @import("./packager.zig");
const gracie = @import("./gracie.zig");

const net = std.net;
const mem = std.mem;
const fs = std.fs;
const io = std.io;

const allocator = std.mem.Allocator;

const BUFSIZ = 8196;
const DEFAULT_PLUGINS_PATH = "./plugins"; // TODO(cjb): Pass me somewhere

const handle_request_error = error {
    RecvHeaderEOF,
    RecvHeaderExceededBuffer,
    HeaderDidNotMatch,
    BadRequest,
};

const http_response_header = struct
{
    // TODO(cjb): rename me to something that makes sense
    const BasicResponse =
        "HTTP/1.1 {d} {s}\r\n" ++
        "Connection: close\r\n";

    const ContentTypeAndLength =
        "Content-Type: {s}\r\n" ++
        "Content-Length: {}\r\n";

    var BackBuf: [BUFSIZ]u8 = undefined;

    Status: u16,
    Mime: []const u8,
    ContentLength: usize,

    fn StatusDesc(Status: u16) []const u8
    {
        switch(Status)
        {
            200 => return "OK",
            201 => return "Created",
            400 => return "Bad Request",
            404 => return "Not Found",
            else => unreachable,
        }
    }

    pub fn Stringify(Self: http_response_header) ![]const u8
    {
        if (mem.eql(u8, Self.Mime, "basic"))
        {
            return try std.fmt.bufPrint(&BackBuf, BasicResponse ++ "\r\n",
                .{Self.Status, StatusDesc(Self.Status)});
        }

        return try std.fmt.bufPrint(&BackBuf, BasicResponse ++ ContentTypeAndLength ++ "\r\n",
            .{Self.Status, StatusDesc(Self.Status), Self.Mime, Self.ContentLength});
    }
};
fn WriteBasicResponse(Stream: *const net.Stream, Status: u16) !void
{
    var ResponseHeader = http_response_header{.Status=Status, .Mime="basic", .ContentLength=0};
    const ResponseHeaderStr = try ResponseHeader.Stringify();

    std.log.info(" >>>\n{s}", .{ResponseHeaderStr});

    try Stream.writer().writeAll(ResponseHeaderStr);
}

fn WriteResponseWithBody(Stream: *const net.Stream, Status: u16, Content: []u8) !void
{
    var ResponseHeader = http_response_header{.Status=Status, .Mime="application/json",
        .ContentLength=Content.len};
    const ResponseHeaderStr = try ResponseHeader.Stringify();

    std.log.info(" >>>\n{s}{s}", .{ResponseHeaderStr, Content});

    try Stream.writer().writeAll(ResponseHeaderStr);
    try Stream.writer().writeAll(Content);
}

//TODO(cjb): Pass data dir path instead of directory. and fix resolving artifact/config paths.
fn HandleHTTPRequest(Ally: allocator, Stream: *const net.Stream, WebDir: fs.Dir, DataDir: fs.Dir) !void
{
    // Read input stream into buffer.

    var RecvBuf: [BUFSIZ]u8 = undefined;
    var RecvTotal: usize = 0;
    while (Stream.read(RecvBuf[RecvTotal..])) |RecvLen|
    {
        if (RecvLen == 0)
        {
            return handle_request_error.RecvHeaderEOF;
        }

        RecvTotal += RecvLen;

        if (RecvTotal >= RecvBuf.len)
        {
            return handle_request_error.RecvHeaderExceededBuffer;
        }

        if (mem.containsAtLeast(u8, RecvBuf[0..RecvTotal], 1, "\r\n\r\n"))
        {
            break;
        }
    }
    else |ReadErr|
    {
        return ReadErr;
    }
    const RecvSlice = RecvBuf[0..RecvTotal];

    std.log.info(" <<<\n{s}", .{RecvSlice});

//
// Parse request contents.
//

    var TokItr = mem.tokenize(u8, RecvSlice, " ");

    const Method = TokItr.next() orelse "";
    if (!mem.eql(u8, Method, "GET") and
        !mem.eql(u8, Method, "PUT"))
    {
        return handle_request_error.HeaderDidNotMatch;
    }

    var ResourcePath: []const u8 = undefined;
    const TmpResourcePath = TokItr.next() orelse "";
    if (TmpResourcePath[0] != '/')
    {
        return handle_request_error.HeaderDidNotMatch;
    }
    if (mem.eql(u8, TmpResourcePath, "/"))
    {
        ResourcePath = "index";
    }
    else
    {
        ResourcePath = TmpResourcePath[1..];
    }

    // Validate protocol section of the header.

    if (!mem.startsWith(u8, TokItr.rest(), "HTTP/1.1\r\n"))
    {
        return handle_request_error.HeaderDidNotMatch;
    }

    if (mem.eql(u8, Method, "GET"))
    {

        // Get py include path

        if (mem.eql(u8, ResourcePath, "get-py-include-path"))
        {
            var ResponseBackBuf: [BUFSIZ]u8 = undefined;
            var ResponseStream = io.fixedBufferStream(&ResponseBackBuf);

            const MaxJSONDepth = 4;
            var JSONWriter = std.json.writeStream(ResponseStream.writer(), MaxJSONDepth);

            // Write reponse JSON fields

            try JSONWriter.beginObject();
            try JSONWriter.objectField("PyIncludePath");
            try JSONWriter.emitString(DEFAULT_PLUGINS_PATH);
            try JSONWriter.objectField("Entries");
            try JSONWriter.beginArray();

            // Open plugins dir and write it's contents under 'Entries' JSON field.

            var PluginsDir = try DataDir.openIterableDir(DEFAULT_PLUGINS_PATH, .{});
            defer PluginsDir.close();

            var PluginsDirItr = PluginsDir.iterate();
            while (try PluginsDirItr.next()) |Entry|
            {
                try JSONWriter.arrayElem();
                try JSONWriter.emitString(Entry.name);
            }
            try JSONWriter.endArray();
            try JSONWriter.endObject();

            // Send OK header along with whatever JSON was written.

            var ResponseHeader = http_response_header{.Status=200, .Mime="application/json",
                .ContentLength=ResponseStream.getWritten().len};
            const ResponseHeaderStr = try ResponseHeader.Stringify();

            std.log.info(" >>>\n{s}{s}", .{ResponseHeaderStr, ResponseStream.getWritten()});

            try Stream.writer().writeAll(ResponseHeaderStr);
            try Stream.writer().writeAll(ResponseStream.getWritten());
        }

        // Serve file

        else //TODO(Cjb): refactorize me!
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
            const ResponseHeaderStr = try ResponseHeader.Stringify();
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

    // Put extractor out

    else if (mem.eql(u8, ResourcePath, "put-extractor-out"))
    {

        // Get Body of request delimited by \r\n\r\n ( should be a JSON str )

        var BodyItr = mem.split(u8, RecvSlice, "\r\n\r\n");
        _ = BodyItr.next() orelse {
            try WriteBasicResponse(Stream, 400);
            return handle_request_error.BadRequest;
        };
        const ConfigStr = BodyItr.rest();

        // Validate JSON

        if (!std.json.validate(ConfigStr))
        {
            try WriteBasicResponse(Stream, 400);
            return handle_request_error.BadRequest;
        }

        // Parse JSON

        var Parser = std.json.Parser.init(Ally, false);
        defer Parser.deinit();
        const ParseTree = try Parser.parse(ConfigStr);
        const Root = ParseTree.root;

//
// Turn JSON's 'ConfName' field into an absoulute path. Also strip it's extension and use
//  it's stem appended with a '.bin' as the artifact path.
// Then create the artifact with a absolute paths to the configuration and artifact.
//

        // Strip 'ConfName's old extension and append '.bin'.

        const ConfName = Root.Object.get("ConfName") orelse {
            return handle_request_error.BadRequest;
        };
        var StemConfName = fs.path.stem(ConfName.String);
        var PathBuf: [fs.MAX_PATH_BYTES]u8 = undefined;
        var PathStream = io.fixedBufferStream(&PathBuf);
        try PathStream.writer().print("{s}.bin", .{StemConfName});
        const ArtifactPath = PathStream.getWritten();

        // Create artifact file upfront so it's pathname can be resolved by 'realpathAlloc'.

        const ArtifactF = try DataDir.createFile(ArtifactPath, .{});
        ArtifactF.close();

        // Real path to config & artifact file(s)

        var RealArtifactPath = DataDir.realpathAlloc(Ally, ArtifactPath) catch {
            try WriteBasicResponse(Stream, 400);
            return handle_request_error.BadRequest;
        };
        defer Ally.free(RealArtifactPath);
        var RealConfNamePath = try DataDir.realpathAlloc(Ally, ConfName.String);
        defer Ally.free(RealConfNamePath);

        // Create artifact

        packager.CreateArtifact(Ally, RealConfNamePath, RealArtifactPath) catch {
            // TODO switch on err
            try WriteBasicResponse(Stream, 400);
            return handle_request_error.BadRequest;
        };

        // Run extractor

        var G = try gracie.Init(Ally, RealArtifactPath);
        defer G.Deinit();
        const Text = Root.Object.get("Text") orelse {
            return handle_request_error.BadRequest;
        };
        const ExtractorOut = try G.Extract(Text.String);

        // Write response

        var ResponseHeader = http_response_header{.Status=200, .Mime="application/json",
            .ContentLength=ExtractorOut.len};
        const ResponseHeaderStr = try ResponseHeader.Stringify();

        std.log.info(" >>>\n{s}{s}", .{ResponseHeaderStr, ExtractorOut});

        try Stream.writer().writeAll(ResponseHeaderStr);
        try Stream.writer().writeAll(ExtractorOut);
    }
    else if (mem.eql(u8, Method, "PUT"))
    {

        // Put config

        if (mem.eql(u8, ResourcePath, "put-config"))
        {

            // Get Body of request delimited by \r\n\r\n ( should be a JSON str )

            var BodyItr = mem.split(u8, RecvSlice, "\r\n\r\n");
            _ = BodyItr.next() orelse {
                try WriteBasicResponse(Stream, 400);
                return handle_request_error.BadRequest;
            };
            const ConfigStr = BodyItr.rest();

            // Verify writing a valid json string.

            if (std.json.validate(ConfigStr))
            {

                try WriteBasicResponse(Stream, 400);
                return handle_request_error.BadRequest;
            }

            // Retrieve 'ConfName' from JSON.

            var Parser = std.json.Parser.init(Ally, false);
            const ParseTree = try Parser.parse(ConfigStr);
            const Root = ParseTree.root;
            const ConfName = Root.Object.get("ConfName") orelse {
                try WriteBasicResponse(Stream, 400);
                return handle_request_error.BadRequest;
            };

            // Write entire JSON str as 'ConfName'.

            const ConfF = try DataDir.createFile(ConfName.String, .{});
            defer ConfF.close();
            try std.json.stringify(Root, .{}, ConfF.writer());

            // Write basic 201 ( created ) response

            try WriteBasicResponse(Stream, 201);
        }
    }

    // Handle unknown request method with a 404

    else
    {
        const HTTP404 = "HTTP/1.1 404 Not Found\r\n\r\n404";
        std.log.info(" >>>\n" ++ HTTP404, .{});
        try Stream.writer().print(HTTP404, .{});
    }
}

fn Usage(ExeName: []const u8) void
{
    std.log.err("Usage: {s} <dir to serve files from> <dir to write data to>", .{ExeName});
}

pub fn main() !void
{
    var Args = std.process.args();
    const ExeName = Args.next() orelse "serverexe";
    const PublicPath = Args.next() orelse { Usage(ExeName); return; };
    const DataPath = Args.next() orelse { Usage(ExeName); return; };

    var WebDir = try fs.cwd().openDir(PublicPath, .{});
    var DataDir = try fs.cwd().openDir(DataPath, .{});

    const SelfAddr = try net.Address.resolveIp("127.0.0.1", 1024);
    var Listener = net.StreamServer.init(.{.reuse_address=true});
    try (&Listener).listen(SelfAddr);

    var Ally = std.heap.page_allocator;

    std.log.info("Listening on {}; press Ctrl-C to exit...", .{SelfAddr});

    while ((&Listener).accept()) |Conn|
    {
        std.log.info("Accepted Connection from: {}", .{Conn.address});
        HandleHTTPRequest(Ally, &Conn.stream, WebDir, DataDir) catch |Err|
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
