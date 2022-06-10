#!/bin/bash
set -e
#set -x

cd $(dirname ${0})

if [ -z "${1}" ]; then
	echo ""
	echo "Usage : run.sh ENVIRONMENT(prod, dev, ...)"
	echo "Examples:"
	echo "	run.sh prod"
	echo "	run.sh dev"
	echo ""
	exit 1
fi

if [ ! -e "./env.${1}" ]; then
	echo ""
	echo "./env.${1} file does not exist"
	echo ""
	exit 1
fi

docker stack deploy -c <(docker-compose -f docker-stack.yml --env-file=./env.${1} config) cortex_stack

