# scratch_items.py
from dotenv import load_dotenv
import os
import json
import traceback

# Make sure items.get_item_from_chatgpt exists and uses the same client interface
# (i.e. client.chat.completions.create(...)). Import it here.
from ai import get_item_from_chatgpt
# OpenAI client same init as main.py
from openai import OpenAI

# load .env so OPENAI_API_KEY / OPENAI_BASE_URL are picked up
load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL")  # optional

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY not set in environment (.env)")

client = OpenAI(
    api_key=OPENAI_API_KEY,
    base_url=OPENAI_BASE_URL
)

def main():
    # Example contexts to try — tweak as you like
    examples = [
        # {
        #     "wish_title": "Make a million dollars from this app",
        #     "task_title": "Make a sale",
        #     "existing_items": [{"id": "itm-silver-pen-of-signing-checks", "name": "Silver Pen Of Signing Checks", "legendariness": "70"},
        #                        {"id": "itm-wooden-spoon", "name": "Wooden Spoon", "legendariness": "5"},
        #                        {"id": "itm-silver-coin-of-prosperity", "name": "Silver Coin Of Prosperity","legendariness": "40", "description": "A shimmering coin that embodies the wealth earned from many sales.","tags": ["achievement", "wealth", "prosperity", "success"]}],
        #     "repeated_amount": 800
        # },
        {
            "wish_title": "Order a pizza from a restaurant",
            "task_title": "Find a local pizza place that looks good",
            "existing_items": [
                # {"id": "itm-wooden-stone", "name": "Wooden Talisman", "tier": "basic", "stats": {"power": 1, "mastery": 0}, "history": {"times_contributed": 3, "notes": ""}}
            ],
            "repeated_amount": 0
        }
        ]
       
    

    for ctx in examples:
        print("\n=== Context ===")
        try:
            res = get_item_from_chatgpt(ctx, client, model="gpt-4o-mini", max_tokens=600)
            print("\n--- RAW ASSISTANT OUTPUT ---")
            print(res.get("raw", "<no raw>")[:4000])  # truncate long output
        except Exception as e:
            print("Error generating item:", str(e))
            traceback.print_exc()

if __name__ == "__main__":
    main()
