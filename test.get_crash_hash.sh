#!/bin/bash

# Definition of crash uniqueness (improvements welcome!) …
# A crash is treated as non-duplicate if it has an unique "crash hash" as computed by the following crash hash function:
get_crash_hash() {
  local compilation_output
  local unreachable_message
  local assertion_message
  local normalized_stack_trace
  compilation_output="$1"
  unreachable_message=$(grep "UNREACHABLE executed at " <<< "${compilation_output}" | head -1)
  assertion_message=$(grep "Assertion " <<< "${compilation_output}" | tr ":" "\n" | grep "Assertion " | head -1)
  normalized_stack_trace="${unreachable_message}${assertion_message}"
  if [[ ${normalized_stack_trace} == "" ]]; then
      normalized_stack_trace=$(grep -E '^[0-9]+ swift +0x[0-f]' <<< "${compilation_output}" | head -1)
  fi
  if [[ ${normalized_stack_trace} == "" ]]; then
    crash_hash=""
  else
    crash_hash=$(shasum <<< "${normalized_stack_trace}" | head -c10)
  fi
  echo -n "${crash_hash}"
}
