import os
import argparse

def list_kb(kb_root):
    kb_root = os.path.expanduser(kb_root)
    if not os.path.exists(kb_root):
        print(f"Error: Path '{kb_root}' does not exist.")
        return

    print(f"Knowledge Base Structure ({kb_root}):")
    # Get all folders and files recursively
    for root, dirs, files in os.walk(kb_root):
        # Exclude hidden directories like .git
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        rel_path = os.path.relpath(root, kb_root)
        if rel_path == '.':
            level = 0
        else:
            level = rel_path.count(os.sep) + 1
        
        indent = '  ' * level
        if rel_path != '.':
            print(f"{indent}📁 {os.path.basename(root)}/")
        
        sub_indent = '  ' * (level + 1)
        for f in sorted(files):
            if f.endswith('.md'):
                print(f"{sub_indent}📄 {f}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="List the knowledge base structure.")
    parser.add_argument("--path", default="~/Desktop/KnowledgeGraph", help="Root path of the knowledge base.")
    args = parser.parse_args()
    list_kb(args.path)
