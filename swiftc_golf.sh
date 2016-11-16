#!/bin/bash

llvm_symbolizer_path=$(which llvm-symbolizer)
if [[ ${llvm_symbolizer_path} == "" ]]; then
    echo "Error: llvm-symbolizer must be in PATH in order for swiftc to create the expected stack trace format."
    exit 1
fi

echo "Rules for swiftc golf:"
echo "* Entries must crash swiftc."
echo "* Entries must be ten (10) characters or less."
echo "* If two crashes have the same crash hash (see get_crash_hash()), then the shorter one wins."
echo "* If two crashes have the same crash hash and the same length, the first discovered one wins."
echo

set -u

version=$(swiftc --version | head -1)
echo "Testing with Swift compiler (\"swiftc\"):"
echo "${version}"
echo

source test.get_crash_hash.sh

seen_crashes=""
test_crash_case() {
  escaped_source_code="$1"
  source_code=$(echo -e "${escaped_source_code}")
  number_of_bytes=$(echo -n "${source_code}" | wc -c | tr -d " ")
  # Retrying logic in order to increase chance of catching intermittent crashes.
  compilation_output=$(swiftc -O -o /dev/null - <<< "${source_code}" 2>&1)
  for _ in {1..10}; do
    compilation_output=$(swiftc -O -o /dev/null - <<< "${source_code}" 2>&1)
    crash_hash=$(get_crash_hash "${compilation_output}")
    if [[ ${crash_hash} != "" ]]; then
      break
    fi
  done
  dupe_text=""
  if grep -q "${crash_hash}" <<< "${seen_crashes}"; then
    dupe_text=" (DUPE!)"
  fi
  seen_crashes="${seen_crashes}:${crash_hash}"
  if grep -q -E '0x[0-9a-f]{16}' <<< "${compilation_output}"; then
    echo "· ✘ · ${escaped_source_code} (${number_of_bytes} bytes)${dupe_text}"
  else
    echo "· ✓ · ${escaped_source_code} (${number_of_bytes} bytes)"
  fi
  # egrep 0x <<< "${compilation_output}" | egrep 'swift::' | head -1
  # echo
}


echo "Crashing:"

test_crash_case '!('
test_crash_case '-._'
test_crash_case 'if('
test_crash_case '._[]'
test_crash_case '#if_='
test_crash_case '_?==_'
test_crash_case '._._=0'
test_crash_case '._=nil'
test_crash_case '[_?,&_'
test_crash_case 'Slice._'
test_crash_case '{$0(*)}{'
test_crash_case '(_=nil,_)'
test_crash_case 'nil?=\n&_,'

echo
echo "Fixed:"

test_crash_case '!(0^_{'
test_crash_case '&(-_'
test_crash_case '&(<)==('
test_crash_case '&(>,_'
test_crash_case '&(Int:_'
test_crash_case '&.f{}()do'
test_crash_case '&0{'
test_crash_case '&[(-{'
test_crash_case '&[_?'
test_crash_case '&_'
test_crash_case '&_{Array'
test_crash_case '&_{Int'
test_crash_case '&_{Range?'
test_crash_case '&Range.T{'
test_crash_case '&true{for{'
test_crash_case '(&.f>_'
test_crash_case '()=()'
test_crash_case '([_'
test_crash_case '({[({_'
test_crash_case '.A['
test_crash_case '.{nil<{\n{'
test_crash_case '[&{}false?'
test_crash_case '[1,{[1,{[]'
test_crash_case '[[map'
test_crash_case ']{&[]()'
test_crash_case '_={$0()}'
test_crash_case 'Array([[]'
test_crash_case 'do{&{}{)'
test_crash_case 'for{{'
test_crash_case 'nil as('
test_crash_case 'Range>\n&_{'
test_crash_case 'true[&{_'
test_crash_case 'var(()...'
test_crash_case '{$0()'
test_crash_case '{&(&)'
test_crash_case '{&_'
test_crash_case '{(&_{("'
test_crash_case '{(_>"",{'
test_crash_case '{[ &{}{'
test_crash_case '{[-{_'
test_crash_case '{_>{{'
test_crash_case '{_{[true'
test_crash_case '{f\n-{{_'
test_crash_case '{nil-{_?'
test_crash_case '{nil...{('
test_crash_case '{nil{true?'
