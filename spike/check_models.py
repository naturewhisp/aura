import urllib.request
import json
import sys

URL = "http://127.0.0.1:1234/v1/models"

def main():
    print(f"Connecting to LM Studio API server at: {URL}...")
    try:
        req = urllib.request.Request(URL)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
            
        models = [m["id"] for m in data.get("data", [])]
        print(f"\nConnection successful! Found {len(models)} models available:")
        for idx, m_id in enumerate(models, 1):
            print(f"  {idx}. {m_id}")
            
        target_evaluator = "mistralai/ministral-3-3b"
        target_actor = "qwen/qwen3.5-9b"
        
        has_evaluator = target_evaluator in models
        has_actor = target_actor in models
        
        print("\nChecking target models:")
        print(f"  - Evaluator ({target_evaluator}): {'[OK] Available' if has_evaluator else '[MISSING]'}")
        print(f"  - Actor ({target_actor}): {'[OK] Available' if has_actor else '[MISSING]'}")
        
        if not has_evaluator or not has_actor:
            print("\nWARNING: Some target models are missing in the LM Studio API list.")
            print("Please ensure they are loaded/active or double-check the IDs.")
            sys.exit(1)
        else:
            print("\nSUCCESS: All required models are available and ready for benchmarking!")
            sys.exit(0)
            
    except Exception as e:
        print(f"\nERROR: Failed to connect to LM Studio API server.")
        print(f"Details: {e}")
        print("\nPlease ensure that:")
        print("  1. LM Studio is open and running.")
        print("  2. The Local Server is started (usually on port 1234).")
        sys.exit(2)

if __name__ == "__main__":
    main()
