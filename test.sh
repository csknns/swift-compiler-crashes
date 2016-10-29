#!/bin/bash
# Distributed under the terms of the MIT license
# Style guide: https://google-styleguide.googlecode.com/svn/trunk/shell.xml
# Defensive bash programming: http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming/
# Shell lint: http://www.shellcheck.net/
# Tip: Want to see details of the type checker's reasoning? Compile with "swiftc -Xfrontend -debug-constraints"
# Tip: Want to see what individual job invocations a swift/swiftc run invokes? Try "swift[c] -driver-print-jobs foo.swift"

# Treat unset variables and parameters other than the special parameters ‘@’ or ‘*’ as an error when performing parameter expansion
set -u

readonly COLOR_RED="\e[31m"
readonly COLOR_GREEN="\e[32m"
readonly COLOR_BOLD="\e[1m"
readonly COLOR_NORMAL_DISPLAY="\e[0m"

swiftc_command="swiftc"

columns=$(tput cols)
delete_dupes=0
delete_fixed=0
log_stacks=0
max_test_number=0
quick_mode=0
verbose=0
while getopts "c:vldfm:q" o; do
  case ${o} in
    c)
      columns=${OPTARG}
      ;;
    v)
      verbose=1
      ;;
    l)
      log_stacks=1
      ;;
    d)
      delete_dupes=1
      ;;
    f)
      delete_fixed=1
      ;;
    m)
      max_test_number=${OPTARG}
      ;;
    q)
      quick_mode=1
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

execute_with_timeout() {
  local timeout_in_seconds=$1
  local command=$2
  local out
  out=$(expect -c "set echo \"-noecho\"; set timeout ${timeout_in_seconds}; spawn -noecho /bin/sh -c \"${command}\"; expect timeout { exit 1 } eof { exit 0 }" 2>&1)
  local return_code=$?
  echo "${out}" | tr -d "\r"
  return ${return_code}
}

# Definition of crash uniqueness (improvements welcome!) …
# A crash is treated as non-duplicate if it has an unique "crash hash" as computed by the following crash hash function:
get_crash_hash() {
  local compilation_output="$1"
  local unreachable_message=$(grep "UNREACHABLE executed at " <<< ${compilation_output} | head -1)
  local assertion_message=$(grep "Assertion " <<< "${compilation_output}" | tr ":" "\n" | grep "Assertion " | head -1)
  local normalized_stack_trace="${unreachable_message}${assertion_message}$(grep -E '^[0-9]+ swift +0x[0-f]' <<< ${compilation_output} | head -1)"
  if [[ ${normalized_stack_trace} == "" ]]; then
    crash_hash=""
  else
    crash_hash=$(shasum <<< "${normalized_stack_trace}" | head -c10)
  fi
  echo -n "${crash_hash}"
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
  local current_test_number
  current_test_number=$(echo "${test_name}" | tr " " "\n" | grep -E "^[0-9]+$" | head -1 | sed "s/^0*//g")
  if [[ ${max_test_number} != 0 && ${current_test_number} != "" && ${current_test_number} -gt ${max_test_number} ]]; then
    return
  fi
  num_tests=$((num_tests + 1))
  local swift_crash=0
  local compilation_comment=""
  local output=""
  # Test mode: Run Swift code and catch a portential hang (infinite running time),
  #            excessive running time or excessive compilation time.
  #            Used for test cases named *.timeout.swift.
  if [[ ${swift_crash} == 0 && ${files_to_compile} =~ \.timeout\. ]]; then
    local _
    for _ in {1..5}; do
      output=$(execute_with_timeout 10 "swift ${files_to_compile}")
      # echo "# output: ${output}"
      if [[ $? == 1 ]]; then
        swift_crash=1
        compilation_comment="timeout"
        break
      elif [[ ${output} =~ Stack\ dump: ]]; then
        swift_crash=1
        compilation_comment=""
        break
      elif [[ ${output} =~ Segmentation\ fault ]]; then
        swift_crash=1
        compilation_comment=""
        break
      elif [[ ${output} =~ Aborted ]]; then
        swift_crash=1
        compilation_comment=""
        break
      elif [[ ${output} =~ \ malloc:\  ]]; then
        swift_crash=1
        compilation_comment="malloc"
        break
      fi
    done
  fi
  # Test mode: Compile using swiftc without any optimizations ("-Onone").
  #            Used for test cases named *.swift.
  if [[ ${swift_crash} == 0 && ! ${files_to_compile} =~ \.timeout\. ]]; then
    local _
    for _ in {1..50}; do
      # shellcheck disable=SC2086
      output=$(${swiftc_command} -Onone -o /dev/null ${files_to_compile} 2>&1 | strings)
      # echo "# output: ${output}"
      if [[ ${output} =~ \ malloc:\  ]]; then
        swift_crash=1
        compilation_comment="malloc"
        break
      elif [[ ${output} =~ (error:\ unable\ to\ execute\ command:\ Segmentation\ fault|LLVM\ ERROR:|While\ emitting\ IR\ for\ source\ file|error:\ linker\ command\ failed\ with\ exit\ code\ 1|error:\ swift\ frontend\ command\ failed\ due\ to\ signal|Stack\ dump:|Segmentation\ fault|Aborted) ]]; then
        swift_crash=1
        compilation_comment=""
        break
      elif [[ ! ${files_to_compile} =~ \.random\. ]]; then
        output=""
        break
      fi
    done
  fi
  # Test mode: Invoke Swift SIL parser (-parse-sil).
  #            Used for test cases named *.sil.swift.
  if [[ ${swift_crash} == 0 && ${files_to_compile} =~ \.sil\. ]]; then
    # shellcheck disable=SC2086
    output=$(${swiftc_command} -parse-sil -o /dev/null ${files_to_compile} 2>&1 | strings)
    # echo "# output: ${output}"
    if [[ ${output} =~ (error:\ unable\ to\ execute\ command:\ Segmentation\ fault|LLVM\ ERROR:|While\ emitting\ IR\ for\ source\ file|error:\ linker\ command\ failed\ with\ exit\ code\ 1|error:\ swift\ frontend\ command\ failed\ due\ to\ signal|Stack\ dump:|Segmentation\ fault|Aborted) ]]; then
      swift_crash=1
      compilation_comment="sil"
    fi
  fi
  # Test mode: Compile using swiftc with optimization option "-O".
  #            Used for test cases named *.swift.
  if [[ ${swift_crash} == 0 && ! ${files_to_compile} =~ \.timeout\. ]]; then
    local _
    for _ in {1..20}; do
      # shellcheck disable=SC2086
      output=$(${swiftc_command} -O -o /dev/null ${files_to_compile} 2>&1 | strings)
      # echo "# output: ${output}"
      if [[ ${output} =~ \ malloc:\  ]]; then
        swift_crash=1
        compilation_comment="malloc"
        break
      elif [[ ${output} =~ (error:\ unable\ to\ execute\ command:\ Segmentation\ fault|LLVM\ ERROR:|While\ emitting\ IR\ for\ source\ file|error:\ linker\ command\ failed\ with\ exit\ code\ 1|error:\ swift\ frontend\ command\ failed\ due\ to\ signal|Stack\ dump:|Segmentation\ fault|Aborted) ]]; then
        swift_crash=1
        compilation_comment="-O"
        break
      elif [[ ! ${files_to_compile} =~ \.random\. ]]; then
        output=""
        break
      fi
    done
  fi
  # Test mode: Compile with file #1 as a library and file #2 as a library user.
  #            Used for test cases named *.library{1,2}.swift.
  if [[ ${swift_crash} == 0 && ${files_to_compile} =~ \.library1\. && -f ${files_to_compile//.library1./.library2.} ]]; then
    local source_file_using_library=${files_to_compile//.library1./.library2.}
    compilation_comment=""
    rm -f DummyModule.swiftdoc DummyModule.swiftmodule libDummyModule.dylib libDummyModule.app
    output=$(${swiftc_command} -emit-library -o libDummyModule.dylib -Xlinker -install_name -Xlinker @rpath/libDummyModule.dylib -emit-module -emit-module-path DummyModule.swiftmodule -module-name DummyModule -module-link-name DummyModule "${files_to_compile}" 2>&1)
    # echo "# output: ${output}"
    if [[ $? == 0 ]]; then
      # shellcheck disable=SC2086
      output=$(${swiftc_command} "${source_file_using_library}" -o libDummyModule.app -I . -L . -Xlinker -rpath -Xlinker @executable_path/ 2>&1 | strings)
      # echo "# output: ${output}"
      if [[ ${output} =~ (error:\ unable\ to\ execute\ command:\ Segmentation\ fault|LLVM\ ERROR:|While\ emitting\ IR\ for\ source\ file|Aborted) ]]; then
        swift_crash=1
        compilation_comment="lib I"
      elif [[ ! ${output} =~ implicit\ entry/start\ for\ main\ executable && ${output} =~ error:\ linker\ command\ failed\ with\ exit\ code\ 1 ]]; then
        swift_crash=1
        compilation_comment="lib II"
      fi
      if [[ ${swift_crash} == 0 ]]; then
        local output_1
        output_1=$(./libDummyModule.app 2>&1)
        local exit_1=$?
        # shellcheck disable=SC2086
        local output_2
        output_2=$(swift -I . "${source_file_using_library}" 2>&1)
        local exit_2=$?
        if [[ "${exit_1}" != "${exit_2}" ]]; then
          swift_crash=1
          output="${output_1}${output_2}"
	  # echo "# output: ${output}"
          compilation_comment="lib III"
        fi
      fi
    fi
    rm -f DummyModule.swiftdoc DummyModule.swiftmodule libDummyModule.dylib libDummyModule.app
  fi
  # Test mode: Run Swift code and watch for runtime error.
  #            Used for test cases named *.runtime.swift.
  if [[ ${swift_crash} == 0 && ${files_to_compile} =~ \.runtime\. ]]; then
    local _
    for _ in {1..10}; do
      # shellcheck disable=SC2086
      output=$(swift -Onone ${files_to_compile} 2>&1 | strings)
      # echo "# output: ${output}"
      if [[ ${output} =~ llvm::sys::PrintStackTrace ]]; then
        swift_crash=1
        compilation_comment="runtime"
        output=""
        break
      elif [[ ! ${files_to_compile} =~ \.random\. ]]; then
        output=""
        break
      fi
    done
  fi
  if [[ ${log_stacks} == 1 ]]; then
    # shellcheck disable=SC2046
    stacktrace_log=./stacks/$(basename $(head -1 <<< "${files_to_compile}") | sed 's/.swift$//').txt
    grep -E "0x[0-9a-f]" <<< "${output}" | sed 's/ 0x[0-9a-f]*//g' | sed 's/ [0-9][0-9][0-9][0-9][0-9][0-9][0-9]*$/ [N]/g' | sed "s/^swift([0-9]*,0x[0-9a-f]*)/swift(N,0xN)/" | grep -E "^[0-9]" | grep -E -v '(libdyld|libsystem_kernel|libsystem_malloc|libsystem_platform|libsystem_c|libsystem_malloc)\.dylib' | grep -E -v '(llvm::sys::PrintStackTrace|SignalHandler)' > "${stacktrace_log}"
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
  local operating_system="$(uname -s)"
  for test_path in "${path}"/*.swift; do
    # Skipping Darwin dependent tests 28184/28185 on non-Darwin platforms.
    if [[ "${operating_system}" != "Darwin" && "${test_path}" =~ (28184|28185) ]]; then
       continue
    fi
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
  if [[ ${max_test_number} != 0 ]]; then
    current_max_id=${max_test_number}
  fi
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
    if [[ ${quick_mode} == 1 ]]; then
      print_header "Quick mode — testing only crashes triggered at unique crash locations"
      local test_file
      for test_file in $(find unique-crash-locations/ -type l -exec readlink {} \; | cut -f2- -d/ | sort -t/ -k2); do
        test_file "${test_file}"
      done
      echo
      exit
    fi
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
