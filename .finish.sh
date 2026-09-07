#!/bin/bash
export PATH="/Users/rik/.local/share/mise/installs/gh/latest/gh_2.96.0_macOS_arm64/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd ~/development/say-it-like-you-say-it || exit 1
rm -f .push.sh .inspect.sh
find .git -name '*.lock' -delete 2>/dev/null

git remote set-url origin git@github.com:rikkus/say-it-like-you-say-it.git
git fetch -q origin

# adopt the history already on GitHub, keep our working tree
git reset -q --mixed origin/main
git add -A
if git diff --cached --quiet; then
  echo "NOTHING_TO_COMMIT"
else
  git -c user.name="Rik Hemsley" -c user.email="rik@hemsley.cc" commit -q -m "Add CLAUDE.md, .gitignore and a full README

CLAUDE.md documents the DSP layout, the speaker-relative calibration idea, and
the constraints that must not be undone: phrase-final targets, one microphone
consumer at a time on iOS, ScriptProcessorNode over AudioWorklet, no color-mix
in canvas fillStyle, and encodeURIComponent on the submission payload.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Ce3jBgSMnQsisNxsq26MMX"
  echo "COMMITTED"
fi

echo "== push =="
git push -u origin main 2>&1 | tail -3

echo "== pages =="
gh api repos/rikkus/say-it-like-you-say-it/pages 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('already enabled:', d.get('html_url'), '| status:', d.get('status'), '| branch:', (d.get('source') or {}).get('branch'))" \
 || {
      echo "not enabled yet, enabling..."
      gh api -X POST repos/rikkus/say-it-like-you-say-it/pages \
        -f "source[branch]=main" -f "source[path]=/" 2>&1 | head -5
    }

echo "== final state =="
git log --oneline | head -4
git status --short
echo "(clean above means all committed)"
