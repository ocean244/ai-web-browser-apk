import http.server
import json
import signal
import socket
import socketserver
import sys
import threading

start_port = int(sys.argv[1])
out_path = sys.argv[2]
port_out_path = sys.argv[3] if len(sys.argv) > 3 else ""


class BoundThreadingHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address, RequestHandlerClass, bound_sock):
        self.socket = bound_sock
        self.server_address = server_address
        socketserver.BaseServer.__init__(self, server_address, RequestHandlerClass)
        self.server_activate()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(raw)
        body = json.dumps({
            "id": "payload-ok",
            "choices": [{"message": {"role": "assistant", "content": "pong-ok"}}]
        }).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


bound_sock = None
chosen_port = None
candidates = [start_port] if start_port != 8080 else list(range(18080, 18201))
if start_port not in candidates:
    candidates = [start_port] + list(range(18080, 18201))

for p in candidates:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", p))
        s.listen(16)
        bound_sock = s
        chosen_port = p
        break
    except OSError:
        s.close()

if bound_sock is None or chosen_port is None:
    raise OSError(f"No free port found starting from {start_port}")

if port_out_path:
    with open(port_out_path, "w", encoding="utf-8") as pf:
        pf.write(str(chosen_port))

srv = BoundThreadingHTTPServer(("127.0.0.1", chosen_port), Handler, bound_sock)
stop_event = threading.Event()


def handle_sig(signum, frame):
    stop_event.set()
    threading.Thread(target=srv.shutdown, daemon=True).start()


signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)

t = threading.Thread(target=srv.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
t.start()
stop_event.wait()
t.join(timeout=2)
srv.server_close()
