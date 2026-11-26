"""Application-recorded AI content provenance for vocabulary packs.

This metadata is not a watermark, signature, human-review claim, or proof of
compliance. Unknown historical details stay unknown. Source/license fields are
never replaced. Only call record_fields for content actually accepted/written.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from urllib.parse import urlsplit

SCHEMA = 'word_universe.ai_content.v1'
ORIGINS = {'ai_generated', 'ai_assisted_revision'}


PUBLIC_PROVIDERS = {
    'api.openai.com': 'openai', 'api.anthropic.com': 'anthropic',
    'api.mistral.ai': 'mistral', 'api.scaleway.ai': 'scaleway',
    'api.tokenfactory.nebius.com': 'nebius', 'api.studio.nebius.com': 'nebius',
    'api.groq.com': 'groq', 'api.cerebras.ai': 'cerebras',
    'api.cohere.com': 'cohere', 'api.cohere.ai': 'cohere',
    'generativelanguage.googleapis.com': 'google', 'api.together.xyz': 'together',
    'inference.hetzner.com': 'hetzner', 'opencode.ai': 'opencode',
    'openrouter.ai': 'openrouter', 'api.x.ai': 'xai', 'api.deepseek.com': 'deepseek',
    'api.perplexity.ai': 'perplexity', 'api.fireworks.ai': 'fireworks',
}


def _endpoint(endpoint):
    if endpoint in ('local_endpoint', 'configured_endpoint'):
        return endpoint, endpoint
    try:
        host = urlsplit(endpoint if '://' in endpoint else 'https://' + endpoint).hostname or ''
    except ValueError:
        host = ''
    if host in PUBLIC_PROVIDERS:
        return PUBLIC_PROVIDERS[host], host
    label = 'local_endpoint' if host in ('localhost', '127.0.0.1', '::1') else 'configured_endpoint'
    return label, label


def _model_id(value, public_provider=False):
    if not isinstance(value, str) or not value or value.strip() != value:
        return None
    if (value.startswith(('/', '~')) or '\\' in value or '://' in value
            or '?' in value or '#' in value
            or (not public_provider and '/' in value)
            or len(value.split('/')) > 2 or any(p in ('.', '..') for p in value.split('/'))
            or re.search(r'^(?:[A-Za-z]:[/\\]|file:|https?:|data:|s3:|gs:)', value, re.I)
            or re.search(r'\.(gguf|ggml|bin|onnx|safetensors|pt|pth|tflite|mlx)$', value, re.I)):
        return None
    return value


def response_metadata(provider, endpoint, requested_model, response_model=None):
    """Record the successful public provider; redact private hosts/model paths."""
    label, host = _endpoint(endpoint)
    result = {'provider': label, 'provider_host': host,
              'received_at': datetime.now(timezone.utc).isoformat()}
    for key, value in (('requested_model', requested_model), ('response_model', response_model)):
        model = _model_id(value, host in PUBLIC_PROVIDERS)
        if model:
            result[key] = model
    return result


def generation_from_record(record):
    """Replay known details without borrowing today's route or exposing secrets."""
    raw = record.get('generation')
    if not isinstance(raw, dict):
        raw = {'provider': record.get('provider'), 'requested_model': record.get('by')}
    result = {}
    host = raw.get('provider_host')
    if isinstance(host, str) and host:
        result['provider'], result['provider_host'] = _endpoint(host)
    elif isinstance(raw.get('provider'), str):
        result['provider'] = (raw['provider'] if raw['provider'] in PUBLIC_PROVIDERS.values()
                              else 'configured_endpoint')
    public = result.get('provider') in PUBLIC_PROVIDERS.values()
    for key in ('requested_model', 'response_model'):
        model = _model_id(raw.get(key), public)
        if model:
            result[key] = model
    received = raw.get('received_at')
    if isinstance(received, str):
        try:
            datetime.fromisoformat(received)
            result['received_at'] = received
        except ValueError:
            pass
    return result


def value_digest(value):
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
                         separators=(',', ':')).encode('utf-8')
    return hashlib.sha256(encoded).hexdigest()


def record_fields(metadata, values, generation=None, *, origin='ai_generated'):
    if not values:
        return
    if origin not in ORIGINS:
        raise ValueError(f'Unsupported AI content origin: {origin}')
    content = metadata.setdefault('ai_content', {})
    content['schema'] = SCHEMA
    fields = content.setdefault('fields', {})
    generation = generation_from_record({'generation': generation or {}})
    for path, value in values.items():
        fields[path] = {
            'origin': origin,
            'value_sha256': value_digest(value),
            'generation': dict(generation),
            'details_status': ('recorded' if generation.get('received_at')
                               and generation.get('provider_host')
                               and generation.get('requested_model')
                               else 'partial' if generation else 'unrecorded'),
        }


def _at_path(document, path):
    value = document
    for component in path.split('.'):
        value = value[int(component)] if isinstance(value, list) else value[component]
    return value


def legacy_ai_evidence(metadata):
    return ('LLM_GENERATED' in (metadata.get('sources') or [])
            or str(metadata.get('gloss_source', '')).startswith('llm-')
            or bool(metadata.get('llm_corrected')))


def refresh_pack_manifest(db):
    """Counts describe recorded evidence; unrecorded never means human-made."""
    totals = Counter()
    origins = Counter()
    for metadata_json, enrichment_json in db.execute(
            'SELECT metadata_json, enrichment_json FROM words'):
        metadata = json.loads(metadata_json or '{}')
        document = {'metadata': metadata,
                    'enrichment': json.loads(enrichment_json or '{}')}
        valid = 0
        fields = metadata.get('ai_content', {}).get('fields', {})
        for path, record in fields.items():
            try:
                matches = value_digest(_at_path(document, path)) == record.get('value_sha256')
            except (KeyError, IndexError, ValueError, TypeError):
                matches = False
            if matches and record.get('origin') in ORIGINS:
                valid += 1
                origins[record['origin']] += 1
            else:
                totals['stale_field_records'] += 1
        totals['entries'] += 1
        if valid:
            totals['entries_with_recorded_ai_fields'] += 1
        elif legacy_ai_evidence(metadata):
            totals['entries_with_legacy_ai_evidence'] += 1
        else:
            totals['entries_with_unrecorded_origin'] += 1
    manifest = {
        'schema': 'word_universe.pack_ai_manifest.v1',
        'scope': 'words',
        'counts': {key: totals[key] for key in (
            'entries', 'entries_with_recorded_ai_fields',
            'entries_with_legacy_ai_evidence', 'entries_with_unrecorded_origin',
            'stale_field_records')},
        'recorded_fields_by_origin': dict(origins),
        'unrecorded_origin_means': 'unknown, not human-authored',
    }
    columns = {r[1] for r in db.execute('PRAGMA table_info(phrasal_verbs)')}
    if 'ai_content_json' in columns:
        phrasal = Counter()
        for meaning, examples, raw_content in db.execute(
                'SELECT meaning, examples_json, ai_content_json FROM phrasal_verbs'):
            phrasal['entries'] += 1
            document = {'meaning': meaning, 'examples': json.loads(examples or '{}')}
            fields = json.loads(raw_content or '{}').get('fields', {})
            valid = 0
            for path, record in fields.items():
                try:
                    matches = value_digest(_at_path(document, path)) == record.get('value_sha256')
                except (KeyError, IndexError, ValueError, TypeError):
                    matches = False
                if matches and record.get('origin') in ORIGINS:
                    valid += 1
                    phrasal[record['origin'] + '_fields'] += 1
                else:
                    phrasal['stale_field_records'] += 1
            phrasal['entries_with_recorded_ai_fields' if valid
                    else 'entries_with_unrecorded_origin'] += 1
        manifest['phrasal_verbs'] = {key: phrasal[key] for key in (
            'entries', 'entries_with_recorded_ai_fields',
            'entries_with_unrecorded_origin', 'stale_field_records',
            'ai_generated_fields', 'ai_assisted_revision_fields')}
    db.execute('CREATE TABLE IF NOT EXISTS content_provenance '
               '(key TEXT PRIMARY KEY, value_json TEXT NOT NULL)')
    db.execute('INSERT OR REPLACE INTO content_provenance VALUES (?, ?)',
               ('ai_content', json.dumps(manifest, ensure_ascii=False)))
    return manifest
