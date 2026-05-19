import json
import os

# Configuration
INPUT_FILE = 'grundwortschatz_v24.json'
OUTPUT_FILE = 'grammar_exercises.json'

def check_and_extract():
    print(f"📂 Loading {INPUT_FILE}...")
    
    if not os.path.exists(INPUT_FILE):
        print(f"❌ Error: File '{INPUT_FILE}' not found.")
        return

    try:
        with open(INPUT_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Check if key exists
        if 'grammarExercises' not in data:
            print("ℹ️  Result: Key 'grammarExercises' DOES NOT EXIST in this file.")
            return

        exercises = data['grammarExercises']
        
        # Check if list is valid and not empty
        if isinstance(exercises, list) and len(exercises) > 0:
            print(f"✅ Found {len(exercises)} grammar exercises!")
            
            # Create the wrapper structure expected by your app
            output_data = {
                "grammarExercises": exercises
            }
            
            with open(OUTPUT_FILE, 'w', encoding='utf-8') as f_out:
                json.dump(output_data, f_out, indent=2, ensure_ascii=False)
            
            print(f"💾 Extracted to: {OUTPUT_FILE}")
        else:
            print("ℹ️  Result: 'grammarExercises' key exists but is EMPTY (List length is 0).")
            print("   (You can safely ignore the grammar loading logic in your app).")

    except Exception as e:
        print(f"❌ Error parsing JSON: {e}")

if __name__ == "__main__":
    check_and_extract()