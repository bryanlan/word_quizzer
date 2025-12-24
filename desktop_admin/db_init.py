import sqlite3
import os

DB_NAME = "vocab_master.db"

def create_connection():
    conn = None
    try:
        conn = sqlite3.connect(DB_NAME)
        return conn
    except sqlite3.Error as e:
        print(e)
    return conn

def create_tables(conn):
    try:
        cursor = conn.cursor()

        # Table: words
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS words (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_stem TEXT UNIQUE NOT NULL,
                original_context TEXT,
                book_title TEXT,
                definition TEXT,
                phonetic TEXT,
                status TEXT CHECK(status IN ('New', 'On Deck', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored', 'Pau(S)ed')) DEFAULT 'New',
                bucket_date DATE,
                next_review_date DATE,
                difficulty_score INTEGER,
                priority_tier INTEGER,
                status_correct_streak INTEGER DEFAULT 0,
                manual_flag BOOLEAN DEFAULT 0
            );
        """)

        # Table: distractors
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS distractors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id INTEGER,
                text TEXT NOT NULL,
                is_plausible BOOLEAN DEFAULT 1,
                FOREIGN KEY (word_id) REFERENCES words (id)
            );
        """)

        # Table: examples
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS examples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id INTEGER,
                sentence TEXT NOT NULL,
                FOREIGN KEY (word_id) REFERENCES words (id)
            );
        """)

        # Table: study_log
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS study_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                word_id INTEGER,
                result TEXT CHECK(result IN ('Correct', 'Incorrect')),
                session_id TEXT,
                FOREIGN KEY (word_id) REFERENCES words (id)
            );
        """)

        # Table: insults
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS insults (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                severity INTEGER
            );
        """)

        ensure_words_columns(conn)
        ensure_on_deck_status(conn)
        
        # Pre-populate insults
        cursor.execute("SELECT count(*) FROM insults")
        if cursor.fetchone()[0] == 0:
            default_insults = [
                ("My grandmother knows that word and she's been dead for 20 years.", 3),
                ("Even a broken clock gets lucky twice a day. You are not a clock.", 2),
                ("That was... optimistic.", 1),
                ("I've seen better vocabulary from a Speak & Spell.", 4),
                ("Are you trying to be wrong?", 2)
            ]
            cursor.executemany("INSERT INTO insults (text, severity) VALUES (?, ?)", default_insults)

        conn.commit()
        print("Tables created successfully.")
    except sqlite3.Error as e:
        print(e)

def ensure_on_deck_status(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='words'")
    if cursor.fetchone() is None:
        return

    cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='words'")
    row = cursor.fetchone()
    if not row or not row[0]:
        return
    has_on_deck = "on deck" in row[0].lower()

    cursor.execute("PRAGMA table_info(words)")
    columns = {row[1] for row in cursor.fetchall()}
    has_priority_tier = "priority_tier" in columns
    has_manual_flag = "manual_flag" in columns
    has_streak = "status_correct_streak" in columns

    if has_on_deck:
        if not has_priority_tier:
            cursor.execute("ALTER TABLE words ADD COLUMN priority_tier INTEGER")
        if not has_manual_flag:
            cursor.execute("ALTER TABLE words ADD COLUMN manual_flag BOOLEAN DEFAULT 0")
        if not has_streak:
            cursor.execute("ALTER TABLE words ADD COLUMN status_correct_streak INTEGER DEFAULT 0")
        conn.commit()
        return

    cursor.execute("PRAGMA foreign_keys=OFF")
    cursor.execute("ALTER TABLE words RENAME TO words_old")
    cursor.execute("""
        CREATE TABLE words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word_stem TEXT UNIQUE NOT NULL,
            original_context TEXT,
            book_title TEXT,
            definition TEXT,
            phonetic TEXT,
            status TEXT CHECK(status IN ('New', 'On Deck', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored', 'Pau(S)ed')) DEFAULT 'New',
            bucket_date DATE,
            next_review_date DATE,
            difficulty_score INTEGER,
            priority_tier INTEGER,
            status_correct_streak INTEGER DEFAULT 0,
            manual_flag BOOLEAN DEFAULT 0
        );
    """)
    cursor.execute("""
        INSERT INTO words (
            id,
            word_stem,
            original_context,
            book_title,
            definition,
            phonetic,
            status,
            bucket_date,
            next_review_date,
            difficulty_score,
            priority_tier,
            status_correct_streak,
            manual_flag
        )
        SELECT
            id,
            word_stem,
            original_context,
            book_title,
            definition,
            phonetic,
            CASE WHEN status = 'Learning' THEN 'On Deck' ELSE status END,
            bucket_date,
            next_review_date,
            difficulty_score,
            {priority_tier},
            {status_correct_streak},
            {manual_flag}
        FROM words_old;
    """.format(
        priority_tier="priority_tier" if has_priority_tier else "NULL",
        status_correct_streak="status_correct_streak" if has_streak else "0",
        manual_flag="manual_flag" if has_manual_flag else "0",
    ))
    cursor.execute("DROP TABLE words_old")
    cursor.execute("PRAGMA foreign_keys=ON")
    conn.commit()

def ensure_words_columns(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='words'")
    if cursor.fetchone() is None:
        return

    cursor.execute("PRAGMA table_info(words)")
    columns = {row[1] for row in cursor.fetchall()}
    if "priority_tier" not in columns:
        cursor.execute("ALTER TABLE words ADD COLUMN priority_tier INTEGER")
    if "manual_flag" not in columns:
        cursor.execute("ALTER TABLE words ADD COLUMN manual_flag BOOLEAN DEFAULT 0")
    if "status_correct_streak" not in columns:
        cursor.execute("ALTER TABLE words ADD COLUMN status_correct_streak INTEGER DEFAULT 0")
    conn.commit()

if __name__ == "__main__":
    if not os.path.exists(DB_NAME):
        print(f"Creating new database: {DB_NAME}")
    
    conn = create_connection()
    if conn:
        create_tables(conn)
        conn.close()
    else:
        print("Error! cannot create the database connection.")
