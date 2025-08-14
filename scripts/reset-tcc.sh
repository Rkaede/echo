#!/usr/bin/env bash
set -euo pipefail

tccutil reset Microphone io.littlecove.echo
tccutil reset Accessibility io.littlecove.echo
tccutil reset Microphone io.littlecove.echo.dev
tccutil reset Accessibility io.littlecove.echo.dev

