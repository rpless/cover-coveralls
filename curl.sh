#!/usr/bin/env bash

file=$1
verbose=$2

curl $verbose --include --fail --form json_file=@"$file" "https://coveralls.io/api/v1/jobs"
