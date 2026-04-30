---

name: obfuscation-design-principles
description: Core principles and reusable patterns for building robust, flexible, and unpredictable obfuscation systems in Lua-based obfuscators like Prometheus.
-----------------------------------------------------------------------------------------------------------------------------------------------------------------

# Obfuscator Skill

## Instructions

Focus on designing obfuscation features as modular, composable transformations rather than fixed pipelines. Each transformation ("step") should operate independently on the AST and expose configuration hooks for variability.

Prioritize **non-determinism**. Ensure outputs differ across runs by introducing controlled randomness in naming, ordering, encoding strategies, and transformation selection. Deterministic outputs reduce the effectiveness of obfuscation.

Maintain **semantic preservation**. Every transformation must guarantee identical runtime behavior. Build internal validation strategies (e.g., AST integrity checks or test execution) to ensure correctness.

Favor **layered obfuscation**. Combine multiple lightweight transformations (renaming, encoding, control flow changes) instead of relying on a single heavy technique. This increases resistance to deobfuscation.

Design for **analysis resistance**, not just readability reduction. Target both:

* Static analysis (structure, signatures, patterns)
* Dynamic analysis (debugging, tracing, instrumentation)

Use **AST-level transformations** instead of string manipulation. This ensures precision, reduces bugs, and allows deeper structural changes.

Incorporate **configurable presets**. Allow users to select different obfuscation strengths that toggle combinations of steps and randomness levels.

Ensure **performance awareness**. Avoid transformations that significantly degrade runtime unless explicitly enabled. Provide trade-offs between security and execution cost.

Build **extensibility**. New steps should be easy to add without modifying existing ones. Follow a consistent interface (e.g., `init`, `apply`, `finalize`).

Include **anti-pattern variation**. Avoid generating repeated structures or recognizable templates that deobfuscators can detect.

## Examples

* A variable renaming step that uses randomized name generation with different strategies (short names, unicode-like patterns, hashed names).
* A constant encoding step that alternates between arithmetic encoding, table lookups, and string-based reconstruction.
* A control flow step that sometimes flattens logic and other times injects fake branches, chosen randomly per run.
* A pipeline where step order is partially shuffled while respecting dependencies.
* A preset system where "Light" uses renaming only, "Medium" adds encoding, and "Strong" includes control flow and anti-analysis.
* A transformation that randomly decides whether to apply itself to a given AST node, increasing unpredictability.
* A modular step system where each obfuscation feature is implemented as a class extending a shared `Step` base.
