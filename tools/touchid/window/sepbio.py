#!/usr/bin/env python3
"""Minimal client for the Apple SEP biometric device (/dev/sep-bio), for stage 3b tests.

It talks to the kernel ABI in include/uapi/linux/apple-sep.h directly, so the first enrol and
verify do not depend on libfprint, fprintd or PAM. Nothing biometric crosses this interface:
only operation, stage, status and an opaque identity UUID. The verify token is never printed.

  sepbio.py info                      sensor present, enrolled count, capacity, stages
  sepbio.py list                      identity UUIDs and host labels
  sepbio.py enrol [LABEL]             enrol one finger (prompts come from the enclave)
  sepbio.py verify                    one match attempt
  sepbio.py cancel                    cancel a running enrol or verify
  sepbio.py delete UUID               delete one identity
  sepbio.py delete-all --yes          delete every identity

Needs root (the device is root-only). The first open activates Touch ID and can take a few seconds.
Exit codes: 0 ok, 1 failed or no match, 2 usage, 3 device error.
"""
import errno
import fcntl
import os
import secrets
import struct
import sys
import time

DEV = os.environ.get("SEPBIO_DEV", "/dev/sep-bio")
MAGIC = 0xB1
IOC_WRITE, IOC_READ = 1, 2


def _ioc(d, nr, size):
    return (d << 30) | (size << 16) | (MAGIC << 8) | nr


INFO = struct.Struct("<8I")
LIST_HEAD = struct.Struct("<II")
IDENT = struct.Struct("<16s128s")
ENROL_START = struct.Struct("<II128s")
ENROL_POLL = struct.Struct("<IIII16sII")
VERIFY_START = struct.Struct("<II32s")
VERIFY_POLL = struct.Struct("<IIII16s32sQ")
DELETE = struct.Struct("<16s")
MAX_IDENT = 32
LIST_SIZE = LIST_HEAD.size + MAX_IDENT * IDENT.size

GET_INFO = _ioc(IOC_READ, 0x01, INFO.size)
LIST = _ioc(IOC_READ, 0x02, LIST_SIZE)
ENROL_START_IOC = _ioc(IOC_WRITE, 0x03, ENROL_START.size)
ENROL_POLL_IOC = _ioc(IOC_READ, 0x04, ENROL_POLL.size)
VERIFY_START_IOC = _ioc(IOC_WRITE, 0x05, VERIFY_START.size)
VERIFY_POLL_IOC = _ioc(IOC_READ, 0x06, VERIFY_POLL.size)
CANCEL = _ioc(0, 0x07, 0)
DELETE_IOC = _ioc(IOC_WRITE, 0x08, DELETE.size)
DELETE_ALL = _ioc(0, 0x09, 0)

STATE = {0: "idle", 1: "pending", 2: "progress", 3: "done", 4: "failed"}
GUIDE = {0: "", 1: "place the finger on the sensor", 2: "lift the finger and move it a little", 3: "hold still"}
RESULT = {0: "NO MATCH", 1: "MATCH", 2: "not compared"}


def open_dev():
    try:
        return os.open(DEV, os.O_RDWR)
    except OSError as e:
        print("cannot open %s: %s (errno %d)" % (DEV, os.strerror(e.errno), e.errno), file=sys.stderr)
        if e.errno == errno.ENOENT:
            print("  ENOENT after the device exists means: no persisted identity keybag (see the kernel log).", file=sys.stderr)
        sys.exit(3)


def ioctl_r(fd, req, size):
    buf = bytearray(size)
    fcntl.ioctl(fd, req, buf, True)
    return bytes(buf)


def get_info(fd):
    v = INFO.unpack(ioctl_r(fd, GET_INFO, INFO.size))
    return dict(version=v[0], sensor_present=v[1], enrolled=v[2], capacity=v[3], stages=v[4], flags=v[5], live=v[6])


def get_list(fd):
    raw = ioctl_r(fd, LIST, LIST_SIZE)
    count, _ = LIST_HEAD.unpack_from(raw, 0)
    out = []
    for i in range(min(count, MAX_IDENT)):
        u, lab = IDENT.unpack_from(raw, LIST_HEAD.size + i * IDENT.size)
        out.append((u.hex(), lab.split(b"\0", 1)[0].decode("utf-8", "replace")))
    return out


def cmd_info(fd, args):
    i = get_info(fd)
    print("interface version %d, sensor present %d, enrolled %d, capacity %d, enrol stages %d" %
          (i["version"], i["sensor_present"], i["enrolled"], i["capacity"], i["stages"]))
    if i["flags"] & 1:
        print("live identities in the enclave: %d" % i["live"])
    return 0


def cmd_list(fd, args):
    ids = get_list(fd)
    print("%d identities" % len(ids))
    for u, lab in ids:
        print("  %s  %s" % (u, lab))
    return 0


def poll_loop(fd, req, st, timeout, cancel_req, on_poll):
    start = time.monotonic()
    last = None
    try:
        while time.monotonic() - start < timeout:
            fields = st.unpack(ioctl_r(fd, req, st.size))
            line = on_poll(fields)
            if line != last:
                print(line, flush=True)
                last = line
            if fields[0] in (3, 4):
                return fields
            time.sleep(0.25)
    except KeyboardInterrupt:
        print("interrupted: cancelling", file=sys.stderr)
    try:
        fcntl.ioctl(fd, cancel_req)
    except OSError:
        pass
    return None


def cmd_enrol(fd, args):
    label = (args[0] if args else "linux-finger").encode()[:127]
    buf = ENROL_START.pack(0, 0, label)
    fcntl.ioctl(fd, ENROL_START_IOC, buf)
    print("enrol started; touch the sensor when prompted (up to %d s)" % ENROL_TIMEOUT)

    def show(f):
        state, stage, total, status, _u, guide, pct = f
        return "state %s, stage %d of %d, %d%%, status %d %s" % (STATE.get(state, state), stage, total, pct, status, GUIDE.get(guide, ""))

    f = poll_loop(fd, ENROL_POLL_IOC, ENROL_POLL, ENROL_TIMEOUT, CANCEL, show)
    if f is None:
        print("ENROL: no result (timed out or cancelled)")
        return 1
    if f[0] == 3 and f[3] == 0:
        print("ENROL: done, identity %s" % f[4].hex())
        return 0
    print("ENROL: failed, status %d" % f[3])
    return 1


def cmd_verify(fd, args):
    buf = VERIFY_START.pack(0, 0, secrets.token_bytes(32))
    fcntl.ioctl(fd, VERIFY_START_IOC, buf)
    print("verify started; touch the sensor (up to %d s)" % VERIFY_TIMEOUT)

    def show(f):
        state, result, status, guide = f[0], f[1], f[2], f[3]
        res = "result %s, " % RESULT.get(result, result) if state in (3, 4) else ""
        return "state %s, %sstatus %d %s" % (STATE.get(state, state), res, status, GUIDE.get(guide, ""))

    f = poll_loop(fd, VERIFY_POLL_IOC, VERIFY_POLL, VERIFY_TIMEOUT, CANCEL, show)
    if f is None:
        print("VERIFY: no result (timed out or cancelled)")
        return 1
    if f[0] == 3 and f[1] == 1:
        print("VERIFY: MATCH, identity %s (token not shown)" % f[4].hex())
        return 0
    print("VERIFY: %s (state %s, status %d)" % (RESULT.get(f[1], f[1]), STATE.get(f[0], f[0]), f[2]))
    return 1


def cmd_cancel(fd, args):
    fcntl.ioctl(fd, CANCEL)
    print("cancel sent")
    return 0


def cmd_delete(fd, args):
    if len(args) != 1:
        return usage()
    try:
        u = bytes.fromhex(args[0])
    except ValueError:
        return usage()
    if len(u) != 16:
        return usage()
    fcntl.ioctl(fd, DELETE_IOC, DELETE.pack(u))
    print("deleted %s" % args[0])
    return 0


def cmd_delete_all(fd, args):
    if args != ["--yes"]:
        print("delete-all removes every enrolled identity. Add --yes.", file=sys.stderr)
        return 2
    fcntl.ioctl(fd, DELETE_ALL)
    print("all identities deleted")
    return 0


ENROL_TIMEOUT = int(os.environ.get("SEPBIO_ENROL_TIMEOUT", "180"))
VERIFY_TIMEOUT = int(os.environ.get("SEPBIO_VERIFY_TIMEOUT", "30"))
CMDS = {"info": cmd_info, "list": cmd_list, "enrol": cmd_enrol, "verify": cmd_verify, "cancel": cmd_cancel,
        "delete": cmd_delete, "delete-all": cmd_delete_all}


def usage():
    print(__doc__, file=sys.stderr)
    return 2


def main(argv):
    if len(argv) < 2 or argv[1] not in CMDS:
        return usage()
    fd = open_dev()
    try:
        return CMDS[argv[1]](fd, argv[2:])
    except OSError as e:
        print("%s failed: %s (errno %d)" % (argv[1], os.strerror(e.errno), e.errno), file=sys.stderr)
        return 3
    finally:
        os.close(fd)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
