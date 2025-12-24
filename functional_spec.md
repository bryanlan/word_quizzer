# Functional Specification: Kindle Vocabulary Master

## Purpose
Provide a self-hosted, offline-first system to ingest Kindle vocabulary, prioritize high-utility words, and deliver daily study sessions with lightweight analytics. This spec is derived from `README_HANDOFF.md` and the current codebase.

## Scope
- In scope: Desktop admin for import/triage/LLM enrichment, mobile app for daily quiz and analytics, SQLite database as single source of truth, manual sync via DB copy.
- Out of scope: Multi-user accounts, cloud sync, web frontend, iOS support, and automated background syncing.

## Users
- Single self-hosting user who manages vocabulary on a desktop and studies on an Android device.

## System Overview
- Desktop Admin (Streamlit + AgGrid):
  - Imports Kindle `vocab.db` into `vocab_master.db`.
  - Runs LLM-based ranking and enrichment.
  - Manual triage and edits in a grid UI.
  - Outputs a DB file to be copied to mobile.
- Mobile App (Flutter):
  - Imports `vocab_master.db`.
  - Builds a daily deck and runs the quiz loop.
  - Tracks outcomes and displays analytics.
- Database (SQLite):
  - `vocab_master.db` used by both desktop and mobile.
  - Local tables store words, distractors, examples, study logs, and insults.

## Data Model
### Table: `words`
Required fields (observed + expected):
- `id` INTEGER PK
- `word_stem` TEXT UNIQUE NOT NULL
- `original_context` TEXT
- `book_title` TEXT
- `definition` TEXT
- `phonetic` TEXT
- `status` TEXT enum: `New`, `Learning`, `Proficient`, `Adept`, `Mastered`, `Ignored`, `Pau(S)ed`
- `bucket_date` DATE
- `next_review_date` DATE
- `difficulty_score` INTEGER (1-10)
- `priority_tier` INTEGER (1-5, nullable) (expected by app logic)
- `manual_flag` BOOLEAN (reserved, currently unused)

### Table: `distractors`
- `id` INTEGER PK
- `word_id` INTEGER FK -> words.id
- `text` TEXT
- `is_plausible` BOOLEAN

### Table: `examples`
- `id` INTEGER PK
- `word_id` INTEGER FK -> words.id
- `sentence` TEXT

### Table: `study_log`
- `id` INTEGER PK
- `timestamp` DATETIME
- `word_id` INTEGER FK -> words.id
- `result` TEXT enum: `Correct`, `Incorrect`
- `session_id` TEXT (not currently written by mobile)

### Table: `insults`
- `id` INTEGER PK
- `text` TEXT
- `severity` INTEGER

## Desktop Admin Functional Requirements
### Import Kindle `vocab.db`
- User selects a Kindle `vocab.db` and clicks "Process Import".
- Import logic:
  - Join Kindle tables `WORDS`, `LOOKUPS`, `BOOK_INFO`.
  - Map to `words.word_stem`, `words.original_context`, `words.book_title`.
  - Insert new words only; ignore duplicates.
  - Report number of new words added.

### Triage and Editing
- Display all `words` records in an editable grid.
- `word_stem` is read-only; `status` is editable via dropdown.
- Keyboard shortcuts for `status` when the column is active:
  - N: New, L: Learning, P: Proficient, A: Adept, M: Mastered, I: Ignored, S: Pau(S)ed
- Edits are saved via an explicit "Save Changes" button.
- App shows a warning if there are unsaved edits.

### LLM Actions
- Pedestrian Check:
  - LLM assigns `difficulty_score` 1-10 to `New` words.
  - If score < 4, auto-set `status` to `Ignored`.
- Priority Ranking:
  - LLM assigns `priority_tier` 1-5 to words with null tier and status not `Ignored`.
  - Process in batches of 50.
- Enrichment:
  - LLM generates `definition`, 4 `distractors`, and 3 `examples` for `New` words.
  - On success: update `definition`, set `status` to `Learning`, set `bucket_date` to today, insert distractors/examples.

### Footer Metrics
- Show total words, new words, and mastered count.

## Mobile App Functional Requirements
### Home Screen
- Displays total words, learned count, mastered count, and a placeholder streak.
- Buttons for:
  - Start Daily Quiz
  - Analytics
  - Settings
  - Import Database (file picker)

### Database Import (Mobile)
- User selects a DB file; app copies it to app database path as `vocab_master.db`.
- Existing DB is closed before copying.
- No schema validation beyond SQLite open.

### Daily Deck Logic
Inputs:
- `limit`: 10 words per session (current quiz screen behavior).
- `active_limit`: from settings (default 20).
Rules:
1. Fetch due words:
   - All `Learning` words.
   - Any `Proficient`, `Adept`, `Mastered` where `next_review_date` is null or <= today.
2. If total deck < limit and active learning count < `active_limit`, fetch `New` words:
   - Order by `priority_tier ASC, difficulty_score ASC`.
   - Fetch up to remaining capacity and deck limit.
3. Shuffle deck to intermix review and new words.

### Quiz Loop
- Each word shows original context (if present), word stem, and phonetic (if present).
- User clicks "Reveal" before seeing options.
- Options:
  - 1 correct definition from `words.definition` (or "MISSING DEFINITION").
  - Up to 3 distractors from `distractors`.
  - Fill remaining slots with random definitions from other words.
  - Shuffle options.
- Correct:
  - Flash green, play TTS for word, update status to `Proficient`, log result.
  - Auto-advance after 2 seconds.
- Incorrect:
  - Flash red, show an insult, show definition, require typing the word to continue.
  - Update status to `Learning`, log result.
- End of session: return to home screen.

### SRS Scheduling
- On status update, set `bucket_date` to today.
- `next_review_date` is set based on status:
  - Proficient: +1 day
  - Adept: +3 days
  - Mastered: +14 days
  - Learning: same day

### Analytics Screen
- Mastery rate: mastered / total.
- Activity chart: counts from `study_log` for the last 7 days.
- Troublesome words: top 5 with more than 1 incorrect result.

### Settings Screen
- "Active Learning Cap" slider from 5 to 100.
- Stored in shared preferences under `active_limit`.

## External Integrations
- OpenRouter API for LLM:
  - Requires `OPENROUTER_API_KEY` in environment.
  - Sends word lists for difficulty scoring, tier ranking, and enrichment.
  - Expects JSON responses.

## Non-Functional Requirements
- Offline-first: all core features work without network access after import/enrichment.
- Single-device, manual sync via file copy.
- Local SQLite storage; no user accounts or authentication.
- Performance: import and enrichment should handle large word lists via batching.

## Known Gaps and Implementation Notes
These are observed in code and should be addressed to match intended behavior.
- `desktop_admin/app.py` calls `import_kindle_db()` but only an unrelated `find_changes()` function exists; import may not work as-is.
- `save_changes_from_records()` is referenced but not implemented; manual grid edits cannot be persisted.
- `db_init.py` does not create `priority_tier`, but the app expects it.
- Quiz progression only promotes to `Proficient`; no automatic step-up to `Adept` or `Mastered` is implemented.
- `study_log.session_id` is defined but never written by the mobile app.
