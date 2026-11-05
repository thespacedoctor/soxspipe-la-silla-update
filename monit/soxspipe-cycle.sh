#!/bin/bash
# SET PATH
PATH=:/diska/home/pipeline/miniforge3/envs/soxspipe/bin/

# EXIT IF ANY COMMAND FAILS
set -e

soxspipe -p reduce all /diska/home/pipeline/soxspipe_reductions/ -b 25

exit 
