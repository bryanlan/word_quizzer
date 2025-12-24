import streamlit as st
import pandas as pd
import sqlite3
import os
import tempfile
from st_aggrid import AgGrid, GridOptionsBuilder, DataReturnMode, JsCode
import db_init
import llm_helper

DB_NAME = "vocab_master.db"
STATUS_OPTIONS = ['New', 'On Deck', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored', 'Pau(S)ed']
DATE_COLUMNS = {"bucket_date", "next_review_date"}

st.set_page_config(page_title="Kindle Vocab Master", layout="wide")

# JavaScript to suppress default editing for specific keys
suppress_keyboard_js = JsCode("""
function(params) {
    const key = params.event.key.toUpperCase();
    const keysToSuppress = ['N', 'O', 'L', 'P', 'A', 'M', 'I', 'S'];
    return keysToSuppress.includes(key);
}
""")

# JavaScript for keyboard shortcuts
# When a key is pressed, if the status column is active, update the value
on_cell_key_down = JsCode("""
function(params) {
    const key = params.event.key.toUpperCase();
    const mappings = {
        'N': 'New',
        'O': 'On Deck',
        'L': 'Learning',
        'P': 'Proficient',
        'A': 'Adept',
        'M': 'Mastered',
        'I': 'Ignored',
        'S': 'Pau(S)ed'
    };

    if (mappings[key] && params.column.getColId() === 'status') {
        params.node.setDataValue('status', mappings[key]);
        params.api.flashCells({ rowNodes: [params.node], columns: ['status'] });
    }
}
""")

def get_db_connection():
    conn = sqlite3.connect(DB_NAME)
    return conn

def ensure_db_schema():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    existing_tables = {row[0] for row in cursor.fetchall()}
    required_tables = {"words", "distractors", "examples", "study_log", "insults"}
    if not required_tables.issubset(existing_tables):
        db_init.create_tables(conn)

    db_init.ensure_words_columns(conn)
    db_init.ensure_on_deck_status(conn)

    conn.close()

def load_data():
    conn = get_db_connection()
    df = pd.read_sql_query("SELECT * FROM words", conn)
    conn.close()
    
    # NORMALIZE IMMEDIATELY
    # 1. Ensure priority_tier is Int64 (nullable int)
    if 'priority_tier' in df.columns:
        df['priority_tier'] = pd.to_numeric(df['priority_tier'], errors='coerce').astype('Int64')
        
    # 2. Normalize text columns: DB NULL -> "" (Empty String)
    # This matches what AgGrid returns for empty cells
    for col in df.select_dtypes(include=['object']).columns:
        df[col] = df[col].fillna("").astype(str)
        
    return df

def import_kindle_db(uploaded_file):
    if uploaded_file is None:
        st.warning("Please upload a Kindle vocab.db file to import.")
        return

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as tmp_file:
            tmp_file.write(uploaded_file.getbuffer())
            temp_path = tmp_file.name

        k_conn = sqlite3.connect(temp_path)
        query = """
            SELECT 
                w.stem as word_stem,
                l.usage as original_context,
                b.title as book_title
            FROM WORDS w
            JOIN LOOKUPS l ON w.id = l.word_key
            JOIN BOOK_INFO b ON l.book_key = b.id
            GROUP BY w.stem
        """
        df_new = pd.read_sql_query(query, k_conn)
        k_conn.close()

        if df_new.empty:
            st.warning("No words found in the uploaded file.")
            return

        m_conn = get_db_connection()
        cursor = m_conn.cursor()

        added_count = 0
        for _, row in df_new.iterrows():
            cursor.execute(
                """
                    INSERT OR IGNORE INTO words (word_stem, original_context, book_title)
                    VALUES (?, ?, ?)
                """,
                (row['word_stem'], row['original_context'], row['book_title'])
            )
            added_count += cursor.rowcount

        m_conn.commit()
        m_conn.close()

        st.success(f"Import complete! Added {added_count} new words.")

    except Exception as e:
        st.error(f"Error importing database: {e}")
    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)

def _normalize_date(value):
    if value is None or pd.isna(value):
        return None

    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return None
        parsed = pd.to_datetime(stripped, errors="coerce")
        if pd.isna(parsed):
            return stripped
        return parsed.date().isoformat()

    parsed = pd.to_datetime(value, errors="coerce")
    if pd.isna(parsed):
        return str(value)
    return parsed.date().isoformat()

def _normalize_for_compare(value, is_numeric, is_date):
    if is_date:
        return _normalize_date(value)

    if value is None or pd.isna(value):
        return None if is_numeric else ""

    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return None if is_numeric else ""
        if is_numeric:
            parsed = pd.to_numeric(stripped, errors="coerce")
            return None if pd.isna(parsed) else parsed
        return value

    if is_numeric:
        return value

    return str(value)

def _normalize_for_db(value, is_numeric, is_date):
    if is_date:
        return _normalize_date(value)

    if value is None or pd.isna(value):
        return None

    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return None
        if is_numeric:
            parsed = pd.to_numeric(stripped, errors="coerce")
            if pd.isna(parsed):
                return None
            if float(parsed).is_integer():
                return int(parsed)
            return float(parsed)
        return value

    if is_numeric and isinstance(value, float) and value.is_integer():
        return int(value)

    return value

def find_changes(original_df, grid_data):
    if grid_data is None:
        return []

    original_rows = original_df.to_dict(orient="records")
    original_by_id = {row["id"]: row for row in original_rows if row.get("id") is not None} if "id" in original_df.columns else {}
    original_by_stem = {row["word_stem"]: row for row in original_rows if row.get("word_stem")} if "word_stem" in original_df.columns else {}
    numeric_cols = {
        col for col in original_df.columns if pd.api.types.is_numeric_dtype(original_df[col])
    }
    read_only_cols = {"id", "word_stem"}

    changed_records = []
    for row in grid_data:
        row_keys = set(row.keys())
        key_field = "id"
        key_value = row.get("id")
        original_row = original_by_id.get(key_value) if key_value is not None else None
        if original_row is None and "word_stem" in row:
            key_field = "word_stem"
            key_value = row.get("word_stem")
            original_row = original_by_stem.get(key_value)

        if original_row is None:
            continue

        updates = {}
        for col in original_df.columns:
            if col in read_only_cols or col not in row_keys:
                continue
            old_val = original_row.get(col)
            new_val = row.get(col)
            is_numeric = col in numeric_cols
            is_date = col in DATE_COLUMNS
            if _normalize_for_compare(old_val, is_numeric, is_date) != _normalize_for_compare(new_val, is_numeric, is_date):
                updates[col] = _normalize_for_db(new_val, is_numeric, is_date)

        if updates:
            updates[key_field] = key_value
            changed_records.append(updates)

    return changed_records

def save_changes_from_records(changed_records):
    if not changed_records:
        return 0

    conn = get_db_connection()
    cursor = conn.cursor()
    updated_rows = 0

    for record in changed_records:
        record_id = record.get("id")
        key_field = "id" if record_id is not None else "word_stem"
        key_value = record_id if record_id is not None else record.get("word_stem")
        if key_value is None:
            continue

        updates = {k: v for k, v in record.items() if k not in ("id", "word_stem")}
        if not updates:
            continue

        set_clause = ", ".join(f"{col} = ?" for col in updates)
        values = list(updates.values()) + [key_value]
        cursor.execute(f"UPDATE words SET {set_clause} WHERE {key_field} = ?", values)
        updated_rows += cursor.rowcount

    conn.commit()
    conn.close()
    return updated_rows

# Initialize session state for Grid Key if not present
if 'grid_key' not in st.session_state:
    st.session_state['grid_key'] = 0
if 'grid_columns_state' not in st.session_state:
    st.session_state['grid_columns_state'] = None
if 'grid_state' not in st.session_state:
    st.session_state['grid_state'] = None

def force_grid_refresh():
    st.session_state['grid_key'] += 1

def run_pedestrian_check():
    conn = get_db_connection()
    # Get New words that haven't been scored yet (or re-score all New)
    df_new = pd.read_sql_query("SELECT id, word_stem FROM words WHERE status = 'New'", conn)
    
    if df_new.empty:
        st.info("No 'New' words to check.")
        conn.close()
        return

    words_to_check = df_new['word_stem'].tolist()
    
    with st.spinner(f"Analyzing {len(words_to_check)} words..."):
        scores = llm_helper.assess_difficulty(words_to_check)
    
    cursor = conn.cursor()
    updated_count = 0
    ignored_count = 0
    
    for word, score in scores.items():
        # Auto-ignore logic: Score < 4 implies pedestrian
        new_status = 'New'
        if score < 4:
            new_status = 'Ignored'
            ignored_count += 1
            
        cursor.execute("""
            UPDATE words 
            SET difficulty_score = ?, status = ?
            WHERE word_stem = ? AND status = 'New'
        """, (score, new_status, word))
        updated_count += 1
        
    conn.commit()
    conn.close()
    st.success(f"Analyzed {updated_count} words. Auto-ignored {ignored_count} pedestrian words.")
    force_grid_refresh()

def run_enrichment(status_filter):
    conn = get_db_connection()
    df_ready = pd.read_sql_query(
        "SELECT id, word_stem FROM words WHERE status = ?",
        conn,
        params=[status_filter],
    )
    
    if df_ready.empty:
        st.info(f"No '{status_filter}' words found to enrich.")
        conn.close()
        return

    words_to_enrich = df_ready['word_stem'].tolist()
    
    cursor = conn.cursor()
    enriched_count = 0
    batch_size = 5
    progress_bar = st.progress(0)
    total = len(words_to_enrich)
    per_word_counts = []
    with_examples = 0
    with_distractors = 0
    
    for i in range(0, total, batch_size):
        batch = words_to_enrich[i:i + batch_size]
        with st.spinner(f"Enriching batch {i + 1}-{min(i + batch_size, total)}..."):
            enrichment_data = llm_helper.enrich_words(batch)

        for word, data in enrichment_data.items():
            if status_filter == 'New':
                cursor.execute("""
                    UPDATE words 
                    SET definition = ?, status = 'On Deck', bucket_date = DATE('now')
                    WHERE word_stem = ? AND status = ?
                """, (data['definition'], word, status_filter))
            else:
                cursor.execute("""
                    UPDATE words 
                    SET definition = ?
                    WHERE word_stem = ? AND status = ?
                """, (data['definition'], word, status_filter))
            
            if cursor.rowcount > 0:
                cursor.execute("SELECT id FROM words WHERE word_stem = ?", (word,))
                row = cursor.fetchone()
                if row:
                    word_id = row[0]
                    
                    cursor.execute("DELETE FROM distractors WHERE word_id = ?", (word_id,))
                    cursor.execute("DELETE FROM examples WHERE word_id = ?", (word_id,))

                    examples = data.get('examples') or []
                    if isinstance(examples, str):
                        examples = [examples]
                    examples = [ex.strip() for ex in examples if isinstance(ex, str) and ex.strip()]

                    distractors = data.get('distractors') or []
                    if isinstance(distractors, str):
                        distractors = [distractors]
                    distractors = [dist.strip() for dist in distractors if isinstance(dist, str) and dist.strip()]

                    for dist in distractors:
                        cursor.execute("INSERT INTO distractors (word_id, text) VALUES (?, ?)", (word_id, dist))
                        
                    for ex in examples:
                        cursor.execute("INSERT INTO examples (word_id, sentence) VALUES (?, ?)", (word_id, ex))
                    
                    if examples:
                        with_examples += 1
                    if distractors:
                        with_distractors += 1
                    per_word_counts.append({
                        "word": word,
                        "examples": len(examples),
                        "distractors": len(distractors),
                    })
                    enriched_count += 1
        
        conn.commit()

        progress_bar.progress(min((i + batch_size) / total, 1.0))
        
    conn.close()
    if status_filter == 'New':
        st.success(f"Enriched {enriched_count} words! Moved to 'On Deck'.")
    else:
        st.success(f"Enriched {enriched_count} words in status '{status_filter}'.")

    if total > 0:
        avg_examples = round(sum(row["examples"] for row in per_word_counts) / max(len(per_word_counts), 1), 2)
        avg_distractors = round(sum(row["distractors"] for row in per_word_counts) / max(len(per_word_counts), 1), 2)
        st.info(
            f"Enrichment summary: {enriched_count}/{total} updated • "
            f"examples present for {with_examples} • distractors present for {with_distractors} • "
            f"avg examples {avg_examples} • avg distractors {avg_distractors}"
        )
        if per_word_counts:
            with st.expander("Enrichment details"):
                st.dataframe(pd.DataFrame(per_word_counts))
    force_grid_refresh()

def run_ranking():
    conn = get_db_connection()
    # Rank words that have no tier yet (NULL), excluding Ignored words
    df_rank = pd.read_sql_query("SELECT word_stem FROM words WHERE priority_tier IS NULL AND status != 'Ignored'", conn)
    
    if df_rank.empty:
        st.info("No unranked active words found.")
        conn.close()
        return

    words_to_rank = df_rank['word_stem'].tolist()
    
    # Process in batches of 50 to respect context window and logic
    batch_size = 50
    cursor = conn.cursor()
    total_ranked = 0
    
    progress_bar = st.progress(0)
    
    for i in range(0, len(words_to_rank), batch_size):
        batch = words_to_rank[i:i + batch_size]
        with st.spinner(f"Ranking batch {i}-{i+len(batch)}..."):
            tiers = llm_helper.rank_words_tier(batch)
            
        for word, tier in tiers.items():
            cursor.execute("UPDATE words SET priority_tier = ? WHERE word_stem = ?", (tier, word))
            total_ranked += 1
        
        conn.commit()
        progress_bar.progress(min((i + batch_size) / len(words_to_rank), 1.0))
        
    conn.close()
    st.success(f"Ranked {total_ranked} words into 5 Tiers!")
    force_grid_refresh()

st.title("📚 Kindle Vocab Master - Admin Console")
ensure_db_schema()

# Sidebar for Actions
with st.sidebar:
    st.header("Actions")
    uploaded_file = st.file_uploader("Import Kindle vocab.db", type="db")
    if uploaded_file is not None:
        if st.button("Process Import"):
            import_kindle_db(uploaded_file)
            st.rerun()
        
    st.markdown("---")
    if st.button("Run Pedestrian Check (LLM)"):
        run_pedestrian_check()
        st.rerun()
        
    if st.button("Run Priority Ranking (Tier 1-5)"):
        run_ranking()
        st.rerun()

    if st.button("Reset All Tiers (Set NULL)"):
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE words SET priority_tier = NULL")
        conn.commit()
        conn.close()
        st.warning("All priority tiers have been reset to NULL.")
        force_grid_refresh()
        st.rerun()

    enrich_status = st.selectbox("Select status to enrich", STATUS_OPTIONS, index=STATUS_OPTIONS.index('New'))
    if st.button("Enrich Words (LLM)"):
        run_enrichment(enrich_status)
        st.rerun()
        
    st.markdown("---")
    if st.button("Reload Data (Hard Refresh)"):
        force_grid_refresh()
        st.cache_data.clear()
        st.rerun()

# Main Grid View
st.subheader("Word Bank")

df = load_data()

if not df.empty:
    gb = GridOptionsBuilder.from_dataframe(df)
    gb.configure_pagination(paginationAutoPageSize=True)
    gb.configure_side_bar()
    gb.configure_default_column(editable=True, groupable=True)
    
    # Configure specific columns
    gb.configure_column("id", hide=True)
    gb.configure_column("word_stem", editable=False, pinned="left")
    gb.configure_column("priority_tier", header_name="Tier (1=High)", width=100, type=["numericColumn", "numberColumnFilter"])
    gb.configure_column(
        "status", 
        cellEditor='agSelectCellEditor', 
        cellEditorParams={'values': STATUS_OPTIONS},
        suppressKeyboardEvent=suppress_keyboard_js
    )
    
    # Add keydown event handler
    gb.configure_grid_options(onCellKeyDown=on_cell_key_down)
    gb.configure_grid_options(enableCellChangeFlash=True)
    
    gridOptions = gb.build()
    stored_grid_state = st.session_state.get("grid_state")
    columns_state = st.session_state.get("grid_columns_state")
    if stored_grid_state:
        gridOptions["initialState"] = stored_grid_state
        columns_state = None

    grid_response = AgGrid(
        df,
        gridOptions=gridOptions,
        data_return_mode=DataReturnMode.AS_INPUT, 
        update_on=["cellValueChanged"],
        columns_state=columns_state,
        fit_columns_on_grid_load=False,
        theme='streamlit',
        height=600, 
        width='100%',
        allow_unsafe_jscode=True,
        key=f"grid_{st.session_state['grid_key']}" 
    )
    if grid_response.grid_state is not None:
        st.session_state["grid_state"] = grid_response.grid_state
    if grid_response.columns_state is not None:
        st.session_state["grid_columns_state"] = grid_response.columns_state

    # Check for updates and save
    grid_data = grid_response['data'] 
    
    if grid_data is not None:
        # Check if grid_data is a DataFrame (some versions of AgGrid return DF)
        if isinstance(grid_data, pd.DataFrame):
            grid_data = grid_data.to_dict(orient='records')
            
        # Detect changes using Pure Python Record Comparison (No Pandas Crashes)
        changed_records = find_changes(df, grid_data)
        
        if changed_records:
            try:
                save_changes_from_records(changed_records)
            except Exception as exc:
                st.error(f"Auto-save failed: {exc}")

else:
    st.info("Database is empty. Import a Kindle vocab.db file to get started.")

# Stats Footer
st.markdown("---")
col1, col2, col3 = st.columns(3)
with col1:
    st.metric("Total Words", len(df))
with col2:
    st.metric("New Words", len(df[df['status'] == 'New']))
with col3:
    st.metric("Mastered", len(df[df['status'] == 'Mastered']))
