`kde-fingerprint` is the lock screen service (a complete file). The Plasma Login file is built at install time
from the vendor file `/usr/lib/pam.d/plasmalogin` by inserting one line before `auth substack password-auth`:

    -auth       sufficient    pam_fprintd.so max-tries=2 timeout=10

`sufficient` means a match logs in and anything else (no match, timeout, no reader, no enrolled finger, fprintd
missing) falls through to the unchanged password stack. `system-auth`, `password-auth`, `login`, `sudo` and
`sshd` are never edited.
