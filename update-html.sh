#!/bin/bash

main() {
    HTML=fb3.nes.html

    # get latest git revision log
    revlog=$(git log -n 1)
    #
    # parse commit id
    id=$(printf '%s\n' "$revlog" | sed -n 's/^commit //p')

    # parse date
    date=$(printf '%s\n' "$revlog" | sed -n 's/^Date:  *//p')

    # determine comment prefix from html file
    pfx=$(sed -n '/This project is/ { s/^\( *; \).*/\1/; p; q }' < "$HTML")

    r=$"\r"
    # edit the HTML file
    sed "
/^<p.*back to project page/d
/This project is.*github\\.com/a\\
${pfx}${r}\\
${pfx}This file was generated from${r}\\
${pfx}  git commit ${id}${r}\\
${pfx}  from ${date}${r}
" -i "$HTML"
}

main
exit 0
