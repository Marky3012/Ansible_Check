#!/bin/bash
systemctl is-active --quiet haproxy
exit $?
