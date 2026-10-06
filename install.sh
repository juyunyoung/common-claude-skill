#!/bin/bash
mkdir -p ~/.claude
[ -f ~/.claude/CLAUDE.md ] && [ ! -L ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak
ln -sf "$(cd "$(dirname "$0")" && pwd)/CLAUDE.md" ~/.claude/CLAUDE.md
echo "연결 완료: ~/.claude/CLAUDE.md"
