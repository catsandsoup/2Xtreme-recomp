# 2Xtreme recomp: instructions for AI agents

**Read [docs/PRODUCT_RULES.md](docs/PRODUCT_RULES.md) first, every session.**
It is the standing rule for this project. Apply each section before writing
code, and judge every milestone against its player goal and "Done means".

Working rules:

- Commit and push every change to `origin main` (the owner's standing
  request). Small commits, clear messages. Before each push, check that
  nothing copyrighted or derived from the disc is staged (release guard).
- Never commit disc images, BIOS dumps, memory cards, frame captures, ripped
  assets or local absolute paths (`/Users/...`).
- Experimental game changes (racer expansion, forced high-poly models,
  direct-track boot) stay opt-in and off by default, as controlled hooks,
  not hand edits to `generated/`.
- Prove features with fresh screenshots of the real build. A green test is
  not proof that a player can use it.
- Current audit and plan: [docs/M1_AUDIT.md](docs/M1_AUDIT.md).
