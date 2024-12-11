#!/bin/sh

docker run --rm -p 8080:80 -p 443:443 -v misp:/misp -v misp-install:/var/log --name ubuntu-test mpriest/ubuntu-test
