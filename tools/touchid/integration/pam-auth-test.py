#!/usr/bin/env python3
"""Password test for one PAM service, through libpam (ctypes). Run as root, on a terminal.

  pam-auth-test.py SERVICE USER

Asks for the password of USER once. Passes only when the right password is accepted AND a random wrong
password is refused, each within 60 s. It runs the auth stack only (no session), so it opens no login.
The password is read with getpass, kept in memory and never printed or logged.
"""
import ctypes
import ctypes.util
import getpass
import secrets
import signal
import sys
import time

PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON, PAM_ERROR_MSG, PAM_TEXT_INFO = 1, 2, 3, 4


class PamMessage(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class PamResponse(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_void_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(PamMessage)),
                        ctypes.POINTER(ctypes.POINTER(PamResponse)), ctypes.c_void_p)


class PamConv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("appdata_ptr", ctypes.c_void_p)]


def attempt(libpam, libc, service, user, password):
    calloc, strdup = libc.calloc, libc.strdup
    calloc.restype, calloc.argtypes = ctypes.c_void_p, [ctypes.c_size_t, ctypes.c_size_t]
    strdup.restype, strdup.argtypes = ctypes.c_void_p, [ctypes.c_char_p]

    def conv(n, msgs, resps, _data):
        arr = calloc(n, ctypes.sizeof(PamResponse))
        if not arr:
            return 19
        out = ctypes.cast(arr, ctypes.POINTER(PamResponse))
        for i in range(n):
            style = msgs[i].contents.msg_style
            if style == PAM_PROMPT_ECHO_OFF:
                out[i].resp = strdup(password.encode())
            elif style == PAM_PROMPT_ECHO_ON:
                out[i].resp = strdup(user.encode())
            elif style in (PAM_ERROR_MSG, PAM_TEXT_INFO):
                print("    pam says: %s" % (msgs[i].contents.msg or b"").decode(errors="replace"))
        resps[0] = out
        return 0

    cb = CONV(conv)
    pc = PamConv(cb, None)
    handle = ctypes.c_void_p()
    libpam.pam_start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(PamConv), ctypes.POINTER(ctypes.c_void_p)]
    libpam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
    libpam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
    rc = libpam.pam_start(service.encode(), user.encode(), ctypes.byref(pc), ctypes.byref(handle))
    if rc != 0:
        return rc, 0.0
    t0 = time.monotonic()
    signal.alarm(60)
    rc = libpam.pam_authenticate(handle, 0)
    signal.alarm(0)
    dt = time.monotonic() - t0
    libpam.pam_end(handle, rc)
    return rc, dt


def main():
    if len(sys.argv) != 3 or not sys.argv[2]:
        sys.exit("usage: pam-auth-test.py SERVICE USER")
    service, user = sys.argv[1:3]
    name = ctypes.util.find_library("pam")
    if not name:
        sys.exit("libpam not found")
    libpam, libc = ctypes.CDLL(name), ctypes.CDLL(ctypes.util.find_library("c"))
    signal.signal(signal.SIGALRM, lambda *_: sys.exit("[pam-test] STOP: %s hung for 60 s" % service))
    password = getpass.getpass("[pam-test] password of %s for service %s: " % (user, service))
    good, tg = attempt(libpam, libc, service, user, password)
    bad, tb = attempt(libpam, libc, service, user, secrets.token_urlsafe(18))
    del password
    print("[pam-test] %-12s right password: %s (%.1f s)   wrong password: %s (%.1f s)" % (
        service, "ACCEPTED" if good == 0 else "REFUSED rc=%d" % good, tg,
        "REFUSED" if bad != 0 else "ACCEPTED", tb))
    if good != 0:
        print("[pam-test] FAIL: the right password was not accepted by %s" % service)
        sys.exit(1)
    if bad == 0:
        print("[pam-test] FAIL: a wrong password was accepted by %s" % service)
        sys.exit(1)


if __name__ == "__main__":
    main()
