import json
import os
import requests
from dotenv import load_dotenv

load_dotenv()

# Mock response mode for development
MOCK_MODE = False  # Changed to False to enable real calls if key is present

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")

def _call_openrouter(messages, model="google/gemini-3-flash-preview", max_tokens=40000):
    """
    Helper function to call OpenRouter API.
    """
    if not OPENROUTER_API_KEY:
        print("Error: OPENROUTER_API_KEY not found in environment variables.")
        return None

    try:
        response = requests.post(
            url="https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {OPENROUTER_API_KEY}",
                "Content-Type": "application/json",
            },
            data=json.dumps({
                "model": model,
                "messages": messages,
                "max_tokens": max_tokens,
                "reasoning": {"enabled": True},
                "response_format": {"type": "json_object"} 
            })
        )
        
        response.raise_for_status()
        data = response.json()
        
        if 'choices' in data and len(data['choices']) > 0:
            content = data['choices'][0]['message']['content']
            try:
                return json.loads(content)
            except json.JSONDecodeError:
                print(f"Failed to parse JSON response: {content}")
                return None
        return None

    except Exception as e:
        print(f"API Call Error: {e}")
        return None

def assess_difficulty(words):
    """
    Analyzes a list of words and assigns a difficulty score (1-10).
    Returns a dictionary: {word_stem: score}
    """
    if MOCK_MODE:
        import random
        results = {}
        for word in words:
            # Pedestrian words get low scores
            if word.lower() in ['cat', 'dog', 'house', 'run']:
                results[word] = 2
            else:
                results[word] = random.randint(5, 10)
        return results

    prompt = f"""
    Analyze the following list of words. Assign a difficulty score (1-10) to each, where 1 is very basic (pedestrian) and 10 is extremely obscure.
    
    Words: {', '.join(words)}
    
    Return ONLY a JSON object where keys are the words and values are the integer scores.
    Example: {{"word1": 5, "word2": 2}}
    """

    messages = [{"role": "user", "content": prompt}]
    result = _call_openrouter(messages)
    
    return result if result else {}

def enrich_words(words):
    """
    Generates definitions, distractors, and examples for a list of words.
    Returns a dictionary keyed by word_stem.
    """
    if MOCK_MODE:
        results = {}
        for word in words:
            results[word] = {
                "definition": f"A concise mock definition for {word}.",
                "distractors": [
                    f"A concrete object unrelated to {word}",
                    "A brief statement about weather patterns",
                    "A kitchen method used for cooking",
                    "A transportation term from logistics",
                    "A musical technique for beginners",
                    "A medical tool used in clinics",
                    "A historical event from the 1800s",
                    "A minor rule in a sport",
                    "A decorative style in architecture",
                    "A type of fabric used in clothing",
                    "A financial metric used in reports",
                    "A geographic feature in Europe",
                    "A photography term about lighting",
                    "A software setting for preferences",
                    "A workplace policy about attendance",
                ],
                "examples": [
                    f"He showed great {word} in the face of danger.",
                    f"The {word} in her voice hinted at quiet disappointment.",
                    f"It was a small gesture, but it revealed his {word} clearly.",
                    f"Without that {word}, the plan would have failed.",
                    f"Their {word} was obvious to anyone watching."
                ]
            }
        return results

    prompt = f"""
    For each word, return:
    - definition: 5-12 words, plain English, no filler.
    - distractors: 15 short definition-style phrases (5-12 words), same part of speech.
      Each distractor MUST be a definition-style clause with a verb (e.g., "being...", "having...", "marked by...", "characterized by...").
      Match the definition’s format and length (use a similar lead-in like "Relating to...", within ±2 words).
      Do NOT output noun-only fragments.
      Mix difficulty: 5 easy wrong, 7 medium, 3 hard-but-wrong.
      Avoid close synonyms or near-misses that could confuse learners.
      Do NOT use the target word or close variants.
      Avoid meta labels like category/genre/brand/model/app/software/name/address.
      EMPHATIC ANTI-PATTERNS (DO NOT DO THESE):
      - Do NOT output concrete objects or food/drink items (e.g., "sweet fruit aroma", "fizzy soda", "pastry").
      - Do NOT output scene fragments or physical places (e.g., "quiet forest glade", "busy train station").
      - Do NOT output single nouns or noun lists without definition-style wording.
      - Do NOT output generic labels (e.g., "a type of X", "kind of Y", "brand/model/name").
    - examples: 5 sentences, 12-25 words each, each must include the word (or inflected form).
      Provide helpful context for someone learning the word; use book-like usage.
      The context should NOT be a dead giveaway for the definition, and NOT useless for inferring meaning.
      Avoid bland, generic sentences.
    
    Words: {', '.join(words)}
    
    Return ONLY a JSON object where the keys are the words and the values are objects with the following structure.
    Example response for a fictional word "vellumate":
    {{
      "vellumate": {{
        "definition": "Relating to formal, meticulous work in an official setting.",
        "distractors": [
          "Relating to seasonal weather patterns and forecasting",
          "Relating to theatrical performance and stagecraft traditions",
          "Relating to childhood play and social games",
          "Relating to culinary technique and slow cooking methods",
          "Relating to insect behavior and life cycles",
          "Relating to navigation safety and route planning",
          "Relating to financial markets and speculative trading",
          "Relating to marine biology and ecosystem balance",
          "Relating to architectural design and urban planning",
          "Relating to religious ceremony and liturgy",
          "Relating to bird migration and seasonal movement",
          "Relating to mechanical repair and equipment maintenance",
          "Relating to medical nutrition and recovery support",
          "Relating to software updates and release cycles",
          "Relating to group psychology and social behavior"
        ],
        "examples": [
          "By the end of the meeting, her vellumate tone slowed the rush and turned scattered talk into measured decisions.",
          "He approached the negotiations with a vellumate air, pausing often, preferring certainty over speed.",
          "After the audit notice arrived, the office adopted a vellumate style, careful and deliberate in every response.",
          "She chose a vellumate approach to the case, resisting shortcuts and insisting on clear steps.",
          "His vellumate habits made him the obvious choice for sensitive tasks demanding patience and restraint."
        ]
      }}
    }}
    {{
      "word_stem": {{
        "definition": "Short, punchy definition",
        "distractors": ["distractor 1", ..., "distractor 15"],
        "examples": ["sentence 1", ..., "sentence 5"]
      }}
    }}
    """
    
    messages = [{"role": "user", "content": prompt}]
    result = _call_openrouter(messages)
    if not isinstance(result, dict):
        return {}

    cleaned = {}
    for word in words:
        data = _find_word_payload(result, word)
        if not isinstance(data, dict):
            continue

        definition = _normalize_text(data.get("definition", ""))
        examples = _normalize_list(data.get("examples", []))
        distractors = _normalize_list(data.get("distractors", []))

        if not definition:
            continue

        cleaned[word] = {
            "definition": definition,
            "examples": examples,
            "distractors": distractors,
        }

    return cleaned

def _find_word_payload(result, word):
    if word in result:
        return result[word]
    lower_map = {str(k).lower(): v for k, v in result.items()}
    return lower_map.get(word.lower())

def _normalize_text(text):
    return str(text).strip()

def _normalize_list(value):
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list):
        return []
    cleaned = []
    seen = set()
    for item in value:
        text = _normalize_text(item)
        if not text:
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(text)
    return cleaned


def rank_words_tier(words):
    """
    Ranks a list of words by frequency into 5 tiers (Quintiles).
    Tier 1 = Most Frequent/Useful
    Tier 5 = Least Frequent/Obscure
    """
    if MOCK_MODE:
        import random
        return {w: random.randint(1, 5) for w in words}

    prompt = f"""
    You are a strict lexicographer. I have a list of {len(words)} words.
    Rank them by frequency of use in modern English and assign them to 5 Tiers.
    
    Constraints:
    1. Divide the list into 5 roughly equal groups (Quintiles).
    2. Tier 1 = Most Useful / Highest Frequency (e.g., 'Nuance', 'Pragmatic').
    3. Tier 5 = Least Useful / Obscure / Archaic (e.g., 'Crapulent', 'Defenestrate').
    
    Words: {', '.join(words)}
    
    Return ONLY a JSON object: {{"word_stem": tier_integer}}
    """
    
    messages = [{"role": "user", "content": prompt}]
    result = _call_openrouter(messages)
    return result if result else {}
