# One-way TCP throughput test over the Thunderbolt/USB4 network link: the sender side.
# Run it on the machine that connects (the Mac). The receiver (tb-tcp-sink.py) runs on the M3.
# Usage: python3 -I tb-tcp-send.py <receiver address> <port> <MiB to send> <local address to bind>
import socket, sys, time
host, port, mb, src = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
s = socket.socket()
s.bind((src, 0))
s.settimeout(20)
s.connect((host, port))
buf = b"\0" * (1 << 20)
t = time.time()
for _ in range(mb):
    s.sendall(buf)
s.shutdown(socket.SHUT_WR)
try:
    s.recv(1)
except Exception:
    pass
d = time.time() - t
print(f"sent {mb} MiB in {d:.2f} s = {mb*1.048576*8/d/1000:.2f} Gbit/s")
