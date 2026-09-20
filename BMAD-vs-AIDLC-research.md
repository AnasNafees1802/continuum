# BMAD-METHOD vs AI-DLC: A Deep Research Report

**Two competing methodologies for structuring AI-assisted software development.**

Compiled: 2026-09-19 · Produced with the Continuum `deep-research` workflow
(6 search angles → 23 sources fetched → 113 claims extracted → adversarial 3-vote verification).

---

## How to read this report (confidence tiers)

This report is deliberately honest about certainty. The verification pass was **cut off partway
by a usage limit**, so not every claim got the full 3-vote adversarial check. Each fact below is
tagged:

- **[VERIFIED]** — passed adversarial verification 3 votes to 0 against a primary source.
- **[REFUTED]** — failed verification 0 to 3. Do not trust the claim as stated.
- **[SOURCED]** — extracted verbatim from a primary or reputable source, but the independent
  verification vote could not run (it errored on the session limit). Treat as reliable-but-unconfirmed.
- **[COMMUNITY]** — appears in blogs / secondary write-ups, not a primary project source. Directional.

Where a widely repeated "fact" did not survive verification, that is called out explicitly. That
disagreement is itself a finding.

---

## Executive summary

Both frameworks answer the same problem: **raw AI coding agents do not scale to real projects** —
they lose context, skip planning, and produce unreviewable output. Both wrap the agent in a
**structured, phased, human-gated process**. They differ in origin, shape, and where they put the human.

- **BMAD-METHOD** is a **community-driven, open-source** framework built around **named specialist
  agent personas** (product, architecture, UX, dev, testing) that collaborate through a
  plan-then-build loop. It is tool-agnostic (Claude Code, Codex, Gemini, ChatGPT, Cursor, web UIs)
  and in **very active development** (v6 line, latest release 2026-09-03). Its philosophy is
  collaboration and "you are the CEO directing a team of expert agents."

- **AI-DLC (AI-Driven Development Life Cycle)** is an **AWS-originated methodology** where **AI is
  the primary driver** — it drafts the plan, asks clarifying questions, and executes — while
  **humans stay in control at explicit approval gates**. It is organized into adaptive phases
  (Inception / Construction / Operations) and borrows "mob programming" ideas. It leans toward the
  AWS tooling ecosystem (Amazon Q Developer, awslabs reference implementations).

**Fastest mental model:** BMAD = *"a team of AI experts you direct."* AI-DLC = *"an AI that drives,
you approve at the gates."*

---

## Part 1 — BMAD-METHOD

### Origin and identity
- Repository: `bmad-code-org/BMAD-METHOD` on GitHub, creator **Brian "BMad" Madison**. **[COMMUNITY / widely reported]**
- "BMAD" is widely written out as **"Breakthrough Method for Agile AI-Driven Development."**
  **[COMMUNITY]** — Note: the compound claim *"name stands for X, maintained by BMad Code LLC,
  MIT-licensed, with 'BMad'/'BMAD-METHOD' as registered trademarks"* was **[REFUTED] (0-3)** as a
  single statement. The likely reason is that it bundled several assertions (acronym + legal entity
  + license + trademark status) and the current primary source did not confirm all of them together.
  The acronym itself is repeated across many secondary sources; the **trademark/LLC/license details
  should not be stated as fact** without checking the current repo's LICENSE and README directly.

### Core philosophy — "Vibe CEO"
- The framing is that **you act as the CEO** directing a team of specialized AI agents rather than
  writing code yourself, and that AI development should be **orchestration, not improvisation**.
  **[COMMUNITY]**

### How it actually works (mechanics)
- The **current README** describes a **phased delivery loop: Clarify → Plan → Build-and-Verify**,
  with a **Learn-and-Adjust** feedback mechanism, drawing on **specialized perspectives across
  product, architecture, UX, development, and testing.** **[VERIFIED, 3-0]**
  (Source: github.com/bmad-code-org/BMAD-METHOD)
- Community / secondary write-ups describe the classic BMAD shape as a **two-phase flow**:
  1. **Agentic planning** — Analyst, Product Manager, and Architect agents produce a **PRD** and an
     **architecture document**.
  2. **Core dev cycle** — a **Scrum Master** shards the plan into stories, then **Dev** and **QA**
     agents implement and verify them. **[COMMUNITY]**
- A head-to-head write-up describes BMAD as **4 sequential phases (Analysis, Planning, Solutioning,
  Implementation)** using **domain-specific named agent personas.** **[COMMUNITY]**

> **Important nuance on versions:** The framework is on the **v6 line** and moving fast. A specific
> claim that *"v6.0.0 was the beta→stable transition with a consolidated Phase-4 chain
> (bmad-sprint-planning → bmad-build → bmad-code-review)"* was **[REFUTED] (0-3)** — do not cite that
> exact structure. What *is* confirmed is only that active v6 development is real (below). The named
> six-persona model (Analyst/PM/Architect/SM/Dev/QA) is the **historically documented** shape; the
> exact agent set and phase names in the **latest** v6 release should be re-checked against the repo
> before relying on them, because the current README frames it as the leaner Clarify/Plan/Build loop.

### Tooling and integration
- Installs via the **Skills CLI**: `npx skills add bmad-code-org/BMAD-METHOD`. Integrates with
  **Claude Code (plugin)**, **Codex (plugin)**, and ships **web bundles for Google Gemini Gems and
  ChatGPT Custom GPTs.** **[VERIFIED, 3-0]** Cursor and other IDEs are also supported per community docs. **[COMMUNITY]**
- **Expansion packs**: BMAD is designed to extend beyond software (other domains use the same
  agent-orchestration engine). **[COMMUNITY]**

### Maturity
- **Latest documented release: v6.12.0, dated 2026-09-03** — confirming the framework is in
  **active v6 development.** **[VERIFIED, 3-0]** (Source: repo CHANGELOG.md)
- Large, active community; strong grassroots adoption and popularity. **[COMMUNITY]**

### Strengths
- Tool-agnostic and free; runs anywhere an agent can read instructions.
- Explicit, legible planning artifacts (PRD, architecture, stories) that a human can review.
- Named personas make responsibilities obvious and the workflow easy to reason about.
- Very active community and rapid iteration.

### Weaknesses / criticism
- **Context bloat**: the sharpest critique (Anderson Santos, "You should BMAD — Part 2") notes that
  **PRDs and architecture files can exceed tens of thousands of tokens**, which breaks on smaller
  models or limited context windows and inflates cost. **[COMMUNITY]**
- Heavy process for small tasks; the full persona ceremony can be overkill.
- Fast-moving version churn means docs and community tutorials drift out of date quickly (as this
  report itself found — several "well-known" structural claims did not match the current repo).

---

## Part 2 — AI-DLC (AI-Driven Development Life Cycle)

> **Verification caveat:** almost all AI-DLC mechanics below are **[SOURCED]** from AWS primary
> sources (AWS DevOps blog, AWS Industries blog, awslabs GitHub, awslabs docs, aws-samples repos)
> but their independent verification votes **errored out on the session limit** before completing.
> Only the top-line "AI as primary driver" claim got a full **[VERIFIED]**. Treat the rest as
> reliable-but-unconfirmed and re-run verification when the limit resets.

### Origin and identity
- **AWS-created / AWS-originated** methodology. **[SOURCED]**
- Attributed to **Raja SP and his team** at AWS. **[SOURCED]** (aws.amazon.com/blogs/devops)
- Reference implementations live under the **awslabs** GitHub org (`awslabs/aidlc-workflows`) and
  **aws-samples** (`sample-collaborative-ai-dlc`). **[SOURCED]**

### Core idea
- **AI is the primary driver, with human oversight**: *"AI systematically creates detailed work
  plans, actively seeks clarification and guidance, and defers critical decisions to humans."*
  **[VERIFIED, 3-0]** (Source: aws.amazon.com/blogs/devops/ai-driven-development-life-cycle)
- The developer's role **shifts from author of code to validator of AI output.** **[SOURCED]**
- AI agents **orchestrate the whole lifecycle** (plans, code, tests, and Infrastructure-as-Code),
  and humans verify/approve before execution proceeds. **[SOURCED]**

### Phases
- Documented as **three adaptive phases** that scale rigor to complexity:
  1. **Inception** — the WHAT/WHY. Requirements, intent, context building.
  2. **Construction** — the HOW. AI proposes architecture, domain models, code, and tests.
  3. **Operations** — running and maintaining. **[SOURCED]**
- One awslabs reference implementation expands this into **five workflow phases** (Initialization,
  Ideation, Inception, Construction, Operation) — i.e. the *methodology* is 3 phases, a specific
  *implementation* subdivides further. **[SOURCED]**

### Signature concepts
- **Mob elaboration / Mob programming**: in Inception, cross-functional teams (or a "mob" of
  broadly capable agents modeled on a 3-5 person mob) collaborate to build shared context, rather
  than narrow single-responsibility specialists. **[SOURCED]** *(This is a philosophical contrast
  with BMAD's narrow named personas.)*
- **"Mob Construction"** in the Construction phase (AI proposes architecture/models/code/tests
  collaboratively). **[SOURCED]**
- **Bolts** replace Agile **sprints** (work cycles measured in **hours or days**, not weeks), and
  **"units of work"** replace **epics**. **[SOURCED]**
- **Human-in-the-loop approval gates** at each phase: the AI asks clarifying questions, creates an
  execution plan, and **waits for human approval before proceeding**; an ambiguous decision
  **pauses the run with preserved state** and resumes only after a human answers. **[SOURCED]**

### Tooling
- Closely associated with **Amazon Q Developer** and the AWS agent tooling ecosystem. **[SOURCED]**
- awslabs frames its core as **"harness-neutral"** (meant to work across coding assistants), and
  `sample-collaborative-ai-dlc` positions AI-DLC as a **shared orchestration and governance layer
  over existing coding agents, not another coding assistant.** **[SOURCED]** *(So AWS's own framing
  is "not locked to one tool" — though gravity toward the AWS ecosystem is real.)*

### Maturity
- Newer and more **enterprise / AWS-ecosystem** oriented than BMAD; strong on **governance, audit
  trail, and traceability** (one reference impl cites source-bound review evidence and a persisted
  audit trail). **[SOURCED]** Grassroots community adoption is smaller than BMAD's. **[COMMUNITY]**

### Strengths
- AI does the heavy lifting; humans focus on decisions and validation.
- Built-in governance, approval gates, and traceability — attractive for regulated / enterprise
  contexts (there is even an AWS "AI-DLC for financial services" writeup).
- Adaptive rigor: comprehensive for complex work, lightweight for simple work.

### Weaknesses / criticism
- Younger, less battle-tested by an independent community than BMAD.
- Gravity toward the AWS ecosystem (Amazon Q Developer) despite the "harness-neutral" framing.
- A critical review ("A critical yet hopeful view," Data Science Collective) exists; the
  developer-as-validator model is a real cultural shift that not every team will accept.

---

## Part 3 — Head-to-head

| Dimension | **BMAD-METHOD** | **AI-DLC** |
|---|---|---|
| **Origin** | Community / open-source; Brian "BMad" Madison **[COMMUNITY]** | AWS; Raja SP and team **[SOURCED]** |
| **Core philosophy** | You are the CEO directing a team of **named expert agents**; collaboration | **AI is the primary driver**; human approves at gates **[VERIFIED]** |
| **Structure** | Plan-then-build loop (Clarify/Plan/Build-and-Verify) **[VERIFIED]**; classic 4-phase / 6-persona shape **[COMMUNITY]** | 3 adaptive phases: Inception / Construction / Operations **[SOURCED]** |
| **Unit of work** | Stories sharded from a PRD **[COMMUNITY]** | "Units of work" + "bolts" (hours/days) **[SOURCED]** |
| **Where the human stays in control** | Reviews planning artifacts (PRD, architecture) and story output | Explicit **approval gates** each phase; run pauses on ambiguity **[SOURCED]** |
| **Agent model** | **Narrow specialist personas** (Analyst, PM, Architect, SM, Dev, QA) | **Broad "mob"** of capable agents modeled on mob programming **[SOURCED]** |
| **Tooling** | Tool-agnostic: Claude Code, Codex, Gemini Gems, ChatGPT GPTs, Cursor, web **[VERIFIED]** | AWS-leaning (Amazon Q Developer); framed "harness-neutral" **[SOURCED]** |
| **Lock-in** | Very low (open, portable instructions) | Low by design, but ecosystem gravity toward AWS **[SOURCED]** |
| **Artifacts** | PRD, architecture doc, sharded stories | Plans, code, tests, IaC + audit trail / review evidence **[SOURCED]** |
| **Learning curve** | Moderate: learn the personas and the phase flow | Moderate: learn the gates, phases, and mob model |
| **Governance/audit** | Lighter; artifact-driven | Stronger; explicit gates + traceability **[SOURCED]** |
| **Maturity** | Active v6, latest 2026-09-03; large community **[VERIFIED]** | Newer; enterprise/AWS-oriented **[SOURCED]** |
| **Best for** | Individuals & teams wanting a free, portable, expert-team workflow | Enterprises wanting governed, auditable, AI-driven delivery |

---

## Part 4 — When to use which (and can they combine?)

**Use BMAD when:**
- You want something **free, open, and portable** across whatever agent you happen to use.
- You value **explicit, reviewable planning artifacts** (PRD, architecture) and a clear division of
  labor among named roles.
- You are an individual or small team and want strong community support and rapid iteration.
- Watch out for: context/token bloat on large PRDs; keep documents lean, especially on smaller models.

**Use AI-DLC when:**
- You are in an **enterprise / regulated** setting that needs **governance, approval gates, and an
  audit trail**.
- You are comfortable letting **AI drive** and positioning developers as **validators**.
- You are already in or near the **AWS / Amazon Q Developer** ecosystem.

**Can they be combined?**
They are **not mutually exclusive** — they operate at different emphases. BMAD's strength is a
**structured multi-agent team and planning artifacts**; AI-DLC's strength is **AI-driven execution
with hard human gates and governance**. A plausible hybrid: use **BMAD-style specialist planning**
(PRD + architecture + stories) to produce the intent, then run **AI-DLC-style gated construction**
with approval checkpoints and an audit trail for execution. No primary source documents an official
combined workflow, so treat this as a **design suggestion, not a documented pattern**.

> **Relevance to Continuum:** both frameworks assume the AI has good, structured, persistent context
> to work from — a PRD, an architecture doc, phase state, approval history. Neither solves
> **continuity across tools or across a hit usage limit**. That is exactly Continuum's lane: BMAD or
> AI-DLC can define *how* you work within a session; Continuum's `.aicontext/` ledger is what lets
> that work **survive a tool switch or a context wipe**. They are complementary layers, not competitors.

---

## Part 5 — What we could NOT confirm (honesty section)

Verification was interrupted by a usage limit, so these should be **re-verified** before you rely on
or publish them:

- The full AI-DLC phase/stage/agent counts from `awslabs/aidlc-workflows` (e.g. "5 phases, 33 stages,
  14 agents, 11 workflow profiles" and "99-event audit trail") — **[SOURCED but unverified]**.
- The exact "bolts / units of work" terminology and definitions — **[SOURCED but unverified]**.
- "Mob elaboration" / "mob construction" as literal AWS terms vs paraphrase — **[SOURCED but unverified]**.
- BMAD's **legal/trademark/license** specifics and the **current** v6 agent set and phase names —
  the compound legal claim and one specific v6 phase-chain claim were **[REFUTED]**; re-check the
  live repo LICENSE, README, and CHANGELOG directly.

**To finish verification** (after the session limit resets), re-run the same workflow — completed
agents replay from cache, so only the failed verification votes and the synthesis step re-run:

```bash
# resume the deep-research run, replaying cached fetch/search agents
```
(Use the `Workflow` resume with `resumeFromRunId: "wf_d6f4934b-298"`.)

---

## Sources

**Primary**
- BMAD-METHOD repo — https://github.com/bmad-code-org/BMAD-METHOD
- BMAD-METHOD CHANGELOG — https://github.com/bmad-code-org/BMAD-METHOD/blob/main/CHANGELOG.md
- AWS DevOps blog, AI-DLC — https://aws.amazon.com/blogs/devops/ai-driven-development-life-cycle
- AWS DevOps blog, building with AI-DLC + Amazon Q — https://aws.amazon.com/blogs/devops/building-with-ai-dlc-using-amazon-q-developer
- AWS DevOps blog, open-sourcing adaptive AI-DLC workflows — https://aws.amazon.com/blogs/devops/open-sourcing-adaptive-workflows-for-ai-driven-development-life-cycle-ai-dlc/
- AWS Industries blog, AI-DLC for financial services — https://aws.amazon.com/blogs/industries/ai-driven-development-lifecycle-for-financial-services/
- awslabs/aidlc-workflows — https://github.com/awslabs/aidlc-workflows
- awslabs AI-DLC docs — https://awslabs.github.io/aidlc-workflows/guide/00-introduction/
- aws-samples/sample-collaborative-ai-dlc — https://github.com/aws-samples/sample-collaborative-ai-dlc
- AWS Agent Toolkit — https://aws.amazon.com/products/developer-tools/agent-toolkit-for-aws/

**Secondary / community**
- BMAD vs AI-DLC head-to-head (DEV) — https://dev.to/jamilxt/bmad-method-vs-ai-dlc-two-ai-development-frameworks-compared-475e
- Augment Code, BMAD guide — https://www.augmentcode.com/guides/bmad-method-ai-development
- DeepWiki, BMAD IDE integration — https://deepwiki.com/bmad-code-org/BMAD-METHOD/2.2-ide-integration
- "Mastering the BMAD Method" (Medium) — https://medium.com/@courtlinholt/mastering-the-bmad-method-a-revolutionary-approach-to-agile-ai-driven-development-for-modern-e7be588b8d94
- "You should BMAD — Part 2" critical analysis — https://adsantos.medium.com/you-should-bmad-part-2-a007d28a084b
- BMAD: reclaiming control (Benny Cheung) — https://bennycheung.github.io/bmad-reclaiming-control-in-ai-dev
- ELEKS, AWS AI-DLC explained — https://eleks.com/blog/aws-ai-dlc-explained/
- TTPSC, how AWS AI-DLC defines an AI-native methodology — https://ttpsc.com/en/blog/how-aws-ai-dlc-defines-an-ai-native-methodology/
- "AI-DLC: a critical yet hopeful view" — https://medium.com/data-science-collective/the-ai-driven-development-lifecycle-ai-dlc-a-critical-yet-hopeful-view-edc966173f2f

*Report generated from 23 fetched sources and 113 extracted claims. 4 claims fully verified (3-0),
2 refuted (0-3), 19 sourced-but-unverified (verification interrupted by usage limit).*
