#!/usr/bin/bash
# Convert markdown readme to html readme
pandoc -f markdown -t html -o README.html README.md
