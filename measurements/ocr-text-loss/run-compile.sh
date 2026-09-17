#!/bin/zsh
# Run probe-ocr-lines under a never-used executable name, so the process compiles its own Vision
# model set (#94), over the chosen books. Records the cache fingerprint after the first book and
# at the end, then removes the copy. The cache is kept until results are recorded; delete it with
# `rm -rf ~/Library/Caches/<name>`.
# usage: run-compile.sh <probe> <name> <corpus cache dir> <output dir> <book>...
#   books: census (pages 2-20), cdc (all 42), warren (excerpt pages), warren-sample (60 pages),
#          bluebook (all 312), flag (Our Flag, all 56), jres (NBS JRES, all 7)
probe=$1; name=$2; cache=$3; out=$4; shift 4
tools=${0:A:h}/../../tools
mkdir -p $out/bin
cp $probe $out/bin/$name
fingerprint() { python3 -c "import sys, json; sys.path.insert(0, '$tools'); import conversion_provenance as p; print(json.dumps(p.vision_model_cache('$name')))"; }
for book in $@; do
  case $book in
    census) pdf=rrs2002-01.pdf; pages=({2..20}) ;;
    cdc) pdf=cdc_6023_DS1.pdf; pages=({1..42}) ;;
    warren) pdf=GPO-WARRENCOMMISSIONREPORT.pdf; pages=(1 7 21 30 50 100 890 910 920) ;;
    warren-sample) pdf=GPO-WARRENCOMMISSIONREPORT.pdf; pages=($(seq 3 15 900)) ;;
    bluebook) pdf=CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf; pages=({1..312}) ;;
    flag) pdf=CDOC-108hdoc97.pdf; pages=({1..56}) ;;
    jres) pdf=jresv82n3p173_A1b.pdf; pages=({1..7}) ;;
  esac
  echo "$(date +%T) load=$(sysctl -n vm.loadavg | cut -d' ' -f2) $name $book ${#pages} pages"
  $out/bin/$name $cache/$pdf $pages > $out/$name-$book.jsonl
  echo "{\"after\": \"$book\", \"cache\": $(fingerprint)}" >> $out/$name-cache.jsonl
done
echo "$(date +%T) done $name"
rm $out/bin/$name
