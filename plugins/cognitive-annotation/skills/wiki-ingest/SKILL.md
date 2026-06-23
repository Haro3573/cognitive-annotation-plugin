---
description: Sync the wiki with cognitive.db. Discovers all annotated sessions that lack wiki pages and ingests them automatically — no UUIDs needed. Updates session pages, category pages, pattern pages, overview.md, index.md, and log.md. Run after annotation or any time the wiki is stale.
model: sonnet
---

You are running an automated wiki ingest. All steps are required.

---

**Step 1 — Locate the database and wiki**

```bash
DB="${COGNITIVE_DB_PATH:-cognitive.db}"
WIKI="${CLAUDE_PROJECT_DIR}/wiki"
PARSED="${CLAUDE_PROJECT_DIR}/session_collection/parsed"
```

If `$DB` does not exist as a file, stop and report: "cognitive.db not found — set COGNITIVE_DB_PATH or run from the project root."

Then sync all wiki tables from the database before reading or writing any page:

```bash
python "$CLAUDE_PROJECT_DIR/pipeline/wiki_sync.py" \
  --db "$DB" \
  --wiki "$WIKI"
```

If the script exits non-zero, stop and report the full stderr output.
Print the stdout summary before continuing to Step 2.

---

**Step 2 — Discover sessions to ingest**

Query all annotated sessions in chronological order:

```bash
sqlite3 "$DB" "SELECT DISTINCT conversation_name FROM cognitive_alignments ORDER BY MIN(created_at);"
```

For each UUID, check whether `$WIKI/pages/sessions/<uuid[:8]>.md` exists.

Collect sessions **without** a page — this is the **ingest queue**.

If the queue is empty: print "Wiki is up to date — nothing to ingest." and stop.

Print: `Found <N> session(s) to ingest: <uuid[:8]>, ...`

---

**Step 3 — Ingest each session in the queue**

For each session UUID, follow the **Ingest a session** procedure from `wiki/CLAUDE.md` exactly (9 steps: read parsed transcript → query alignments → query relationships → write session page → update category pages → update pattern pages → update overview → update index → append log entry).

Key queries for each session:

```bash
# Behavioral events
sqlite3 "$DB" "
SELECT turn_index, category, subcategory, excerpt_text,
       sub_type, confidence, rationale, mundane_alternative, trigger,
       matched_excerpt_text, matched_excerpt_id, composite_score
FROM cognitive_alignments
WHERE conversation_name = '<uuid>'
ORDER BY turn_index;"

# Cross-session matches for this session's excerpts
sqlite3 "$DB" "
SELECT ca.excerpt_id, ca.subcategory, ca.excerpt_text,
       ca.matched_excerpt_text, ca.composite_score
FROM cognitive_alignments ca
WHERE ca.conversation_name = '<uuid>'
  AND ca.matched_excerpt_id IS NOT NULL;"
```

Session metadata: query `cognitive_sessions` for the turn count and conversation summary:
```bash
sqlite3 "$DB" "SELECT user_turn_count, conversation_summary FROM cognitive_sessions WHERE conversation_name = '<uuid>';"
```
Use `user_turn_count` for the `Turns:` header field and `conversation_summary` for the `## What was discussed` section body.

Print one progress line per session as it completes:
`✓ <uuid[:8]> — <N> excerpt(s), <M> cross-session match(es)`

**Do not update `overview.md` during individual session ingests** — defer it to Step 4.

---

**Step 4 — Rebuild overview.md**

After all sessions are ingested, read all pages in `wiki/pages/categories/` and `wiki/pages/patterns/`. Synthesize `wiki/pages/overview.md`:

- **Dominant patterns**: which subcategories appear most, with what score distribution
- **Cross-session trajectory**: how behaviors have shifted across sessions (if multiple sessions)
- **Contradictions**: any subcategories where the same behavior was both accepted and rejected across sessions
- **Profile summary**: 3–5 sentences a cognitive insight agent could use to generate relevant 💡 insights

This last section — the profile summary — should be at the top of the file under a `## Profile` heading. It is what the prediction agent reads when generating predicted user messages.

---

**Step 5 — Finalize index.md and log.md**

Update `wiki/index.md`:
- Add a row to the **Sessions** table for each newly ingested session
- Update the **Overview** section link if overview.md was rebuilt

Append to `wiki/log.md`:
```
## [YYYY-MM-DD] ingest | <N> session(s): <uuid[:8]>, ...
```

---

**Step 6 — Summary**

Print:
```
Wiki ingest complete.
  Sessions ingested: <N>
  Pages written:     <M>
  Overview rebuilt:  yes/no
```
