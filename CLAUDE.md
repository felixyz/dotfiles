## Code comments

* Keep comments minimal and oriented to what a future human reader will need. Don't ever include information that is only relevant in the context when the code was added or modified. Make an extra pass over comments after completing a task, to make sure they are plain, easily digested, and focused on crucial and non-obvious aspects of the code.

* Earn the comment first. Before writing one, ask: is this something a future reader ACTUALLY needs, that is easily overlooked or would take them a long time to work out? If not, write nothing. The default is no comment. Code that a competent reader can follow needs none, and a comment that restates the code in prose is worse than silence.

  What earns a comment: a trap (delete this class and scrolling silently breaks), a non-local constraint (this column order must match that table), a rule the reader cannot see from here (this API returns null for X). What does not: describing what the code plainly does, narrating the design, or justifying the approach. The last of those belongs in the commit message. Example:

   Bad: exposition — restates the structure the code already shows

   ```
   #   The header sits outside the scrolling box rather than stuck to its top
   #   edge, so nothing can move it. The list scrolls in the sibling below it.
   ```

   Good: the one thing a reader would otherwise remove by accident

   ```
   #   A flex child will not shrink below the height of its content.
   #   Without min-h-0 this box is as tall as everything in it, and the
   #   column scrolls instead of this box.
   ```

* Use the Oxford comma. A list of three or more takes a comma before its final "and" or "or", so "a head, an operator, and a tail", never "a head, an operator and a tail". This holds in comments, doc strings, commit messages, exception messages, and this document. Example:

   Bad: the last two items read as one

   ```
   --   The id, the name and the checks stay.
   ```

   Good: three items, three
   ```
   --   The id, the name, and the checks stay.
   ```

* Show the rule working rather than describing it. One concrete instance, written out, saves the reader the work of applying an abstract statement. Example, on a test that asserts "SKU" takes "an" and "URL" takes "a":

   Good: the reader hears the rule before they have finished the first line

   ```
   #   "an ess-kay-you", "a you-are-ell". The article follows how the first
   #   letter is pronounced, so U takes "a" for the same reason "user" does.
   ```

* The only sentence punctuation allowed in a comment is the full stop and the comma. No colons, semicolons, dashes, parentheses, or ellipses. Quotation marks, apostrophes, and backticks are not sentence punctuation and stay. A colon or a semicolon almost always hides a link the writer never made explicit, and the reader has to guess it. Two plain sentences say it better. Two exceptions carry a colon, and both hide nothing. A colon introducing a literal list, where the items follow on their own lines under it. And the word "Example:" introducing an example, which every example must carry. A colon inside a sentence is still banned. Example:

   Bad: the colon asserts a connection the reader must reconstruct

   ```
   #   The gutters hold the toggles and the add rows, which sit outside the
   #   text: overflow-y makes overflow-x scrollable.
   ```

   Good: says what the classes are for, and what breaks without them

   ```
   #   The gutters keep the section toggles and the dashed add rows inside
   #   the box, so overflow-x-hidden does not clip them.
   ```

   Allowed: the colon introduces a list, and every item stands under it

   ```
   --   Raises when any of the following are not met:
   --     * the head is a property or a relation, not both and not neither
   --     * at most one relation, at the head or at the tail
   ```

   Allowed: the example says it is one, so the reader knows to read it as a case

   ```
   --   A value is possessed and a yes-or-no is asserted,
   --   and the result type decides which.
   --   Example: "each order has a grand total", "each order is over limit".
   ```

* Short is good; cryptic is bad. Write for someone who was not part of the work that produced the code: use literal verbs rather than metaphors ("appears when hovered", not "wakes"), name the thing rather than alluding to it (quote the UI text, or name the column or function), and state the mechanism rather than the belief about it. The test: if someone who has never seen this code reads the comment once, do they learn what it does and why, without re-reading? A two-line plain comment beats a one-line riddle. Example:

   Bad: a metaphor, and the reader must already know what "the invitation" is

   ```
   #   The invitation to word the other direction wakes with its pair.
   ```
   
   Good: names the thing, and says what actually happens

   ```
   #   The "+ and the other way round" line appears when its pair is hovered.
   ```

* Be direct. Say the thing in the plainest order: subject, verb, object. Do not set the scene, do not reason towards the point, do not explain what would happen otherwise. If a sentence can be replaced by a shorter one that carries the same fact, it must be. Example:

   Bad: reasons its way there, and explains a hypothetical

   ```
   --   Every existing row starts on the default, so "has a optionality" would read
   --   until its name was next edited. One job per property has the worker derive
   --   the article the same way it does for a new one.
   ```

   Good: states what the code does, and why

   ```
   --   Trigger one job for each existing property to set the correct article.
   ```

* Never give code, text or data a mind of its own. A sentence does not read, a check does not object, a name does not want. Name the actor, or drop to a plain statement of fact ("the article for the property name", not "the article the property's sentence reads").

* Leave out the plumbing the reader did not ask about. Which module, worker, or job writes a value is rarely the point at the place the value is defined; "derived from the name" tells the reader what they need. Name a specific module only when a reader would otherwise have to search for it.

* Line breaks in comments are semantic, never width-driven: do not fill lines to a column width. Break after a full sentence. Failing that, break after a comma. Failing that, break at a clause boundary. Never split an article from its noun, a subject from its verb, or a phrasal verb: a long line always beats a mid-phrase break. This applies to every comment form, `@doc`/`@moduledoc` heredocs included. Example:

   Bad: filled to width, breaking mid-phrase

   ```
   --   A relation joins any pair already connecting the two entities, so both
   --   directions hold one position in each concept's list.
   ```

   Good: each line ends where the sentence pauses
   ```
   --   A relation joins any pair already connecting the two entities,
   --   so both directions hold one position in each concept's list.
   ```

* Watch for now-biased phrasing: words like "still", "now", "no longer", "pre-/post-" only make sense relative to the moment the code was written. State the timeless fact instead. Example:

   Bad: relative to the change being made

   ```
   # The trigger payload still holds the pre-rename plural.
   ```
   
   Good: always true of the system

   ```
   # The payload's term_plural belongs to the previous term,
   # and inflection-only updates fire no follow-up job.
   ```

   Bad: archaeology; a future reader does not care what the old code did

   ```
   # The pre-machine handler cleared the error flash on every successful upload;
   # only the first-save path kept doing so.
   ```

   Good: rationale the current code does not state by itself

   ```
   # Commit re-derives the rows from current state rather than
   # the previewed snapshot, so a pricing run landing between
   # preview and commit is included.
   ```

* **Comments are a separate pass, in three steps.** Never write a comment while writing code, not even a placeholder. When the code is done, go back over the changed files and write the comments the rules above call for. Then hand those files to the advisor and ask it to scrutinise every comment against these rules, keeping the default of no comment. Apply what comes back.

* Tests are the exception to the first step. A comment naming the case a test covers is written with the test, the way the assertions are.

* **The advisor reads nothing.** It has no tools and cannot open a file or grep the codebase. It sees only the transcript, so paste the whole of every file whose comments are under review, not the comments alone. A ruling that a fact is "not visible from here" is only as good as what you showed it.

* **Check each ruling against the file before applying it.** Delegating the writing does not delegate the judgement. The advisor has kept a comment stating a fact that was plainly visible three lines further down, in a file already pasted in full.

* This rule stops at the comment. A commit message describes a change, so "now", "used to", and "no longer" are informative there and are the right words for its two sides. See COMMIT-MESSAGES.md.

## Commit messages

* Follow COMMIT-MESSAGES.md. The short version:
  - subject at most 50 characters
  - `*` bullets that say what was wrong and what a reader cannot infer from the diff
  - problem before solution, one fact per bullet, a dependent fact as a nested point
  - a problem bullet only for a fix or a non-trivial change, not for a plain addition
  - message size follows diff size, most commits need 0 to 2 bullets
  - "Now" is right in a commit message and wrong in a code comment
  - hand the advisor the diff and the proposed message together

## Style

* This document is written with one line per paragraph and per bullet. Do not hard-wrap prose to a column width. Line breaks belong to structure alone, between bullets, headings, and table rows. Code blocks keep the breaks they need.
* Don't use "→". Instead use "=>".
* All SQL is written in lowercase.

