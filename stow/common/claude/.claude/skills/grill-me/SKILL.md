---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time. Don't accept partial answers. Don't accept answers which are part of uncertain statements ot those which include additional questions. The discussion on each question must conclude with a clear choice made by me.

If a question can be answered by exploring the codebase, explore the codebase instead.

before each question, print an estimated progress marker -- rough sense of how far through the decision tree we are (e.g. `progress: ~3/10 branches resolved`, or `progress: ~30%, still need to cover error handling + rollout`). estimate is fine; it's a vibes-meter, not a contract. update as new branches surface.

ask questions as plain prose with lettered options inline -- not via picker tools or special multi-choice modes. format:

- one-paragraph context setting up the decision (constraints, current state, what's forced vs free).
- one-line `Question:` stating the actual choice.
- options `(a)`, `(b)`, `(c)` each as a short paragraph -- name the choice, then its consequences / what it implies.
- `Recc:` line with your recommendation and the reasoning, tying back to the constraints.
- `Pick?` to close.

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