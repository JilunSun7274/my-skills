import os
import argparse

def read_note(rel_path, kb_root):
    kb_root = os.path.expanduser(kb_root)
    full_path = os.path.join(kb_root, rel_path)
    
    if not os.path.exists(full_path):
        print(f"Error: File '{full_path}' does not exist.")
        return
    
    if not os.path.isfile(full_path):
        print(f"Error: Path '{full_path}' is not a file.")
        return
        
    try:
        with open(full_path, 'r', encoding='utf-8') as f:
            print(f.read())
    except Exception as e:
        print(f"Error reading file: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Read a specific knowledge note.")
    parser.add_argument("rel_path", help="Relative path to the .md file (e.g., CS/OS.md).")
    parser.add_argument("--path", default="~/Desktop/KnowledgeGraph", help="Root path of the knowledge base.")
    args = parser.parse_args()
    read_note(args.rel_path, args.path)
