#!/bin/bash

docker run --rm -d -p ${1-80}:80 vectorim/element-web
