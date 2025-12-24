# Word Quizzer

Offline-first vocabulary trainer with a Streamlit admin console and a Flutter Android app.

## What it does
- Import Kindle vocab exports into a single SQLite database.
- Triage words by status and tier, then enrich with definitions, distractors, and examples.
- Run daily quizzes on Android with streak-based promotion rules and analytics.

## Repo layout
- `desktop_admin/` Streamlit admin UI + LLM enrichment
- `mobile_app/` Flutter Android app
- `functional_spec.md` Product behavior and data model

## Prerequisites
- Python 3.12+
- Flutter 3.38+
- Android SDK (for device runs)

## Desktop admin setup
```bash
cd desktop_admin
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create `desktop_admin/.env`:
```
OPENROUTER_API_KEY=your_key_here
```

Run the admin:
```bash
streamlit run app.py
```

## Mobile app setup
```bash
cd mobile_app
flutter pub get
flutter run
```

## Database sync to Android (debug)
The app reads `vocab_master.db` from the Android app data directory. For debug builds you can push a fresh DB:
```bash
adb shell am force-stop com.example.vocab_master
adb push /path/to/vocab_master.db /data/local/tmp/vocab_master.db
adb shell run-as com.example.vocab_master cp /data/local/tmp/vocab_master.db \
  /data/data/com.example.vocab_master/databases/vocab_master.db
```

## Notes
- The SQLite database is the source of truth and is intentionally not checked in.
- LLM enrichment uses OpenRouter; set `OPENROUTER_API_KEY` before running.
