## Commit messages

### Format

* Subject in sentence case, no trailing period, at most 50 characters, no `area:` prefix
* A blank line, then `  * ` bullets wrapped near 72 columns with 4-space continuation, and `    - ` for nested points with 6-space continuation
* No period at the end of a bullet
* A one-liner is right when there is nothing non-obvious to say

### Substance

1. **A bullet states what was wrong, or what a reader cannot infer from the diff.** Never restate the file list.

2. **Problem first, solution second, as separate bullets.** A reader who only needs "what was wrong" can stop at the first. Details of the solution go in nested points under it.
   This shape fits a bug fix, or an improvement where the new behaviour relates to the old one in a non-trivial way. It does not fit a plain addition. "The code did not do X. Now it does X" says nothing the subject did not, so a new feature gets the subject and whatever is non-obvious about it, not a problem bullet.

3. **One fact per bullet.** If two facts share one, ask whether the second is needed at all. A semicolon is almost always two bullets, a comma, or a nested point.

4. **A dependent fact is a nested point, not a sibling.** If a bullet only makes sense after the reader read the one above it, it belongs underneath. Sibling bullets must each stand alone.

5. **A count can replace a list.** Name a thing only when the name carries a fact the reader needs. The diff has the names.

6. **Use the verb that describes what the code does.** Not "the function that names the rpc" but "the function that directly calls the rpc". Not "back at the button" but "re-enables the button". Quiet metaphors count as much as loud ones.

7. **Say which set, and match the number.** "one of the repository modules" says the set already exists, "a repository module" does not. A parent bullet takes the plural when its nested points enumerate more than one.

8. **Avoid a word that could take two subjects.** "the fixture no longer passes" leaves open whether the fixture or the test is meant. "the fixture is no longer accepted" does not.

9. **The message is proportional to the diff.** A small diff gets a small message, and most commits need 0 to 2 bullets. The exception is a small diff that fixes a tricky bug, where the reader needs context to understand what was done. More than a few bullets is right only for a complex diff where several factors interact.

10. **"Now" belongs here.** A code comment describes a timeless state, so "now", "still", and "no longer" are wrong in a comment. A commit message describes a change, so "now", "used to", and "no longer" are the right words for its two sides. The two rules pull in opposite directions. Do not carry one into the other.

11. Do not co-sign commits.

### A worked example

Before:

    Repository owns its endpoints and return shapes

      * Api had inlined seven endpoints, among them
        generate_supplier_orders, determine and commit_production_steps,
        and mark and unmark_self_delivered
      * Each is back in a repository module, and Api is a dispatch table
        with no URL in it
      * Every repository function declares the shape its rpc returns as a
        guarded case, so a schema change raises in the function that names
        the rpc
      * assign_dvc_rule ran an already-decoded ApiError through decode/1
        again, which turned every real failure into kind: :bug
      * The machine's outcome clauses match the payload shape as well, so a
        test fixture with a shape the rpc cannot return no longer passes
      * Five unit fixtures and the property generator had such shapes

After:

    Repository owns its endpoints and return shapes

      * Every repository function declares the shape its rpc returns as a
        guarded case, so a schema change raises in the function that
        directly calls the rpc
        - Test fixtures with shapes the rpc cannot return are no longer
          accepted, there were 5 unit fixtures and a property generator
          with such shapes
      * assign_dvc_rule ran an already-decoded ApiError through decode/1
        again, which turned every real failure into kind: :bug

The first two bullets went. The subject says the endpoints moved, and the
diff shows where, so neither the problem nor the solution needed a bullet
(rules 1, 2, 5). The endpoint list went with them (rule 5). "Names" became
"directly calls" (rule 6). The two fixture bullets became one nested point
under the bullet they depend on (rules 3, 4), and "no longer passes"
became "are no longer accepted" (rule 8). Six bullets became two and a
nested point, which is the usual size for a commit of this kind (rule 9).

### Review

Hand the advisor the diff and the proposed message together. Without the diff it cannot tell a redundant bullet from a needed one, or judge whether the length fits the change.
