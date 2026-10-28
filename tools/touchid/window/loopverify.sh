#!/bin/bash
# Restart-loop test: up to 15 short verifies (1.5 s each, cancelled by SIGINT), stop at the first result.
out=~/window/loop.out; : > $out
date +%H:%M:%S.%N >> $out
for i in $(seq 1 15); do
  r=$(sudo -n timeout -s INT 1.5 python3 -I ~/window/touchid/sepbio.py verify 2>&1 | grep -E "^VERIFY|interrupted" | tail -1)
  echo "$(date +%H:%M:%S.%N | cut -c1-12) cycle $i: $r" >> $out
  case "$r" in VERIFY:\ MATCH*|VERIFY:\ NO\ MATCH*) break;; esac
done
echo LOOP-END >> $out
