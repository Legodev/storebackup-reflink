#! /bin/sh

perl -p -e 's/^\s*uncompress=bzip2\s*$/uncompress=bzip2 -d\n/' -i */.md5CheckSums.info
