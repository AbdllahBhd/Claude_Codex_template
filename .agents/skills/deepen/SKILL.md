---
name: deepen
description: Upgrade a task/prompt/spec to professional depth — pro-gaps, primary sources, methods, external validation — then hand back the rewritten version for approval
---

> Mirrored from .claude/commands/deepen.md by scripts/sync-codex.sh — edit the
> source file and re-run the script; do not edit this copy.
> $ARGUMENTS below means: the text the user typed after $deepen.


# /deepen — professional-depth upgrade for a task

Target: $ARGUMENTS (a draft prompt, a task description, or a file like SPEC.md /
task_plan.md; if empty, deepen the most recent task the user stated in this
conversation).

Make the task DEEPER, not bigger. Produce these four sections, then the rewrite:

## 1. The pro bar
What would a top professional in this exact domain do here that the current
task does NOT ask for? List only items that change the outcome's quality or
longevity — no gold-plating. Present each as a decision request (reporting.md
five-part format: what / why / decision+recommendation / relation tag / cost)
so the user picks what enters scope.

## 2. The raw material
Name the rawest sources the work should start from instead of digested
knowledge: official docs for the installed versions, changelogs, the
dependency's actual code, the real spec/standard, production data or logs,
the live rendered product. Be specific — name the exact pages/files, and fetch
the critical ones now if accessible.

## 3. Methods & tools
The specific techniques a specialist would use, mapped to what this template
already has (skills, agents, gates) plus anything missing worth a one-line
install from CATALOG.md. Name methods precisely ("characterization tests
before refactor", "RLS policy matrix"), not vibes ("be careful").

## 4. External validation
What — other than the author's or the user's opinion — will show the result is
right: named tests with expected results, measurable thresholds (Web Vitals,
analyzer zero-warnings, contrast ratios), gates, an adversarial review in fresh
context, or real-world evidence (device screenshot, production query). These
become the Done-when clauses of the rewritten task.

## Then: the rewrite
Rewrite the original task to ask for exactly the above — incorporating only
the pro-bar items the user approved (ask first if interactive), citing the raw
sources as required inputs, and ending with Done-when criteria built from
section 4. Keep it straight to the point; depth is in the requirements, not
the word count. Do NOT start executing — hand the rewritten task back and wait.
