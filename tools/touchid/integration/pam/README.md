`kde-fingerprint` is the lock screen service (a complete file). The Plasma Login file is built at install time
from the vendor file `/usr/lib/pam.d/plasmalogin` by inserting two lines before `auth substack password-auth`:

    auth        [success=1 default=ignore] pam_unix.so nodelay
    -auth       sufficient    pam_fprintd.so max-tries=2 timeout=5

A typed password passes `pam_unix` and skips the finger line, so the login does not wait. Enter with an empty
password field fails `pam_unix` at once, and the finger line waits up to 5 s for the enrolled finger. `sufficient`
means a match logs in and anything else (no match, timeout, no reader, no enrolled finger, fprintd missing) falls
through to the unchanged password stack. `system-auth`, `password-auth`, `login`, `sudo` and
`sshd` are never edited.
