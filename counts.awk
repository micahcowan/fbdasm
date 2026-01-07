#!/usr/bin/awk -f

# Feed exported text assembly from SourceGen as input to this script,
# being sure to remove any carriage returns first (tr -d '\r')
# it will output how many human-labeled, vs auto-labeled locations
# exist, as a rough sketch of how much work remains to be completed.

BEGIN {
    OK=0
    ucnt=0
    dcnt=0
}

/; ROM Header/ { OK=1 }
!OK { next }
/^;/ { next }
$2 == ".var" { next }

/^[_A-Za-z]/ {
    if ($1 ~ /^.[0-9A-F][0-9A-F][0-9A-F][0-9A-F]/) {
        if (debug) {
            print "U " $1 " line " NR
        }
        ucnt++
    } else {
        if (debug) {
            print "D " $1 " line " NR
        }
        dcnt++
    }
}

END {
    print "! Final counts: " dcnt " labeled, with " ucnt " remaining."
}
