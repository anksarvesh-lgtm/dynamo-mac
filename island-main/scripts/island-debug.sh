#!/usr/bin/env bash
# Sends a command to a running DEBUG build of Island: expand|collapse|search|next|music|timer|download|recording|critical|battery|clear|query:<text>
osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('dev.island.debug', '${1//\'/}', \$(), true)" >/dev/null
