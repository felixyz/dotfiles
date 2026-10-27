# Bridges a sandbox to the MCP endpoint of tidewave-cli,
# and refuses everything else on its port, including its file API.
# See decisions/0019.
import asyncio
import json
import os
import re
import sys

UPSTREAM_HOST = "127.0.0.1"
MAX_HEAD = 16 * 1024
MAX_BODY = 1024 * 1024

TARGET = re.compile(rb"/socket/mcp-remote-client\?sessionId=[A-Za-z0-9_-]+")
HTTP_METHODS = {b"GET", b"POST", b"DELETE"}
REFUSED_HEADERS = {b"transfer-encoding", b"upgrade", b"expect"}
RPC_METHODS = {
    "initialize",
    "notifications/initialized",
    "notifications/cancelled",
    "notifications/roots/list_changed",
    "ping",
    "server/discover",
    "tools/list",
    "tools/call",
}
TOOLS = {
    "browser_eval",
    "create_design_canvas",
    "restart_app_server",
    "task_create",
    "task_get",
    "task_list",
    "task_update",
}


class Refused(Exception):
    def __init__(self, reason, rpc_id=None):
        super().__init__(reason)
        self.rpc_id = rpc_id


def log(message):
    print(f"tidewave-mcp-filter: {message}", file=sys.stderr, flush=True)


# json.loads keeps the last of two duplicate keys.
# A server that keeps the first would see a different tool name.
def no_duplicate_keys(pairs):
    keys = [key for key, _ in pairs]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate key")
    return dict(pairs)


def parse_head(head):
    # Some servers end a header line at a bare LF and this parser does not,
    # so a header hidden that way would reach tidewave-cli unchecked.
    if head.count(b"\r") != head.count(b"\r\n") or head.count(b"\n") != head.count(b"\r\n"):
        raise Refused("bare CR or LF in the request head")
    request_line, *header_lines = head[:-4].split(b"\r\n")
    parts = request_line.split(b" ")
    if len(parts) != 3:
        raise Refused("malformed request line")
    method, target, version = parts
    if method not in HTTP_METHODS or version != b"HTTP/1.1":
        raise Refused(f"{method.decode(errors='replace')} {version.decode(errors='replace')}")
    if not TARGET.fullmatch(target):
        raise Refused(f"path {target[:200].decode(errors='replace')}")
    lengths = []
    for line in header_lines:
        name, sep, value = line.partition(b":")
        if not sep or not name or name != name.strip() or line[:1] in (b" ", b"\t"):
            raise Refused("malformed header")
        name = name.lower()
        if name in REFUSED_HEADERS:
            raise Refused(f"header {name.decode()}")
        if name == b"content-length":
            lengths.append(value.strip())
    if len(lengths) > 1 or (lengths and not lengths[0].isdigit()):
        raise Refused("bad Content-Length")
    length = int(lengths[0]) if lengths else 0
    if length > MAX_BODY:
        raise Refused("body too large")
    if method == b"POST" and not lengths:
        raise Refused("POST without Content-Length")
    if method != b"POST" and length:
        raise Refused(f"{method.decode()} with a body")
    return length


# The agent can swap a symlink in after this check. decisions/0019 accepts that.
def check_canvas_path(path, project_dir, rpc_id):
    if not isinstance(path, str) or not os.path.isabs(path):
        raise Refused("create_design_canvas needs an absolute path", rpc_id)
    if os.path.realpath(path) != path or not path.startswith(project_dir + "/"):
        raise Refused(f"create_design_canvas path {path!r} is outside {project_dir} or goes through a symlink", rpc_id)


def check_body(body, project_dir):
    try:
        # json.loads also accepts UTF-16 and UTF-32 bytes.
        message = json.loads(body.decode("utf-8"), object_pairs_hook=no_duplicate_keys)
    except ValueError:
        raise Refused("body is not a JSON object with unique keys")
    if not isinstance(message, dict):
        raise Refused("body is not a single JSON-RPC message")
    rpc_id = message.get("id")
    if "method" not in message:
        if "id" in message and ("result" in message or "error" in message):
            return
        raise Refused("JSON-RPC message without a method", rpc_id)
    method = message["method"]
    if method not in RPC_METHODS:
        raise Refused(f"JSON-RPC method {method!r}", rpc_id)
    if method != "tools/call":
        return
    params = message.get("params")
    if not isinstance(params, dict):
        raise Refused("tools/call without params", rpc_id)
    tool = params.get("name")
    if tool not in TOOLS:
        raise Refused(f"tool {tool!r}", rpc_id)
    if tool == "create_design_canvas":
        arguments = params.get("arguments")
        if not isinstance(arguments, dict):
            raise Refused("create_design_canvas without arguments", rpc_id)
        check_canvas_path(arguments.get("path"), project_dir, rpc_id)


async def read_request(reader, project_dir):
    try:
        head = await reader.readuntil(b"\r\n\r\n")
    except asyncio.IncompleteReadError as error:
        if error.partial:
            raise Refused("connection closed inside a request head")
        return None
    except asyncio.LimitOverrunError:
        raise Refused("request head too large")
    length = parse_head(head)
    body = await reader.readexactly(length) if length else b""
    if length:
        check_body(body, project_dir)
    return head + body


async def forward_requests(reader, upstream, project_dir):
    while (request := await read_request(reader, project_dir)) is not None:
        upstream.write(request)
        await upstream.drain()


async def copy(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except ConnectionError:
        pass


def refusal_response(error):
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": error.rpc_id,
        "error": {"code": -32600, "message": f"Refused by the sandbox: {error}"},
    }).encode()
    return (
        b"HTTP/1.1 403 Forbidden\r\n"
        b"Content-Type: application/json\r\n"
        b"Content-Length: " + str(len(body)).encode() + b"\r\n"
        b"Connection: close\r\n\r\n" + body
    )


async def handle(client_reader, client_writer, upstream_port, project_dir):
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection(UPSTREAM_HOST, upstream_port)
    except OSError as error:
        log(f"cannot reach {UPSTREAM_HOST}:{upstream_port}: {error}")
        client_writer.close()
        return
    forward = asyncio.create_task(forward_requests(client_reader, upstream_writer, project_dir))
    pump = asyncio.create_task(copy(upstream_reader, client_writer))
    try:
        await asyncio.wait({forward, pump}, return_when=asyncio.FIRST_COMPLETED)
        if forward.done():
            error = forward.exception()
            if isinstance(error, Refused):
                pump.cancel()
                log(f"refused {error}")
                client_writer.write(refusal_response(error))
                await client_writer.drain()
            elif error is None:
                upstream_writer.write_eof()
                await pump
    except (ConnectionError, OSError):
        pass
    finally:
        forward.cancel()
        pump.cancel()
        upstream_writer.close()
        client_writer.close()


async def main():
    if len(sys.argv) != 4:
        sys.exit("usage: tidewave-mcp-filter <listen-socket> <upstream-port> <project-dir>")
    socket_path, upstream_port, project_dir = sys.argv[1], int(sys.argv[2]), os.path.realpath(sys.argv[3])
    server = await asyncio.start_unix_server(
        lambda r, w: handle(r, w, upstream_port, project_dir),
        path=socket_path,
        limit=MAX_HEAD,
    )
    async with server:
        await server.serve_forever()


asyncio.run(main())
