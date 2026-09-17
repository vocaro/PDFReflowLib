#!/bin/zsh
# Sample Vision model compilation (#94): run a compiled probe-page-ocr under <count> never-used
# names, so each process compiles Vision's models into an empty cache. Prints load, text hash and
# the two program files that varied (27BD..., 572C...), then removes that name's cache and copy.
# usage: sample-fresh-compiles.sh <probe> <count> <pdf> <page>   (PROBE_DEVICE is passed through)
probe=$1; count=$2; pdf=$3; page=$4
work=$(mktemp -d)
for i in $(seq 1 $count); do
  name=ocr-sample-$(uuidgen | cut -c1-8 | tr A-Z a-z)
  cp "$probe" $work/$name
  line=$($work/$name "$pdf" $page 2>/dev/null | grep '^page')
  programs=$(cd ~/Library/Caches/$name/com.apple.e5rt.e5bundlecache/*/ && for k in 27BD* 572C*; do
    [ -d "$k" ] && echo -n "${k:0:4}=$(cat $k/*/H17C.bundle/H17C.e5 | shasum | cut -c1-6) "; done)
  echo "$(date +%T) load=$(sysctl -n vm.loadavg | cut -d' ' -f2) $name $line $programs"
  rm -rf ~/Library/Caches/$name $work/$name
done
rmdir $work
