#!/usr/bin/env bash
echo ------------------------------------------------------------
echo Algorithm: $1

iperf -Z $1 -c 10.0.$2.$3 -i 1 -t $4
