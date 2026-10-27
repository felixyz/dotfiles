# Code comments

## Keep them few, and write them for a future reader

Keep comments minimal and aimed at what a future reader will need. Never include information that only mattered while the code was being written or changed. After finishing a change, go over its comments once more and make sure they are plain, easy to take in, and about the crucial and non-obvious parts of the code.

## Short is good, cryptic is bad

Write for someone who was not part of the work that produced the code. Use literal verbs rather than metaphors ("appears when hovered", not "wakes"), name the thing rather than alluding to it (quote the UI text, or name the column or function), and state the mechanism rather than a belief about it. The test: if someone who has never seen this code reads the comment once, do they learn what it does and why, without re-reading? A plain two-line comment beats a one-line riddle.

Bad: a metaphor, and the reader must already know what "the invitation" is.

```
#   The invitation to word the other direction wakes with its pair.
```

Good: names the thing, and says what actually happens.

```
#   The "+ and the other way round" line appears when its pair is hovered.
```

## Line breaks follow the sentence

Line breaks in comments are semantic, never driven by width: don't fill lines up to a column limit. Break after a full sentence. Failing that, break after a comma, semicolon, colon, or dash, and failing that, at a clause boundary. Never split an article from its noun, a subject from its verb, or a phrasal verb: a long line is always better than a break mid-phrase. Each line then reads as a unit, and rewording one clause doesn't reflow the rest of the comment. This applies to every kind of comment, `@doc` and `@moduledoc` heredocs included.

Bad: filled to width, breaking mid-phrase.

```
--   A relation joins any pair already connecting the two entities, so both
--   directions hold one position in each concept's list.
```

Good: each line ends where the sentence pauses.

```
--   A relation joins any pair already connecting the two entities,
--   so both directions hold one position in each concept's list.
```

## State timeless facts

Words like "still", "now", "no longer", and "pre-" or "post-" only make sense relative to the moment the code was written. State the fact that stays true instead.

Bad: relative to the change being made.

```
# The trigger payload still holds the pre-rename plural.
```

Good: always true of the system.

```
# The payload's term_plural belongs to the previous term,
# and inflection-only updates fire no follow-up job.
```

Bad: history that a future reader does not care about.

```
# The pre-machine handler cleared the error flash on every successful upload;
# only the first-save path kept doing so.
```

Good: a reason the code does not state by itself.

```
# Commit re-derives the rows from current state rather than
# the previewed snapshot, so a pricing run landing between
# preview and commit is included.
```

Note that this rule only applies to comments. Commit messages describe a change, so "now", "used to", and "no longer" are informative there, and are the right words for its two sides. See [commit-messages.md](commit-messages.md).
