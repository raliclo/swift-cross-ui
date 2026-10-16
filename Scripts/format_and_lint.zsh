#!/usr/bin/env zsh

cd ${0:A:h}/..

zsh Scripts/format.zsh
swiftlint lint --quiet
