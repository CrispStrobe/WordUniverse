import re

# Download the .sql file from OpenThesaurus (e.g., openthesaurus_dump.sql)
SQL_FILE = 'openthesaurus_dump.sql' 

def analyze_dump(filepath):
    print(f"🔍 Analyzing {filepath}...\n")
    
    current_table = None
    schema_lines = []
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Detect start of a table creation
                if line.startswith("CREATE TABLE"):
                    # Extract table name
                    match = re.search(r'CREATE TABLE `?(\w+)`?', line)
                    if match:
                        current_table = match.group(1)
                        print(f"--- TABLE: {current_table} ---")
                        print(line)
                        continue

                # If we are inside a table definition, print the lines
                if current_table:
                    # Stop at the end of the table definition
                    if line.endswith(';'):
                        print(line)
                        print("-" * 40 + "\n")
                        current_table = None
                    else:
                        # Print columns and keys
                        print(line)
                        
    except FileNotFoundError:
        print("❌ File not found. Please download the .sql dump first.")

if __name__ == "__main__":
    analyze_dump(SQL_FILE)