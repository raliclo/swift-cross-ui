#!/usr/bin/env zsh

cd ${0:A:h}/../APITool

swift run -c release APITool generate --scui-checkout .. \
  ../Sources/_SwiftCrossUIPortingKit/Generated
