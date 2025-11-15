#!/usr/bin/env python3
"""
Test script to discover Google AI (Gemini) models and test them
"""

import os
import requests
import json

def list_google_ai_models(api_key):
    """List all available Google AI models"""
    print("=" * 80)
    print("LISTING GOOGLE AI MODELS")
    print("=" * 80)
    
    # Try v1beta endpoint
    url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
    
    response = requests.get(url, timeout=10)
    
    if response.status_code == 200:
        data = response.json()
        models = data.get('models', [])
        
        print(f"\nFound {len(models)} models:\n")
        
        for model in models:
            name = model.get('name', 'Unknown')
            display_name = model.get('displayName', 'Unknown')
            supported_methods = model.get('supportedGenerationMethods', [])
            
            print(f"Name: {name}")
            print(f"Display Name: {display_name}")
            print(f"Supported Methods: {', '.join(supported_methods)}")
            
            # Check if it supports generateContent
            if 'generateContent' in supported_methods:
                print("✓ Supports generateContent")
            else:
                print("✗ Does NOT support generateContent")
            
            print("-" * 80)
        
        return models
    else:
        print(f"Error listing models: {response.status_code}")
        print(response.text)
        return []

def test_model(api_key, model_name):
    """Test a specific model with generateContent"""
    print("\n" + "=" * 80)
    print(f"TESTING MODEL: {model_name}")
    print("=" * 80)
    
    # Extract just the model ID (remove 'models/' prefix if present)
    model_id = model_name.replace('models/', '')
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_id}:generateContent?key={api_key}"
    
    headers = {"Content-Type": "application/json"}
    
    payload = {
        "contents": [{
            "parts": [{
                "text": "Say hello in German."
            }]
        }],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 100
        }
    }
    
    print(f"\nURL: {url}")
    print(f"Payload: {json.dumps(payload, indent=2)}")
    
    response = requests.post(url, headers=headers, json=payload, timeout=30)
    
    print(f"\nResponse Status: {response.status_code}")
    
    if response.status_code == 200:
        result = response.json()
        print("✓ Success!")
        
        if "candidates" in result and result["candidates"]:
            candidate = result["candidates"][0]
            if "content" in candidate and "parts" in candidate["content"]:
                for part in candidate["content"]["parts"]:
                    if "text" in part:
                        print(f"\nModel Response: {part['text']}")
        else:
            print("No content in response")
            print(json.dumps(result, indent=2))
    else:
        print("✗ Failed!")
        print(f"\nError Response: {response.text}")

def main():
    api_key = os.getenv("GOOGLEAI_API_KEY", "")
    
    if not api_key:
        print("Error: GOOGLEAI_API_KEY environment variable not set!")
        print("\nSet it with:")
        print("  export GOOGLEAI_API_KEY='your_key_here'")
        return
    
    print(f"Using API key: {api_key[:20]}...")
    
    # List all models
    models = list_google_ai_models(api_key)
    
    if not models:
        print("\nNo models found or error occurred")
        return
    
    # Find models that support generateContent
    generate_content_models = [
        m for m in models 
        if 'generateContent' in m.get('supportedGenerationMethods', [])
    ]
    
    print("\n" + "=" * 80)
    print("MODELS THAT SUPPORT generateContent:")
    print("=" * 80)
    
    for model in generate_content_models:
        name = model.get('name', '')
        display_name = model.get('displayName', '')
        print(f"  • {name} ({display_name})")
    
    # Test a few common models
    print("\n" + "=" * 80)
    print("TESTING COMMON MODELS")
    print("=" * 80)
    
    test_models = [
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "gemini-2.0-flash-exp",
        "gemini-pro",
    ]
    
    for model_name in test_models:
        # Check if this model exists in our list
        full_name = f"models/{model_name}"
        exists = any(m.get('name') == full_name for m in models)
        
        if exists:
            print(f"\n✓ Model {model_name} exists, testing...")
            test_model(api_key, model_name)
        else:
            print(f"\n✗ Model {model_name} not found in available models")
    
    # Also test the first available generateContent model
    if generate_content_models:
        print("\n" + "=" * 80)
        print("TESTING FIRST AVAILABLE MODEL")
        print("=" * 80)
        
        first_model = generate_content_models[0]
        model_name = first_model.get('name', '').replace('models/', '')
        print(f"\nTesting: {model_name}")
        test_model(api_key, model_name)
    
    # Print summary with correct model names to use
    print("\n" + "=" * 80)
    print("SUMMARY - MODELS TO USE IN YOUR CODE:")
    print("=" * 80)
    
    for model in generate_content_models:
        name = model.get('name', '').replace('models/', '')
        display_name = model.get('displayName', '')
        print(f"  '{name}',  # {display_name}")

if __name__ == "__main__":
    main()
