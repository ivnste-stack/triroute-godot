#!/bin/bash
# list undefined globals in a JS bundle: undef.sh file.js
cd "$(dirname "$0")"
npx eslint --no-eslintrc -c .eslintrc.json -f unix "$1" 2>&1 | grep "no-undef" | sed -E "s/.*'([^']+)' is not defined.*/\1/" | sort | uniq -c | sort -rn
