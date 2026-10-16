#!/usr/bin/env zsh

cd ${0:A:h}/../APITool

swift run -c release APITool analyze --scui-checkout ..
