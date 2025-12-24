import sqlite3
import os

DB_NAME = "import_db/vocab.db"

def create_dummy_kindle_db():
    if not os.path.exists("import_db"):
        os.makedirs("import_db")

    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()

    # Kindle Schema (Simplified)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS WORDS (
            id TEXT PRIMARY KEY,
            stem TEXT,
            word TEXT,
            lang TEXT,
            category INTEGER DEFAULT 0,
            timestamp INTEGER DEFAULT 0,
            profileid TEXT
        );
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS BOOK_INFO (
            id TEXT PRIMARY KEY,
            asin TEXT,
            guid TEXT,
            lang TEXT,
            title TEXT,
            authors TEXT
        );
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS LOOKUPS (
            id TEXT PRIMARY KEY,
            word_key TEXT,
            book_key TEXT,
            dict_key TEXT,
            pos TEXT,
            usage TEXT,
            timestamp INTEGER DEFAULT 0
        );
    """)

    # Insert Dummy Data
    words = [
        ("w1", "ephemeral", "ephemeral", "en"),
        ("w2", "obsequious", "obsequious", "en"),
        ("w3", "serendipity", "serendipity", "en"),
        ("w4", "cat", "cat", "en") # Pedestrian word
    ]
    cursor.executemany("INSERT OR IGNORE INTO WORDS (id, stem, word, lang) VALUES (?, ?, ?, ?)", words)

    books = [
        ("b1", "asin1", "guid1", "en", "The Great Gatsby", "F. Scott Fitzgerald"),
        ("b2", "asin2", "guid2", "en", "1984", "George Orwell")
    ]
    cursor.executemany("INSERT OR IGNORE INTO BOOK_INFO (id, asin, guid, lang, title, authors) VALUES (?, ?, ?, ?, ?, ?)", books)

    lookups = [
        ("l1", "w1", "b1", "dict1", "noun", "The ephemeral nature of fashion is annoying."),
        ("l2", "w2", "b2", "dict1", "adj", "His obsequious behavior was embarrassing."),
        ("l3", "w3", "b1", "dict1", "noun", "It was pure serendipity that we met."),
        ("l4", "w4", "b2", "dict1", "noun", "The cat sat on the mat.")
    ]
    cursor.executemany("INSERT OR IGNORE INTO LOOKUPS (id, word_key, book_key, dict_key, pos, usage) VALUES (?, ?, ?, ?, ?, ?)", lookups)

    conn.commit()
    conn.close()
    print(f"Dummy Kindle DB created at {DB_NAME}")

if __name__ == "__main__":
    create_dummy_kindle_db()
