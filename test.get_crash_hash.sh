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
