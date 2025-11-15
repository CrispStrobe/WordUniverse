#!/usr/bin/env python3
"""
German Vocabulary Filter for Children (Age 9+)

Features:
- Multiple provider support with automatic fallback (Groq, Together, OpenRouter, etc.)
- Rate limiting and error handling
- Progress tracking and incremental saving
- Manual filter + AI verification
"""

import json
import os
import sys
import time
import logging
import requests
from typing import List, Dict, Set, Optional, Tuple
from dataclasses import dataclass, field
from pathlib import Path

# Load environment variables from .env file
from dotenv import load_dotenv
load_dotenv()  # This must come before any os.getenv() calls

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class ProviderConfig:
    name: str
    api_key: str
    models: List[str]
    rate_limit_rpm: int = 60
    rate_limit_daily: Optional[int] = None
    base_url: Optional[str] = None
    enabled: bool = True

@dataclass
class RateLimitTracker:
    requests_count: int = 0
    daily_requests: int = 0
    last_reset: float = field(default_factory=time.time)
    last_daily_reset: float = field(default_factory=time.time)
    consecutive_errors: int = 0
    backoff_until: float = 0.0
    
    def reset_if_needed(self):
        current_time = time.time()
        if current_time - self.last_reset >= 60:
            self.requests_count = 0
            self.last_reset = current_time
        if current_time - self.last_daily_reset >= 86400:
            self.daily_requests = 0
            self.last_daily_reset = current_time
    
    def can_make_request(self, rpm_limit: int, daily_limit: Optional[int] = None) -> bool:
        self.reset_if_needed()
        current_time = time.time()
        
        if current_time < self.backoff_until:
            return False
        if daily_limit and self.daily_requests >= daily_limit:
            return False
        return self.requests_count < rpm_limit
    
    def record_request(self):
        self.requests_count += 1
        self.daily_requests += 1
        self.consecutive_errors = 0
    
    def record_error(self):
        self.consecutive_errors += 1
        backoff_minutes = min(2 ** self.consecutive_errors, 30)
        self.backoff_until = time.time() + (backoff_minutes * 60)
        logger.warning(f"Backing off for {backoff_minutes} minutes")

class VocabularyFilter:
    def __init__(self):
        self.providers = self._initialize_providers()
        self.rate_trackers = {name: RateLimitTracker() for name in self.providers.keys()}
        self.current_provider_index = 0
        self.provider_names = list(self.providers.keys())
        
        self.known_inappropriate_all = {
            'ficken', 'fick', 'gefickt', 'scheiße', 'scheisse', 'scheiss',
            'arsch', 'arschloch', 'schwanz', 'schwanzlutscher', 'fotze', 
            'wichser', 'wichsen', 'hurensohn', 'nutte', 'hure', 'puff',
            'verdammt', 'verfickt', 'beschissen', 'bumsen', 'vögeln',
            'blödmann', 'drecksack', 'scheißkerl', 'pisser', 'pissen',
            'pimmel', 'möse', 'titten', 'titte', 'arschgeige',
            'kacke', 'kacken', 'scheiß', 'wixer', 'drecksau',
            'mistkerl', 'fotzen', 'votze', 'vögelt', 
            'onanieren', 'masturbieren', 'orgasmus',
            # Additional from AI filtering
            'vergewaltigt', 'hinrichtung',
            'kokain', 'nazis', 'flittchen', 'droge',
            'verfickte', 'verflucht',
            'Arsch','Arschloch','Blödmann','Drecksack','Droge','Drogen','Fick','Flittchen','Hinrichtung','Hure','Hurensohn','Kacke','Kokain','Mistkerl','Nazis','Nutte','Scheiss','Scheisse','Scheiß','Scheiße','Scheißkerl','Schwanz','Schwanzlutscher','Titten','Verdammt','Wichser','abhauen','abschaum','affäre','alkohol','alkoholiker','ammenhai','anmachen','anschläge','antisemitismus','arschlöcher','asozial','ausgezogen','ausziehen','bastard','bastarde','behindert','behinderte','bescheuert','beschissen','beschissene','beschissenen','beschissener','besoffen','betrunken','bh','bier','biest','blasen','blut','blöd','blöde','blöden','blödes','blödsinn','bombardieren','brust','brutal','brüste','bud','bude','bulle','bullen','bullshit','bumsen','busen','bürgerkrieg','casino','colt','dealer','dekolleté','depp','diarrhö','dicke','disko','diskriminierung','doof','dreckige','dreckigen','dreckiger','dreckskerl','drohungen','dumm','dumme','dummkopf','durchgeknallt','durchsuchungsbefehl','einbrechen','einbruch','einfaltspinsel','entführung','ermorden','ermordet','ermordung','erpressung','erregen','erschieß','erschießen','erschlagen','erschossen','erstochen','feigling','ficken','folter','foltern','freier','fresse','fuck','gauner','gefickt','gehasst','geil','geisel','geißeln','geschrei','gewalt','gewehre','gin','griesgram','hasardeur','haß','heroin','hingerichtet','hitler','huren','höschen','idiot','idioten','ira','irrer','junkie','kannibale','killer','klugscheißer','knast','kneipe','koks','kommunisten','krüppel','körperverletzung','köter','leck','leiche','lesbisch','loser','lynchen','marihuana','massaker','mieser','mischpoke','miststück','mißbrauch','mord','morde','mordes','muschi','nackt','nackte','narr','nationalismus','nationalsozialismus','nigger','nutten','patrouille','penis','penner','pinkeln','pissen','pistole','pistolen','po','pogrom','poker','pornos','prostituierte','pussy','rasse','rassismus','rauchen','raucher','raucherin','rauchst','sack','sau','scheiden','scheißegal','scheißen','scheißer','schieß','schießerei','schiss','schlampe','schlampen','schnaps','schuss','schwachkopf','schwachsinn','schwuchtel','schwul','schwänze','selbstmord','sex','sexualität','sexuell','sexuelle','sexuellen','sexy','shit','skandal','sklave','sklaven','spinner','spinnt','sprengstoff','spritzen','stöhnen','suchtmittel','söldner','sünde','sünden','tabak','tequila','terror','terrorist','terroristen','todes','todesstrafe','trottel','tussi','tödlichen','töte','tötest','tötet','tötete','umbringen','umgebracht','umzubringen','unterhose','unterwäsche','vagina','verarschen','verarscht','verdammte','verdammten','verdammter','verdammtes','verfickte','verflucht','verfluchte','verfluchten','verführen','vergewaltigt','vergewaltigung','verknallt','verpiss','verprügeln','verprügelt','versauen','versaut','vollidiot','vögeln','waffe','waffen','weiber','weichei','wein','whiskey','whisky','wodka','wurscht','zigarette','zigaretten','zigarre','zuhälter','zuschlagen','ärsche'
        }
        self.known_inappropriate = { # filtered to include educational wordlists vocabulary still. note some are ambiguous depending on use/context
            'ficken', 'fick', 'gefickt', 'scheiße', 'scheisse', 'scheiss',
            'arsch', 'arschloch', 'schwanz', 'schwanzlutscher', 'fotze', 
            'wichser', 'wichsen', 'hurensohn', 'nutte', 'hure', 'puff',
            'verdammt', 'verfickt', 'beschissen', 'bumsen', 'vögeln',
            'blödmann', 'drecksack', 'scheißkerl', 'pisser', 'pissen',
            'pimmel', 'möse', 'titten', 'titte', 'arschgeige',
            'kacke', 'kacken', 'scheiß', 'wixer', 'drecksau',
            'mistkerl', 'fotzen', 'votze', 'vögelt', 
            'onanieren', 'masturbieren', 'orgasmus',
            # Additional from AI filtering
            'vergewaltigt', 'hinrichtung',
            'kokain', 'nazis', 'flittchen',
            'verfickte', 'verflucht',
            'Arsch','Arschloch','Blödmann','Drecksack','Fick','Flittchen','Hinrichtung','Hure','Hurensohn','Kacke','Kokain','Mistkerl','Nazis','Nutte','Scheiss','Scheisse','Scheiß','Scheiße','Scheißkerl','Schwanz','Schwanzlutscher','Titten','Verdammt','Wichser','abhauen','abschaum','affäre','alkoholiker','anschläge','antisemitismus','arschlöcher','ausgezogen','bastard','bastarde','behindert','behinderte','bescheuert','beschissen','beschissene','beschissenen','beschissener','besoffen','bh','biest','blasen','blut','blöden','blödes','blödsinn','brutal','brüste','bud','bude','bulle','bullen','bullshit','busen','bürgerkrieg','casino','colt','dealer','depp','dicke','diskriminierung','dreckige','dreckigen','dreckiger','dreckskerl','drohungen','dummkopf','durchgeknallt','durchsuchungsbefehl','entführung','ermorden','ermordet','ermordung','erpressung','erregen','erschieß','erschießen','erschlagen','erschossen','erstochen','feigling','folter','foltern','freier','fresse','fuck','gauner','gefickt','gehasst','geil','gin','heroin','hingerichtet','hitler','huren','höschen','idiot','idioten','ira','irrer','junkie','killer','klugscheißer','knast','koks','kommunisten','krüppel','körperverletzung','köter','leck','leiche','lesbisch','marihuana','massaker','mieser','miststück','mißbrauch','mord','morde','mordes','muschi','nackt','nackte','narr','nationalismus','nationalsozialismus','nigger','nutten','patrouille','penis','penner','pinkeln','pistole','pistolen','po','poker','pornos','prostituierte','pussy','rasse','rassismus','rauchst','sau','scheißegal','scheißen','scheißer','schieß','schießerei','schiss','schlampe','schlampen','schnaps','schuss','schwachkopf','schwachsinn','schwuchtel','schwul','schwänze','selbstmord','sex','sexualität','sexuell','sexuelle','sexuellen','sexy','shit','skandal','sklave','sklaven','spinner','spinnt','sprengstoff','stöhnen','söldner','sünde','sünden','tabak','tequila','terror','terrorist','terroristen','todes','todesstrafe','trottel','tussi','tödlichen','töte','tötest','tötet','tötete','umbringen','umgebracht','umzubringen','unterhose','unterwäsche','vagina','verarschen','verarscht','verdammte','verdammten','verdammter','verdammtes','verfickte','verflucht','verfluchte','verfluchten','verführen','vergewaltigung','verknallt','verpiss','verprügeln','verprügelt','versauen','versaut','vollidiot','weiber','weichei','whiskey','whisky','wodka','zigarre','zuhälter','zuschlagen','ärsche'
        }
    
    def _initialize_providers(self) -> Dict[str, ProviderConfig]:
        """Initialize providers - using only working ones"""
        providers = {}
        
        # Groq - Use requests API instead of SDK to avoid version issues
        groq_key = os.getenv("GROQ_API_KEY", "")
        if groq_key:
            providers["groq"] = ProviderConfig(
                name="Groq",
                api_key=groq_key,
                models=["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
                rate_limit_rpm=25,  # Conservative to avoid hitting limits
                rate_limit_daily=14000,  # Leave some buffer
                base_url="https://api.groq.com/openai/v1"
            )
        
        # OpenRouter - Slow it down to avoid rate limits
        openrouter_key = os.getenv("OPENROUTER_API_KEY", "")
        if openrouter_key:
            providers["openrouter"] = ProviderConfig(
                name="OpenRouter",
                api_key=openrouter_key,
                models=[
                    "meta-llama/llama-3.3-70b-instruct:free",
                    "deepseek/deepseek-chat:free",
                    "mistralai/mistral-7b-instruct:free"
                ],
                rate_limit_rpm=15,  # Conservative - actual limit is 20
                rate_limit_daily=45,  # Conservative - actual limit is 50
                base_url="https://openrouter.ai/api/v1"
            )
        
        # Google AI - Fixed model names for v1 API
        googleai_key = os.getenv("GOOGLEAI_API_KEY", "")
        if googleai_key:
            providers["googleai"] = ProviderConfig(
                name="GoogleAI",
                api_key=googleai_key,
                models=["gemini-1.5-flash-latest", "gemini-1.5-pro-latest"],
                rate_limit_rpm=14,  # Conservative - actual is 15
                base_url="https://generativelanguage.googleapis.com/v1beta"
            )
        
        # Mistral
        mistral_key = os.getenv("MISTRAL_API_KEY", "")
        if mistral_key:
            providers["mistral"] = ProviderConfig(
                name="Mistral",
                api_key=mistral_key,
                models=["open-mistral-nemo", "mistral-small-latest"],
                rate_limit_rpm=50,
                base_url="https://api.mistral.ai/v1"
            )
        
        if not providers:
            logger.error("No providers configured!")
            logger.info("\nSet at least one API key:")
            logger.info("  GROQ_API_KEY")
            logger.info("  OPENROUTER_API_KEY")
            logger.info("  GOOGLEAI_API_KEY")
            logger.info("  MISTRAL_API_KEY")
            sys.exit(1)
        
        logger.info(f"Initialized {len(providers)} providers: {list(providers.keys())}")
        return providers
    
    def get_next_available_provider(self) -> Optional[Tuple[str, ProviderConfig]]:
        """Get next available provider"""
        attempts = 0
        max_attempts = len(self.providers) * 3
        
        while attempts < max_attempts:
            provider_name = self.provider_names[self.current_provider_index]
            provider_config = self.providers[provider_name]
            rate_tracker = self.rate_trackers[provider_name]
            
            self.current_provider_index = (self.current_provider_index + 1) % len(self.provider_names)
            attempts += 1
            
            if not provider_config.enabled:
                continue
                
            if rate_tracker.can_make_request(provider_config.rate_limit_rpm, provider_config.rate_limit_daily):
                return provider_name, provider_config
        
        return None
    
    def call_groq_api(self, config: ProviderConfig, messages: List[Dict], model: str) -> str:
        """Call Groq using requests to avoid SDK version issues"""
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {config.api_key}"
        }
        
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500
        }
        
        response = requests.post(
            f"{config.base_url}/chat/completions",
            headers=headers,
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            return response.json()["choices"][0]["message"]["content"]
        else:
            raise Exception(f"Groq error {response.status_code}: {response.text}")
    
    def call_openrouter_api(self, config: ProviderConfig, messages: List[Dict], model: str) -> str:
        """Call OpenRouter API"""
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {config.api_key}",
            "HTTP-Referer": "https://github.com/vocab-filter"
        }
        
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500
        }
        
        response = requests.post(
            f"{config.base_url}/chat/completions",
            headers=headers,
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            return response.json()["choices"][0]["message"]["content"]
        else:
            raise Exception(f"OpenRouter error {response.status_code}: {response.text}")
    
    def call_googleai_api(self, config: ProviderConfig, messages: List[Dict], model: str) -> str:
        """Call Google AI API with v1beta endpoint"""
        url = f"{config.base_url}/models/{model}:generateContent?key={config.api_key}"
        
        headers = {"Content-Type": "application/json"}
        
        # Build contents from messages
        contents = []
        for msg in messages:
            if msg["role"] == "user":
                contents.append({"role": "user", "parts": [{"text": msg["content"]}]})
            elif msg["role"] == "assistant":
                contents.append({"role": "model", "parts": [{"text": msg["content"]}]})
        
        payload = {
            "contents": contents,
            "generationConfig": {
                "temperature": 0.1,
                "maxOutputTokens": 500
            }
        }
        
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        
        if response.status_code == 200:
            result = response.json()
            if "candidates" in result and result["candidates"]:
                parts = result["candidates"][0]["content"]["parts"]
                return "".join(part.get("text", "") for part in parts)
            return ""
        else:
            raise Exception(f"GoogleAI error {response.status_code}: {response.text}")
    
    def call_mistral_api(self, config: ProviderConfig, messages: List[Dict], model: str) -> str:
        """Call Mistral API"""
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {config.api_key}"
        }
        
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500
        }
        
        response = requests.post(
            f"{config.base_url}/chat/completions",
            headers=headers,
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            return response.json()["choices"][0]["message"]["content"]
        else:
            raise Exception(f"Mistral error {response.status_code}: {response.text}")
    
    def call_provider_api(self, provider_name: str, config: ProviderConfig, messages: List[Dict], model: str) -> str:
        """Route to appropriate API"""
        if provider_name == "groq":
            return self.call_groq_api(config, messages, model)
        elif provider_name == "openrouter":
            return self.call_openrouter_api(config, messages, model)
        elif provider_name == "googleai":
            return self.call_googleai_api(config, messages, model)
        elif provider_name == "mistral":
            return self.call_mistral_api(config, messages, model)
        else:
            raise ValueError(f"Unknown provider: {provider_name}")
    
    def check_words_batch(self, words_batch: List[str]) -> Set[str]:
        """Check batch with fallback"""
        if not words_batch:
            return set()
        
        words_list = [w for w in words_batch if w]
        
        prompt = f"""Filter German vocabulary for 9-year-olds.

Check these words. Identify ONLY inappropriate ones (profanity, vulgar, sexual, offensive):
{', '.join(words_list)}

Return ONLY a JSON array: ["word1", "word2"] or []
NO explanations."""

        messages = [
            {"role": "system", "content": "You filter inappropriate words for children."},
            {"role": "user", "content": prompt}
        ]
        
        max_retries = 3
        
        for attempt in range(max_retries):
            provider_info = self.get_next_available_provider()
            
            if not provider_info:
                logger.warning("No providers available, waiting 30s...")
                time.sleep(30)
                continue
            
            provider_name, config = provider_info
            model = config.models[0]
            rate_tracker = self.rate_trackers[provider_name]
            
            try:
                logger.info(f"Checking with {provider_name}/{model}")
                response = self.call_provider_api(provider_name, config, messages, model)
                
                rate_tracker.record_request()
                
                # Parse JSON
                content = response.strip().replace("```json", "").replace("```", "").strip()
                
                try:
                    inappropriate = json.loads(content)
                    return set(w.lower() for w in inappropriate if isinstance(w, str))
                except json.JSONDecodeError:
                    # Try to extract words
                    import re
                    words_found = re.findall(r'"([^"]+)"', content)
                    if words_found:
                        return set(w.lower() for w in words_found if w.lower() in [word.lower() for word in words_list])
                    return set()
                
            except Exception as e:
                logger.error(f"Error with {provider_name}: {str(e)}")
                rate_tracker.record_error()
                
                # If rate limit error, disable provider temporarily
                if "429" in str(e) or "rate limit" in str(e).lower():
                    logger.warning(f"{provider_name} rate limited, extending backoff")
                    rate_tracker.backoff_until = time.time() + 300  # 5 minutes
                
                if attempt == max_retries - 1:
                    logger.error("All attempts failed")
                    return set()
                
                time.sleep(2 ** attempt)
        
        return set()
    
    def manual_filter(self, vocabulary: List[Dict]) -> Tuple[List[Dict], Set[str]]:
        """Manual filter"""
        logger.info("Running manual filter...")
        
        removed_words = set()
        filtered_vocabulary = []
        
        for entry in vocabulary:
            word_lower = entry['word'].lower()
            lemma_lower = entry.get('lemma', '').lower() if entry.get('lemma') else ''
            
            if word_lower in self.known_inappropriate or lemma_lower in self.known_inappropriate:
                removed_words.add(entry['word'])
            else:
                filtered_vocabulary.append(entry)
        
        logger.info(f"Manual filter removed {len(removed_words)} words")
        return filtered_vocabulary, removed_words
    
    def ai_filter(self, vocabulary: List[Dict], batch_size: int = 25) -> Tuple[List[Dict], Set[str]]:
        """AI filter with batching"""
        logger.info("Running AI filter...")
        
        unique_words = list(set(entry['word'] for entry in vocabulary))
        logger.info(f"Checking {len(unique_words)} unique words")
        
        inappropriate_found = set()
        batch_count = (len(unique_words) + batch_size - 1) // batch_size
        
        for i in range(0, len(unique_words), batch_size):
            batch = unique_words[i:i+batch_size]
            current_batch = (i // batch_size) + 1
            
            logger.info(f"Batch {current_batch}/{batch_count} ({len(batch)} words)")
            
            inappropriate = self.check_words_batch(batch)
            
            if inappropriate:
                logger.info(f"Found: {inappropriate}")
                inappropriate_found.update(inappropriate)
            
            if current_batch % 10 == 0:
                self.print_provider_status()
            
            # Adaptive delay based on available providers
            available_count = sum(1 for name in self.provider_names 
                                if self.rate_trackers[name].can_make_request(
                                    self.providers[name].rate_limit_rpm,
                                    self.providers[name].rate_limit_daily))
            
            if available_count <= 1:
                time.sleep(5)  # Slower if only one provider
            else:
                time.sleep(2)  # Normal pace with multiple providers
        
        filtered_vocabulary = [
            entry for entry in vocabulary 
            if entry['word'].lower() not in inappropriate_found
        ]
        
        logger.info(f"AI filter removed {len(inappropriate_found)} words")
        return filtered_vocabulary, inappropriate_found
    
    def filter_vocabulary(self, input_file: str, output_file: str, method: str = "hybrid"):
        """Main filter"""
        logger.info(f"Loading from {input_file}...")
        
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        vocabulary = data.get('vocabulary', [])
        original_count = len(vocabulary)
        logger.info(f"Total entries: {original_count}")
        
        all_removed = set()
        
        if method in ["manual", "hybrid"]:
            vocabulary, manual_removed = self.manual_filter(vocabulary)
            all_removed.update(manual_removed)
        
        if method in ["ai", "hybrid"]:
            vocabulary, ai_removed = self.ai_filter(vocabulary)
            all_removed.update(ai_removed)
        
        data['vocabulary'] = vocabulary
        
        logger.info(f"Saving to {output_file}...")
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        
        filtered_count = len(vocabulary)
        removed_count = original_count - filtered_count
        
        logger.info(f"\n{'='*60}")
        logger.info(f"Complete!")
        logger.info(f"Original: {original_count} | Filtered: {filtered_count} | Removed: {removed_count}")
        logger.info(f"{'='*60}\n")
        
        if all_removed:
            report_file = output_file.replace('.json', '_removed.txt')
            with open(report_file, 'w', encoding='utf-8') as f:
                f.write("Removed words:\n" + "="*60 + "\n")
                for word in sorted(all_removed):
                    f.write(f"- {word}\n")
            logger.info(f"Report: {report_file}")
    
    def print_provider_status(self):
        """Print status"""
        logger.info("\nProvider Status:")
        logger.info("-" * 80)
        for name, config in self.providers.items():
            tracker = self.rate_trackers[name]
            tracker.reset_if_needed()
            
            status = "🟢 Available"
            if not config.enabled:
                status = "🔴 Disabled"
            elif tracker.consecutive_errors > 0:
                status = f"🟡 Errors: {tracker.consecutive_errors}"
            elif time.time() < tracker.backoff_until:
                remaining = int(tracker.backoff_until - time.time())
                status = f"🔴 Backoff: {remaining}s"
            
            daily = f"{tracker.daily_requests}/{config.rate_limit_daily or '∞'}"
            logger.info(f"{name:12} | {status:20} | {tracker.requests_count:3}/{config.rate_limit_rpm} req/min | {daily} daily")
        logger.info("-" * 80)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Filter German vocabulary')
    parser.add_argument('input_file', nargs='?', default='vocabulary.json')
    parser.add_argument('output_file', nargs='?', default='vocabulary_filtered.json')
    parser.add_argument('--method', choices=['manual', 'ai', 'hybrid'], default='manual',
                       help='Filter method (default: manual - AI filtering takes time!)')
    parser.add_argument('--batch-size', type=int, default=25)
    parser.add_argument('--status', action='store_true')
    
    args = parser.parse_args()
    
    try:
        vocab_filter = VocabularyFilter()
    except SystemExit:
        return
    
    if args.status:
        vocab_filter.print_provider_status()
        return
    
    vocab_filter.print_provider_status()
    
    try:
        vocab_filter.filter_vocabulary(args.input_file, args.output_file, args.method)
        logger.info("\nFinal status:")
        vocab_filter.print_provider_status()
        
    except KeyboardInterrupt:
        logger.info("\nInterrupted")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()