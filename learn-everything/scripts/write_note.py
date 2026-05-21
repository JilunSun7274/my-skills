import os
import argparse
import sys

def write_note(rel_path, content, kb_root):
    kb_root = os.path.expanduser(kb_root)
    full_path = os.path.join(kb_root, rel_path)
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    
    try:
        with open(full_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Successfully saved note to '{full_path}'.")
    except Exception as e:
        print(f"Error writing to file: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Save a note to the knowledge base.")
    parser.add_argument("rel_path", help="Relative path to save the .md file.")
    parser.add_argument("--content", help="The markdown content of the note. If omitted, it will read from stdin.")
    parser.add_argument("--path", default="~/Desktop/KnowledgeGraph", help="Root path of the knowledge base.")
    args = parser.parse_args()
    
    if args.content:
        content = args.content
    else:
        print("Reading note content from stdin (Press Ctrl+D when finished)...")
        content = sys.stdin.read()
    
    if not content:
        print("Error: No content provided. Note not saved.")
    else:
        write_note(args.rel_path, content, args.path)
