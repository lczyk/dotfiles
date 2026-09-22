---
name: grill-me
description: interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. use when the user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

interview me relentlessly about every aspect of this plan until we reach a shared understanding. walk down each branch of the design tree, resolving dependencies between decisions one by one. for each question, give your recommended answer.

ask one question at a time. don't accept partial answers, answers wrapped in uncertain statements, or answers that include further questions -- each question ends with a clear choice made by me.

if the codebase can answer a question, explore the codebase instead of asking.

before each question, print a rough progress marker for the decision tree (e.g. `progress: ~3/10 branches resolved`, or `progress: ~30%, still need to cover error handling + rollout`). a vibes-meter, not a contract; update it as new branches surface.

ask in plain prose with lettered options inline -- no picker tools or multi-choice modes:

- one paragraph of context for the decision (constraints, current state, what's forced vs free)
- one `Question:` line stating the actual choice
- options `(a)`, `(b)`, `(c)`, each a short paragraph: name the choice, then its consequences
- a `Recc:` line with your pick and the reasoning, tied back to the constraints
- `Pick?` to close

shape sketch (not a verbatim template):

> progress: <~N/M branches resolved, or ~X%, + what's still uncovered>
>
> <context paragraph: constraints, current state, forced vs free>
>
> Question: <the actual choice>
>
> (a) <name>. <consequences / implications>.
> (b) <name>. <consequences / implications>.
> (c) <name>. <consequences / implications>.
>
> Recc: <letter>. <reasoning tied to constraints>.
>
> Pick?
