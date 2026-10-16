#!/usr/bin/env zsh

cd ${0:A:h}/..

# Find and compile all *.gyb files in the Sources directory
find Sources -name '*.gyb' |
  while read file; do
    ./gyb/gyb --line-directive '' -o "$PWD/${file%.gyb}" "$PWD/$file"
    zsh Scripts/format.zsh "$PWD/${file%.gyb}"
  done
