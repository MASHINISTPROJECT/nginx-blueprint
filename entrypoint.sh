#!/bin/bash
cd /home/container

# Replace Startup Variables
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server (with exec to replace PID 1)
exec eval ${MODIFIED_STARTUP}
