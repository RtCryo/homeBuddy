# homeBuddy

This file applies to the root workspace and to every service repository below it (`authBuddy/`, `finanzBuddy/`, `calendarBuddy/`).

## Language

- Write every commit message, pull request title and description, code comment, specification, documentation file, script, and other generated text in English, even when the conversation is in another language.
- User-facing UI copy is English as well, following each service's design-system content rules.

## Git workflow

- Implement every new feature (each OpenSpec change) on its own Git branch, created from the up-to-date default branch of the repository that owns the change. Never commit feature work directly to `main`.
- Name the branch after the change, for example `add-identity-service`.
- Open the pull request only after the change is archived (`openspec archive`), so the PR contains the implementation, the archived change, and the synced specs together.

## Workspace rules

@AGENTS.md
