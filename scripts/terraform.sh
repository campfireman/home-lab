#!/bin/bash

set -ex

function init() {
  tfenv install
  tfenv use
  tfenv exec init
  tfenv exec get -update
}

function plan() {
  tfenv exec plan ${TF_VARS_ARG}
}

function apply() {
  tfenv exec apply -input=false -auto-approve ${TF_VARS_ARG}
}

function console() {
  tfenv exec console ${TF_VARS_ARG}
}

function print_usage() {
  echo "Usage: $0 <init|plan|apply|import> <module_path_from_project_root> [var1=value1 var2=value2 ...] [positional_arg1 positional_args2 ...]"
  exit 1
}

function import () {
  tfenv exec import ${TF_VARS_ARG} ${*}
}

CMD=${1}
PROJECT_DIR=$(cd "$(dirname "$0")"/.. && pwd -P)
MODULE_PATH=${PROJECT_DIR}/${2}
shift
shift
TF_ARGS=${*}
TF_VARS_ARG=""

if [[ -z "${CMD}" || -z "${MODULE_PATH}" ]]; then
  print_usage
fi

if [[ ! -d "${MODULE_PATH}" ]]; then
  echo "Module path ${MODULE_PATH} does not exist!"
  print_usage
  exit 1
fi

for VAR in ${TF_ARGS}; do
  if [[ "${VAR}" == *"="* ]]; then
    TF_VARS_ARG="${TF_VARS_ARG} -var ${VAR}"
    shift
  fi
done

pushd "${MODULE_PATH}" >/dev/null || exit

case $CMD in
init)
  init
  ;;
plan)
  plan
  ;;
apply)
  apply
  ;;
console)
  console
  ;;
import)
  import ${*}
  ;;
*)
  print_usage
  exit 1
  ;;
esac