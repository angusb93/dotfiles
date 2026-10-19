# Angus's agent instructions

These are common instructions for Angus's agents across all scenarios.

## General Guidelines

- Never use the em dash "—". Use plain dash "-" instead.
- When writing commit messages, NEVER auto-add your agent name as co-author.
- Use conventional commits with scope and ticket number, e.g. `feat(front-page): add dark mode (CON-31)`.
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated.
- When writing or substantially editing long Markdown files, put each full sentence on its own line.
  Preserve normal Markdown structure, but avoid wrapping multiple sentences onto one physical line.
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Communication

How you report the work matters as much as the work.
These rules apply to every response, including the reports subagents hand back.

- Lead with the answer.
  Put the conclusion, recommendation, or result in the first sentence, then give the reasoning behind it.
  Never make Angus read a build-up to find out what you decided.
- Use the shortest form that carries the information.
  A `file.ts:42` reference, a short list, or a small table beats a paragraph describing the same thing.
  Three tight sentences beat a well-organised page.
- Report outcomes, not process.
  Do not narrate which tools you are about to use, and do not recount the steps you took.
  The exception is when something went wrong and the path you took is what explains it.
- Cut the padding.
  Skip preambles, restatements of the question, and closing summaries of what you just said.
- Explain a term the first time you use it if it is specific to this codebase, this tool, or this domain.
  Prefer plain language wherever it is just as precise as the jargon.
- When an answer has to be long, structure it to be skimmed.
  Lead each bullet or section with its point, not with the context for the point.

## Angus's Opinions

When you are working on something that would benefit from being informed by Angus's viewpoints, read ~/OPINIONS.md to understand them.

## Voice Profile

When you are talking/posting on behalf of Angus using his identity, read ~/VOICE.md to see how Angus talks.
