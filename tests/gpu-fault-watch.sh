#!/bin/bash
# GPU fault watcher: follows the journal and appends GPU fault, recovery, fail-stop and core dump
# lines with time stamps to ~/gpu-fault-watch.log, so a fault shows the moment it happens.
# Run it in the foreground or as the user service tests/gpu-fault-watch.service (no root; the
# user needs journal read access, as for journalctl -k). Read the log: tail -f ~/gpu-fault-watch.log
set -u
LOG=${GPU_FAULT_WATCH_LOG:-$HOME/gpu-fault-watch.log}
echo "$(date --iso-8601=seconds) watch start, kernel $(uname -r)" >> "$LOG"
exec journalctl -f -n 0 -o short-iso-precise --no-pager |
	grep --line-buffered -E 'GPU fault|fault bank|recovery (error|halted|resumed|step)|recovered:|not drained|fail-stop|GPU work of a client failed|dumped core|BO creation failed|DeviceLost' >> "$LOG"
