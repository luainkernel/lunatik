#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the home directory memory-guard.cases reads, user/: a
# project's Claude Code memories, a lesson that names no place of the repository, one that names a
# skill, a project memory, the index, which lists the first, and a second lesson that names no place
# of the repository, which it does not list.
#
# Usage: bash tools/checks/cases/memory-guard.fixture.sh <dir>

memory=$1/user/.claude/projects/p/memory
mkdir -p "$memory" || exit 1
printf -- '---\nname: feedback-bare\ndescription: "Run the suite twice"\nmetadata:\n  type: feedback\n---\n\nRun the suite twice before reporting.\n' > "$memory/feedback_bare.md"
printf -- '---\nname: feedback-placed\ndescription: "Install before testing"\nmetadata:\n  type: feedback\n---\n\nInstall before testing.\nLives in .agents/skills/lunatik-cycle/SKILL.md.\n' > "$memory/feedback_placed.md"
printf -- '---\nname: project-batch\ndescription: "A batch of runs"\nmetadata:\n  type: project\n---\n\nThree runs in flight.\n' > "$memory/project_batch.md"
printf -- '- [Bare](feedback_bare.md) - run the suite twice\n' > "$memory/MEMORY.md"
printf -- '---\nname: feedback-loose\ndescription: "Run it once"\nmetadata:\n  type: feedback\n---\n\nRun the example once.\n' > "$memory/feedback_loose.md"

