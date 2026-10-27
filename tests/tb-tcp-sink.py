# One-way TCP throughput test over the Thunderbolt/USB4 network link: the receiver side.
# Run it on the M3, bound to its thunderbolt0 address, before the sender starts. Stops after one connection.
# Usage: python3 tb-tcp-sink.py <thunderbolt0 address> <port>
import socket, sys, time
ip, port = sys.argv[1], int(sys.argv[2])
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((ip, port))
srv.listen(1)
srv.settimeout(60)
c, a = srv.accept()
c.settimeout(30)
n = 0
t = None
while True:
    b = c.recv(1 << 20)
    if not b:
        break
    if t is None:
        t = time.time()
    n += len(b)
d = time.time() - t if t else 0
c.sendall(b"k")
print(f"from {a[0]}: received {n/1048576:.0f} MiB in {d:.2f} s = {n*8/d/1e9:.2f} Gbit/s" if d else f"received {n} bytes")
