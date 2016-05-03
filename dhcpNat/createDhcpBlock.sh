#!/bin/bash

IFS=$OLDIFS
IFS=$' \n'
for file in mappings/{DPI1.mapping,DPI2.mapping,moreSDE.mapping,moreSPB.mapping}; do
    bladeName=$(echo "$file" | cut -f1 -d\.)
    echo "<!-- Blade {$bladeName} mac/vm-name/ip mappings -->"

    IFS=$'\n'
    for line in $(cat "$file"); do

        IFS=$' \t'
        set $line

        vmName=$2
        mac=$3
        ip=$4

        echo "<host mac='$mac' name='$vmName' ip='$ip' />"
    done
    echo "<!-- -->"
done

