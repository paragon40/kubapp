#!/bin/bash

s=$(stat -c "%a" README.md)
echo "$s"
dhd 
