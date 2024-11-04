#!/usr/bin/env bash

iperf -c 10.0.$1.$2 -u -i 1 -t $3 -b $4M
