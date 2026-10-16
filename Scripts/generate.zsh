#!/usr/bin/env zsh

cd ${0:A:h}

zsh generate_gyb.zsh

zsh generate_gtk.zsh

zsh generate_porting_kit.zsh
