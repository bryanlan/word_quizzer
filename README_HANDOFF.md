# Kindle Vocabulary Master - Project Handoff

## 1. Project Goal
A self-hosted, offline-first system to master vocabulary from a Kindle device. 
**Philosophy:** Prioritize high-utility words ("Tier 1") over obscure ones. Prevent backlog burnout via a capped "Active Learning" queue.

**Tech Stack:**
*   **Database:** SQLite (`vocab_master.db`) - Single source of truth.
*   **Desktop Admin:** Python + Streamlit + AgGrid (Linux). Used for importing, AI enrichment, and triage.
*   **Mobile App:** Flutter (Android). Used for daily study (Quiz) and analytics.

---

## 2. Core Workflows (The "Spec")

### A. Desktop Admin
1.  **Import:** User uploads `vocab.db` (Kindle). System merges new words into `vocab_master.db`.
2.  **Tiering (AI):** User clicks "Run Priority Ranking". LLM assigns `priority_tier` (1=High, 5=Low) to all words.
3.  **Triage (Manual):** User views the grid. Uses hotkeys (`I`=Ignored, `S`=Paused, `N`=New) to quick-filter words.
4.  **Enrichment (AI):** User clicks "Enrich New Words". LLM generates definitions, distractors, and examples for all `New` words.
5.  **Sync:** User manually copies `vocab_master.db` to Android device.

### B. Mobile Player
1.  **The Daily Deck:**
    *   **Logic:** 
        *   Prioritize `Learning` words (SRS Due).
        *   If `Count(Learning) < Active_Cap` (User Setting, default 20), fetch `New` words.
        *   **Fetch Order:** Strict `priority_tier ASC` (Tier 1 before Tier 2).
    *   **Mix:** Shuffle the final deck (Reviews + New) to intersperse them.
2.  **Quiz Loop:**
    *   **Correct:** Promote status (Learning -> Proficient -> Adept -> Mastered). Set `next_review_date` (Leitner: +1, +3, +14 days).
    *   **Incorrect:** Demote to `Learning`. Show insult. Require typing the word.
3.  **Analytics:**
    *   Show "Troublesome Words" (high failure rate).
    *   Show Daily Activity Chart.

---

## 3. Database Schema

**Table: `words`**
*   `id` (PK)
*   `word_stem` (Text, Unique)
*   `status` (Enum: 'New', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored', 'Pau(S)ed')
*   `priority_tier` (Int: 1-5, Nullable)
*   `difficulty_score` (Int: 1-10)
*   `definition` (Text)
*   `next_review_date` (Date)

**Tables:** `distractors`, `examples`, `study_log`, `insults` (Standard FK relations).

---

## 4. Current State & Known Issues

### ✅ Working
*   **Database:** Fully migrated with `priority_tier` and indices.
*   **Mobile App:** Fully implemented. Includes Settings (Active Cap), Analytics, and Smart Deck logic.
*   **AI Integration:** OpenRouter (Grok) is hooked up for Tiering and Enrichment.
*   **Desktop Grid (Logic):** The "Record-Based Diffing" is implemented to allow saving changes.

### ⚠️ Fragile / Needs Attention
*   **AgGrid State Management:** The Streamlit <-> AgGrid connection is tricky.
    *   *Issue:* "Phantom Saves" where the app thinks data changed when it didn't.
    *   *Current Fix:* We moved to a manual "Save Changes" button and a dictionary-based comparison function (`find_changes` in `app.py`) to ignore Pandas index/type strictness.
    *   *Risk:* If the user sorts/filters and the unique ID isn't tracked perfectly, edits might be lost or misapplied.
*   **Hotkeys:** JavaScript injection for `N`, `I`, `S` shortcuts exists but depends on AgGrid focus state.

---

## 5. How to Run

**Desktop:**
```bash
cd desktop_admin
source venv/bin/activate
streamlit run app.py
```

**Mobile:**
```bash
cd mobile_app
flutter run --release
```
