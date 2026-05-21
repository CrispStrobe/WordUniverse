import pandas as pd
import json

# --- Configuration ---
EXCEL_FILE_NAME = 'YOUR_FILE.xlsx' # Make sure this is your .xlsx file
OUTPUT_JSON_NAME = 'output_nested.json'

# Read the Excel file, 4 header rows, first column is the index
try:
    df = pd.read_excel(EXCEL_FILE_NAME, header=[0, 1, 2, 3], index_col=0)
except FileNotFoundError:
    print(f"Error: The file '{EXCEL_FILE_NAME}' was not found.")
    print("Please make sure the file is in the same directory and the name is correct.")
    exit()
except Exception as e:
    print(f"An error occurred reading the Excel file: {e}")
    exit()

# === FIX #1: Skip the summary row ===
df = df.iloc[1:]
print("Skipped summary row...")

# === FIX #2: Handle messy merged cells ===
df.columns = pd.MultiIndex.from_frame(df.columns.to_frame().ffill())

# === Building the Nested JSON ===
all_records = []
print("Starting conversion...")

# Go through the Excel sheet row by row
for article, row_data in df.iterrows():
    
    record = {"Artikel": article}
    
    # Go through each column for that row
    for col_keys, value in row_data.items():
        
        # Only include cells that actually have a value (e.g., "x")
        if pd.notna(value):
            
            current_level_dict = record
            
            # Filter the header keys to remove "Unnamed" junk
            clean_keys = [
                str(key).strip() for key in col_keys if "Unnamed" not in str(key)
            ]
            
            # --- THIS IS THE ROBUST, CORRECTED LOGIC ---
            
            for i, key in enumerate(clean_keys):
                is_last_key = (i == len(clean_keys) - 1)
                
                if is_last_key:
                    # We are at the end of the path. Time to set the value.
                    
                    # Check if a sub-dictionary *already* exists here
                    # (from a longer path processed earlier)
                    existing_entry = current_level_dict.get(key)
                    
                    if isinstance(existing_entry, dict):
                        # e.g., (A, B, C) was set, now we're setting (A, B)
                        # Store as: B: { _value: "x", C: "y" }
                        existing_entry["_value"] = value
                    else:
                        # Simple case: B: "x"
                        current_level_dict[key] = value
                
                else:
                    # We are not at the end. We must descend into a dictionary.
                    next_level = current_level_dict.get(key)
                    
                    if isinstance(next_level, dict):
                        # Dict exists, just move into it
                        current_level_dict = next_level
                    elif next_level is None:
                        # No entry exists, create a new dict and move into it
                        new_dict = {}
                        current_level_dict[key] = new_dict
                        current_level_dict = new_dict
                    else:
                        # CONFLICT: An entry exists but it's a VALUE (a string).
                        # e.g., (A, B) was set to "x", now we need to set (A, B, C)
                        # We must *replace* "x" with a dict that *contains* "x".
                        # Replace B: "x" with B: { _value: "x" }
                        new_dict = {"_value": next_level}
                        current_level_dict[key] = new_dict
                        # Now move into the new dict
                        current_level_dict = new_dict
            
    all_records.append(record)

# --- Save the final JSON file ---
with open(OUTPUT_JSON_NAME, 'w', encoding='utf-8') as f:
    json.dump(all_records, f, ensure_ascii=False, indent=2)

print(f"Successfully created '{OUTPUT_JSON_NAME}'!")