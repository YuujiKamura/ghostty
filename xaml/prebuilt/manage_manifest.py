import os
import hashlib
import json
import sys

# Directories to watch for changes
XAML_DIR = "xaml"
PREBUILT_DIR = os.path.join(XAML_DIR, "prebuilt")
MANIFEST_FILE = os.path.join(PREBUILT_DIR, "manifest.json")

# File extensions that contribute to the build output
EXTENSIONS = {".xaml", ".resw", ".csproj"}

def calculate_sha256(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def generate_manifest():
    manifest = {"sources": {}}
    
    # Scan XAML directory for source files
    for root, _, files in os.walk(XAML_DIR):
        # Skip obj/bin and prebuilt itself to avoid circularity or noise
        if "obj" in root or "bin" in root or "prebuilt" in root:
            continue
            
        for file in files:
            if any(file.endswith(ext) for ext in EXTENSIONS):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, start=XAML_DIR)
                manifest["sources"][rel_path] = calculate_sha256(full_path)
                
    # Sort for deterministic output
    manifest["sources"] = dict(sorted(manifest["sources"].items()))
    
    with open(MANIFEST_FILE, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Manifest generated at {MANIFEST_FILE}")

def verify_manifest():
    if not os.path.exists(MANIFEST_FILE):
        print("ERROR: Manifest file not found.")
        return False
        
    with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
        manifest = json.load(f)
        
    stale_files = []
    current_files = set()
    
    for root, _, files in os.walk(XAML_DIR):
        if "obj" in root or "bin" in root or "prebuilt" in root:
            continue
            
        for file in files:
            if any(file.endswith(ext) for ext in EXTENSIONS):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, start=XAML_DIR)
                current_files.add(rel_path)
                
                expected_hash = manifest["sources"].get(rel_path)
                if expected_hash is None:
                    print(f"STALE: New file detected: {rel_path}")
                    stale_files.append(rel_path)
                else:
                    actual_hash = calculate_sha256(full_path)
                    if actual_hash != expected_hash:
                        print(f"STALE: Modified file: {rel_path}")
                        stale_files.append(rel_path)
    
    # Check for deleted files
    for rel_path in manifest["sources"]:
        if rel_path not in current_files:
            print(f"STALE: Deleted file: {rel_path}")
            stale_files.append(rel_path)
            
    if stale_files:
        print(f"Found {len(stale_files)} mismatching file(s). Prebuilt assets are STALE.")
        return False
    else:
        print("Prebuilt assets are UP-TO-DATE.")
        return True

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--verify":
        if not verify_manifest():
            sys.exit(1)
    else:
        generate_manifest()
