#!/usr/bin/env bash

tcpdump -XX -n -i eth0:s$1-eth$2 -w h$2.cap
