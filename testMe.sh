#!/bin/bash
echo "-----------------------------------------------------------------$?"
if [[ $? -ne 0 ]]; then
echo "true"
else
echo "false"
fi