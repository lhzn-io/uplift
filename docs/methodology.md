# Methodology

**Status:** Scaffolded. The sections that depend on a literature pass
(§§1–6 below) are intentionally empty rather than speculatively filled.
The framing, trace-schema commitments, and Key Metric posture are not
stubs — they are the project's non-negotiable evaluation contract.

## Purpose

This document is the methodological backbone of Uplift Core. It exists
to make the project's evaluation claims legible, citable, and
falsifiable. If you are a researcher in causal ML, uplift modeling, or
human–AI teaming and you want to know whether this project is doing
something rigorous or just borrowing your vocabulary, this is the
document to read.

## Why this matters now

The AI-agent space is awash in frameworks that compete on architecture,
model choice, tool surface, and leaderboard scores on synthetic
benchmarks. Recent literature has diagnosed this as a methodology
crisis: the industry evaluates complex, non-deterministic agentic
systems using the equivalent of static multiple-choice tests. Point
estimates like Pass@1 are reported without confidence intervals and
ignore the agent's dynamic reasoning, the friction of real-world
deployment, and — most importantly — whether the assisted human
operator actually did their job better than they would have unaided.

Almost none of these frameworks can answer, with any rigor, the
question *"did this thing actually help a real human do real work in a
real place."* The evaluation culture is dominated by aggregate
win-rates and vibes.

Meanwhile, two mature literatures have spent decades building exactly
the methodology this space needs:

1. **Uplift modeling** (a.k.a. heterogeneous treatment effect
   estimation, CATE/ITE, causal ML) — developed in marketing and
   biostatistics, designed precisely to answer *"which intervention
   helps which subpopulation, by how much, vs. doing nothing."*
2. **Causal evaluation of human–AI teams** — a smaller but growing
   body of work that measures the incremental effect of AI assistance
   on human task performance with proper controls (Copilot
   productivity studies, BCG/Harvard "centaur" studies, clinical AI
   assistance trials, customer-support agent-assist studies).

These two literatures have not yet been brought together and pointed
at LLM-driven agent stacks deployed on real operators in the field.
That gap is where Uplift Core operates.

## Position in one paragraph

Uplift Core treats each release, prompt change, model swap, or tool
addition as a *treatment*, treats real operator outcomes as the
*response*, and aims to estimate heterogeneous treatment effects
across operator subpopulations and task cohorts in field deployments
(aquaculture platform, food bank). We are downstream consumers of the
uplift modeling and causal ML literatures — not a causal inference
library ourselves. Where we need estimators, we pull them from
[scikit-uplift](https://github.com/maks-sh/scikit-uplift),
[upliftml](https://github.com/bookingcom/upliftml), and CausalML, and
cite generously.

## Sections to populate

The following sections will be filled in as the literature review
returns and as the `uplift/` module matures. Each is intentionally
empty rather than speculatively filled — placeholder prose here would
defeat the document's purpose.

### 1. Foundations of uplift modeling and HTE estimation
*To be populated.* Canonical references for uplift modeling, CATE/ITE,
meta-learners (S/T/X/R/DR), causal forests, doubly robust methods,
both the marketing/CRM and the medical/biostatistics lineages.

### 2. Causal evaluation of human–AI teams
*To be populated.* Studies measuring incremental effect of AI
assistance on human task performance with proper controls — Copilot
productivity studies, BCG/Harvard "centaur" studies, clinical AI
trials, customer-support agent-assist work. Methodologically strong
and weak examples, with notes on which is which.

### 3. Counterfactual and off-policy evaluation of LLM agents
*To be populated.* Counterfactual analysis of agent trajectories,
off-policy evaluation, credit assignment over tool calls.

### 4. Heterogeneous treatment effects of AI assistance
*To be populated.* Who does AI assistance help, who does it hurt,
under what conditions. The "AI helps low-skill workers more" findings
and any contradicting work.

### 5. Field measurement in low-resource / high-stakes operational settings
*To be populated.* Methodology for measuring operator uplift in messy
real-world deployments where clean RCTs are hard. Aquaculture,
fisheries, food security, humanitarian logistics, community health
workers.

### 6. Critiques of current agent / LLM evaluation
*To be populated.* Calls for causal evaluation standards,
reproducibility issues in agent benchmarks, Goodhart effects.

## Key Metrics (per anchor deployment)

Each anchor deployment will have at least one causal Key Metric
reported on every release, *including the bad numbers, with
confidence intervals*. These are **operator-centric**, not
model-centric — the unit of analysis is the human doing the work.

### Aquaculture platform

Operators on an offshore platform manage sensors, feeders,
water-quality alerts, and intervention decisions. Operator time is
scarce, conditions are harsh, and the network is intermittent (hence
the edge-inference architecture).

**Primary Key Metric:** time-to-correct-action on alerts, on matched
task cohorts, with vs. without the stack.

**Primary HTE slice:** effect stratified by operator experience. The
specific question: does the stack close the skill gap (help
less-experienced operators more), or widen it (a known AI-assistance
failure mode)? Both outcomes are legitimate findings and must be
reported honestly.

### Food bank

Intake, inventory, routing, and beneficiary-facing operations in a
resource-constrained nonprofit setting. Operators are often
volunteers with high turnover and heterogeneous training.

**Primary Key Metric:** throughput per operator-hour, on matched
shift cohorts, with vs. without the stack. Secondary: intake error
rate.

**Primary HTE slice:** effect on the *median* volunteer, not only on the
most technically sophisticated ones. A stack that accelerates
power-users while leaving most volunteers unaffected fails the
mission regardless of the aggregate number.

### Why these two deployments

Both sites share the three properties that make them ideal anchor
sites for causal evaluation:

- Operator time is scarce and **measurable**.
- Operator populations are **heterogeneous** in ways uplift modeling
  is literally designed for.
- Stakeholders (funders, partners, regulators) will actively reward
  rigorous measurement rather than punish it.

## Trace schema commitments

The agent trace schema must support causal analysis from day one,
even before the estimators are sophisticated. Specifically:

- A run is taggable as `baseline` or `assisted` (or a richer
  treatment label). The *data model* supports counterfactual
  analysis even when the estimators are naive.
- A run is associated with an operator identifier, a task cohort,
  and one or more outcome measurements.
- The `uplift/` module exposes a `TreatmentEffect` type and a CLI
  that computes a naive ATE on two matched run sets, with hooks for
  swapping in scikit-uplift / upliftml / CausalML estimators. The
  word "uplift" appears in the *type system*, not only in the
  README.

These three commitments are non-negotiable from v0.1 onward.

## Literature review prompt (for an academic research agent)

The following prompt is the canonical brief handed to an academic
research agent (e.g. Ai2 Asta) to populate the literature sections
above. Keep it in sync with the project's framing — if the thesis
shifts, this prompt shifts with it.

```
I'm building an operational AI-agent stack ("Uplift Core") deployed on edge
hardware (NVIDIA Jetson Orin AGX) for human operators in real-world field
settings — specifically aquaculture platforms and food banks. My thesis is
that agent frameworks should be evaluated the way clinical and marketing
interventions are: by estimating the *causal uplift* the stack produces on
real human operators, with proper treatment/control structure and attention
to heterogeneous treatment effects (HTE) across operator subpopulations,
tasks, and contexts. I want to bring the rigor of uplift modeling / causal
inference into agent framework validation, where today evaluation is
dominated by aggregate benchmark win-rates and vibes.

Please find and summarize the most relevant academic papers, preprints, and
technical reports across the following intersecting areas. For each paper,
give: full citation, year, venue, a 2–4 sentence "why this matters to us"
note grounded in the use case above, and a link (arXiv / DOI / OpenReview).
Prefer recent work (2020–present) but include foundational older work where
it's load-bearing.

Areas to cover:

1. **Foundations of uplift modeling and heterogeneous treatment effects.**
   Canonical references for uplift modeling, CATE/ITE estimation, meta-
   learners (S/T/X/R/DR-learner), causal forests, doubly robust methods.
   Both the marketing/CRM lineage and the medical/biostatistics lineage.

2. **Uplift modeling and causal ML applied outside marketing.** Especially
   any work applying it to: human–AI collaboration, decision support
   systems, recommender systems evaluated causally, education / tutoring,
   healthcare decision aids, field operations, agriculture, robotics, or
   humanitarian / development settings. The further from marketing
   attribution, the more interesting.

3. **Causal evaluation of AI assistants and human–AI teams.** Studies that
   measure the *incremental* effect of an AI assistant on human task
   performance with proper controls (RCTs, quasi-experiments, matched
   cohorts). E.g. the GitHub Copilot productivity studies, BCG/Harvard
   "centaur" studies, radiology/clinical AI assistance trials, customer
   support agent-assist studies. I want both the methodologically strong
   and the methodologically weak ones, with notes on which is which.

4. **Counterfactual and off-policy evaluation of LLM agents and tool use.**
   Work on evaluating agent trajectories counterfactually, off-policy
   evaluation for LLM agents, causal analysis of agent traces, credit
   assignment over tool calls, and any attempts to estimate "what would
   have happened if the agent had chosen differently at step k."

5. **Heterogeneous treatment effects of AI assistance.** Papers showing
   that AI assistance helps some user subpopulations and hurts others
   (e.g. the "AI helps low-skill workers more" findings, and any
   contradicting work). HTE methodology applied specifically to AI tools.

6. **Field deployment and measurement of AI in low-resource / high-stakes
   operational settings.** Especially aquaculture, fisheries, food
   security, food banks, humanitarian logistics, smallholder agriculture,
   community health workers. Methodology papers on how to measure operator
   uplift in messy real-world deployments where clean RCTs are hard.

7. **Critiques and open problems.** Papers arguing that current agent /
   LLM evaluation is methodologically broken, calls for causal evaluation
   standards, reproducibility crises in agent benchmarks, Goodhart issues,
   etc. I want to know what the smartest critics are saying.

For each area, also identify 2–3 *active research groups or individual
authors* whose work I should follow, with their affiliation and a one-line
note on why. I'm specifically looking for people I might credibly approach
as collaborators or reviewers — bias toward people who seem open to
applied/operational partnerships rather than pure-theory groups.

Finally, end with a short "synthesis" section (≤300 words) on where you
think the genuine open problems are at the intersection of (uplift
modeling) × (LLM agent evaluation) × (field-deployed human–AI teams),
and which 3–5 papers I should read first if I only had a weekend.

Output as a single Markdown document with clear section headers. Do not
pad — skip any section where you genuinely can't find quality work, and
say so explicitly rather than filling it with weak hits.
```

## How to contribute to this document

If you are a researcher and you think we are misreading the
literature, citing the wrong things, or missing something important:
please open an issue or PR. See the **Collaborators wanted** section
of the project [`README.md`](../README.md) for the specific research
directions where we are actively seeking input.
