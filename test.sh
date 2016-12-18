#!/bin/bash
# Distributed under the terms of the MIT license
# Style guide: https://google-styleguide.googlecode.com/svn/trunk/shell.xml
# Defensive bash programming: http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming/
# Shell lint: http://www.shellcheck.net/
# Tip: Want to see details of the type checker's reasoning? Compile with "swiftc -Xfrontend -debug-constraints"
# Tip: Want to see what individual job invocations a swift/swiftc run invokes? Try "swift[c] -driver-print-jobs foo.swift"

# Treat unset variables and parameters other than the special parameters "@" or "*" as an error when performing parameter expansion
set -u

source test.get_crash_hash.sh

readonly COLOR_RED="\e[31m"
readonly COLOR_GREEN="\e[32m"
readonly COLOR_BOLD="\e[1m"
readonly COLOR_NORMAL_DISPLAY="\e[0m"

swiftc_command="swiftc"

llvm_symbolizer_path=$(which llvm-symbolizer)
if [[ ${llvm_symbolizer_path} == "" ]]; then
    echo "Error: llvm-symbolizer must be in PATH in order for swiftc to create the expected stack trace format."
    exit 1
fi

columns=$(tput cols)
delete_dupes=0
delete_fixed=0
verbose=0
while getopts "c:vldfm:q" o; do
  case ${o} in
    c)
      columns=${OPTARG}
      ;;
    v)
      verbose=1
      ;;
    d)
      delete_dupes=1
      ;;
    f)
      delete_fixed=1
      ;;
  esac
done
shift $((OPTIND - 1))
name_size=$((columns - 20))
if [[ ${name_size} -lt 35 ]]; then
  name_size=35
fi
num_tests=0
num_crashed=0
seen_crash_hashes=""

###

show_error() {
  local warning="$1"
  printf "%b" "${COLOR_RED}[Error]${COLOR_NORMAL_DISPLAY} ${COLOR_BOLD}${warning}${COLOR_NORMAL_DISPLAY}\n"
}

test_file() {
  local path=$1
  if [[ ! -f ${path} ]]; then
    return
  fi
  local files_to_compile=${path}
  if [[ ${path} =~ part1.swift ]]; then
    return
  elif [[ ${path} =~ (part|library)[2-9].swift ]]; then
    return
  fi
  local test_name
  test_name=$(basename -s ".swift" "${path}")
  test_name=${test_name//-/ }
  test_name=${test_name//.library1/}
  test_name=${test_name//.part1/}
  test_name=${test_name//.random/}
  test_name=${test_name//.runtime/}
  test_name=${test_name//.sil/}
  test_name=${test_name//.timeout/}
  num_tests=$((num_tests + 1))
  local swift_crash=0
  local compilation_comment=""
  local output=""
  # shellcheck disable=SC2086
  output=$(${swiftc_command} -o /dev/null ${files_to_compile} 2>&1 | strings)
  if [[ ${output} =~ \ malloc:\  ]]; then
    swift_crash=1
    compilation_comment="malloc"
  elif [[ ${output} =~ (error:\ unable\ to\ execute\ command:\ Segmentation\ fault|LLVM\ ERROR:|While\ emitting\ IR\ for\ source\ file|error:\ linker\ command\ failed\ with\ exit\ code\ 1|error:\ swift\ frontend\ command\ failed\ due\ to\ signal|Stack\ dump:|Segmentation\ fault|Aborted) ]]; then
    swift_crash=1
    compilation_comment=""
  fi

  output_with_llvm_symbolizer=$(egrep '^#[0-9] 0x[0-9a-f]{16} swift::' <<< "${output}" | head -1)
  output_without_llvm_symbolizer=$(egrep '^[0-9]+ swift +0x[0-9a-f]{16}$' <<< "${output}" | head -1)
  if [[ ${output_with_llvm_symbolizer} == "" && ${output_without_llvm_symbolizer} != "" ]]; then
      echo "Error: llvm-symbolizer appears in PATH but does not create the expected stack trace format."
      exit 1
  fi

  local hash
  hash=$(get_crash_hash "${output}")
  # grep -E "0x[0-9a-f]" <<< "${output}" | grep -E '(swift|llvm)::' | grep -vE '(llvm::sys::|frontend_main)' | awk '{ $1=$2=$3=""; print $0 }' | sed 's/^ *//g' | grep -E '(swift|llvm)::' | head -10
  local is_dupe=0
  if [[ ${hash} == "" ]]; then
    hash="        "
  else
    if [[ ${seen_crash_hashes} =~ ${hash} ]]; then
      is_dupe=1
    fi
    seen_crash_hashes="${seen_crash_hashes}:${hash}"
  fi
  if [[ ${swift_crash} == 1 ]]; then
    if [[ ${compilation_comment} != "" ]]; then
      test_name="${test_name} (${compilation_comment})"
    fi
    num_crashed=$((num_crashed + 1))
    local adjusted_name_size=${name_size}
    if [[ ${is_dupe} == 1 ]]; then
      test_name="${test_name} (${COLOR_BOLD}dupe?${COLOR_NORMAL_DISPLAY})"
      adjusted_name_size=$((adjusted_name_size + 8))
      if [[ ${delete_dupes} == 1 && ${files_to_compile} =~ crashes-fuzzing ]]; then
        # shellcheck disable=SC2086
        rm ${files_to_compile}
      fi
    fi
    printf "  %b  %-${adjusted_name_size}.${adjusted_name_size}b (%-10.10b)\n" "${COLOR_RED}✘${COLOR_NORMAL_DISPLAY}" "${test_name}" "${hash}"
  else
    if [[ ${delete_fixed} == 1 && ${files_to_compile} =~ crashes-fuzzing ]]; then
      # shellcheck disable=SC2086
      rm ${files_to_compile}
    fi
    printf "  %b  %-${name_size}.${name_size}b\n" "${COLOR_GREEN}✓${COLOR_NORMAL_DISPLAY}" "${test_name}"
  fi
  if [[ ${verbose} == 1 ]]; then
    crashed_in_function=$(grep -E "0x[0-9a-f]" <<< "${output}" | grep -v '\*\*\*' | grep -E -v '(llvm::sys::PrintStackTrace|SignalHandler|_sigtramp|swift::TypeLoc::isError)' | grep -E '(swift|llvm)' | head -1 | sed 's/ 0x[0-9a-f]/|/g' | cut -f2- -d'|' | cut -f2- -d' ')
    echo
    printf "%b" "${COLOR_BOLD}Crashed in function:${COLOR_NORMAL_DISPLAY}\n"
    echo "${crashed_in_function}"
    echo
    printf "%b" "${COLOR_BOLD}Compilation output:${COLOR_NORMAL_DISPLAY}\n"
    echo "${output}"
    echo
  fi
}

print_header() {
  local header=$1
  echo
  printf "%b" "== ${COLOR_BOLD}${header}${COLOR_NORMAL_DISPLAY} ==\n"
  echo
}

run_tests_in_directory() {
  local header=$1
  local path=$2
  print_header "${header}"
  local found_tests=0
  local test_path
  for test_path in "${path}"/*.swift; do
    if [[ -h "${test_path}" ]]; then
      test_path=$(readlink "${test_path}" | cut -b4-)
    fi
    if [[ -f "${test_path}" ]]; then
      found_tests=1
      test_file "${test_path}"
    fi
  done
  if [[ ${found_tests} == 0 ]]; then
    printf "  %b  %-${name_size}.${name_size}b\n" "${COLOR_GREEN}✓${COLOR_NORMAL_DISPLAY}" "No tests found."
  fi
}

main() {
  local swiftc_version
  swiftc_version=$(${swiftc_command} -version | head -1)
  echo
  echo "Running tests against: ${swiftc_version}"
  echo "Usage: $0 [-v] [-q] [-c<columns>] [-l] [file ...]"
  local current_max_id
  current_max_id=$(find crashes crashes-fuzzing crashes-duplicates fixed -name "?????-*.swift" | cut -f2 -d'/' | grep -E '^[0-9]+\-' | sort -n | cut -f1 -d'-' | sed 's/^0*//g' | tail -1)
  local next_id
  next_id=$((current_max_id + 1))
  echo "Adding a new test case? The crash id to use for the next test case is ${next_id}."
  local duplicate_bug_ids
  duplicate_bug_ids=$(find crashes crashes-fuzzing crashes-duplicates fixed -name "?????-*.swift" | cut -f2 -d/ | cut -f1 -d'.' | sort | uniq | cut -f1 -d'-' | uniq -c | sed "s/^ *//g" | grep -E -v '^1 ' | cut -f2 -d" " | tr "\n" "," | sed "s/,$//g")
  if [[ ${duplicate_bug_ids} != "" ]]; then
    show_error "Duplicate bug ids: ${duplicate_bug_ids}. Please re-number to avoid duplicates."
    echo
  fi
  ${swiftc_command} - -o /dev/null 2>&1 <<< "" | grep -E -q "error:" && {
    show_error "swiftc does not appear to work. Cannot run tests. Please investigate."
    exit 1
  }
  local argument_files=$*
  if [[ ${argument_files} == "" ]]; then
    run_tests_in_directory "Currently known crashes, set #1 (human reported crashes)" "./crashes"
    run_tests_in_directory "Currently known crashes, set #2 (crashes found by fuzzing)" "./crashes-fuzzing"
    # run_tests_in_directory "Currently known crashes (duplicates)" "./crashes-duplicates"
    if [[ ${delete_dupes} == 1 || ${delete_fixed} == 1 ]]; then
      exit 0
    fi
    run_tests_in_directory "Crashes marked as fixed in previous releases" "./fixed"
  else
    local test_path
    for test_path in ${argument_files}; do
      if [[ -f ${test_path} ]]; then
        found_tests=1
        test_file "${test_path}"
      fi
    done
    echo
  fi
  echo "** Results: ${num_crashed} of ${num_tests} tests crashed the compiler **"
  echo
}

main "$@"
