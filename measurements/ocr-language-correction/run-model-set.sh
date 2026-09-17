#!/bin/zsh
# Run the language-correction probe over the English OCR pages under one never-used executable
# name, so the process compiles its own Vision model set (#94). Records the cache fingerprint
# before and after, then removes the copy (the cache is kept until the results are recorded).
# usage: run-model-set.sh <probe> <name> <off-on|on-off> <corpus cache dir> <output dir> [books...]
probe=$1; name=$2; order=$3; cache=$4; out=$5; shift 5
books=($@); (( $#books )) || books=(census cdc bluebook warren)
tools=${0:A:h}/../../tools
mkdir -p $out/bin
cp $probe $out/bin/$name
fingerprint() { python3 -c "import sys, json; sys.path.insert(0, '$tools'); import conversion_provenance as p; print(json.dumps(p.vision_model_cache('$name')))"; }
echo "{\"stage\": \"before\", \"cache\": $(fingerprint)}" >> $out/$name-cache.jsonl
for book in $books; do
  case $book in
    census) pdf=rrs2002-01.pdf; pages=({2..20}) ;;
    cdc) pdf=cdc_6023_DS1.pdf; pages=(2 13 15 16 17 36 38 40 41) ;;
    bluebook) pdf=CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf; pages=({1..312}) ;;
    warren) pdf=GPO-WARRENCOMMISSIONREPORT.pdf; pages=(1 7 21 30 50 100 890 910 920) ;;
  esac
  echo "$(date +%T) load=$(sysctl -n vm.loadavg | cut -d' ' -f2) $name $book ${#pages} pages"
  $out/bin/$name $cache/$pdf $order $pages > $out/$name-$book.jsonl
done
echo "{\"stage\": \"after\", \"cache\": $(fingerprint)}" >> $out/$name-cache.jsonl
echo "$(date +%T) done $name"
rm $out/bin/$name
