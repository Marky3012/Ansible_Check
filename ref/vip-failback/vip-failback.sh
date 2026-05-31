#!/bin/bash

DC_VIP="192.168.3.183"

STATE="NORMAL"

echo "==== VIP Failback Script Started ===="

while true; do

    ping -c 2 $DC_VIP > /dev/null 2>&1
    DC_STATUS=$?

    case $STATE in

    NORMAL)
        if [ $DC_STATUS -ne 0 ]; then
            echo "$(date) - DC DOWN → entering MONITOR mode"
            STATE="MONITOR"
        fi
        ;;

    MONITOR)
        if [ $DC_STATUS -eq 0 ]; then
            echo "$(date) - DC BACK UP → wait 5 min stabilization"
            sleep 300   # 5 minutes

            ping -c 2 $DC_VIP > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "$(date) - DC stable → trigger failback"

                echo "$(date) - Stopping keepalived (release VIP)"
                systemctl stop keepalived

                echo "$(date) - Waiting 10 min before rejoining"
                sleep 600   # 10 minutes

                echo "$(date) - Starting keepalived"
                systemctl start keepalived

                echo "$(date) - Entering COOLDOWN mode"
                STATE="COOLDOWN"
            else
                echo "$(date) - DC unstable → stay in MONITOR"
            fi
        fi
        ;;

    COOLDOWN)
        if [ $DC_STATUS -ne 0 ]; then
            echo "$(date) - DC DOWN again → restarting MONITOR mode"
            STATE="MONITOR"
        else
            echo "$(date) - Cooldown active → ignoring DC UP"
        fi
        ;;

    esac

    sleep 10
done
