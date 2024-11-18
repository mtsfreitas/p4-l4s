#!/usr/bin/env bash
echo ------------------------------------------------------------
echo Algorithm: $1

iperf -s -i 1 -Z $1
