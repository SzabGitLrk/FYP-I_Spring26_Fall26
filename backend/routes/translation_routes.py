# Stub Route Files - Translation Routes

from flask import Blueprint, request, jsonify, current_app
from backend.app import limiter
import time
import re

translation_bp = Blueprint('translation', __name__)

# Word to animation file mapping
ANIMATION_MAP = {
    # Alphabet (26 letters)
    'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E', 'f': 'F', 'g': 'G',
    'h': 'H', 'i': 'I', 'j': 'J', 'k': 'K', 'l': 'L', 'm': 'M', 'n': 'N',
    'o': 'O', 'p': 'P', 'q': 'Q', 'r': 'R', 's': 'S', 't': 'T', 'u': 'U',
    'v': 'V', 'w': 'W', 'x': 'X', 'y': 'Y', 'z': 'Z',
    
    # Common words (mapped to available animations)
    'drink': 'Drinking', 'drinking': 'Drinking', 'thirsty': 'Drinking', 'drinks': 'Drinking',
    'water': 'Drinking', 'cup': 'Drinking',
    'bbq': 'BBQ', 'barbecue': 'BBQ', 'grill': 'BBQ',
    'idle': 'Idle', 'rest': 'Idle', 'neutral': 'Idle', 'stop': 'Idle', 'pause': 'Idle',
    
    # Common words (using alphabet fallback)
    'hello': 'H', 'hi': 'H', 'hey': 'H',
    'yes': 'Y', 'yeah': 'Y', 'ok': 'O',
    'no': 'N', 'not': 'N',
    'go': 'G', 'come': 'C', 'here': 'H',
    'good': 'G', 'great': 'G', 'better': 'B',
    'bad': 'B', 'sad': 'S', 'mad': 'M',
    'thanks': 'T', 'thank': 'T', 'thankyou': 'T',
    'please': 'P', 'sorry': 'S',
    'help': 'H', 'need': 'N', 'want': 'W',
    'sleep': 'S', 'bed': 'B', 'rest': 'R',
    'eat': 'E', 'food': 'F', 'hungry': 'H',
    'love': 'L', 'like': 'L',
    'person': 'P', 'people': 'P', 'man': 'M', 'woman': 'W',
    'time': 'T', 'when': 'W', 'where': 'W', 'what': 'W',
    'look': 'L', 'see': 'S', 'watch': 'W',
    'listen': 'L', 'hear': 'H', 'speak': 'S', 'talk': 'T',
    'wait': 'W', 'stay': 'S', 'find': 'F', 'have': 'H',
}

def word_to_animation(word):
    """Convert English word to animation file name"""
    if not word:
        return None
    
    word_lower = word.lower().strip()
    
    # Direct mapping
    if word_lower in ANIMATION_MAP:
        return ANIMATION_MAP[word_lower]
    
    # Remove punctuation and try again
    word_clean = re.sub(r'[^\w\s]', '', word_lower)
    if word_clean in ANIMATION_MAP:
        return ANIMATION_MAP[word_clean]
    
    # Single letter
    if len(word_clean) == 1 and word_clean.isalpha():
        return word_clean.upper()
    
    # Check first few characters
    for i in range(len(word_clean), 0, -1):
        prefix = word_clean[:i]
        if prefix in ANIMATION_MAP:
            return ANIMATION_MAP[prefix]
    
    # Try first character
    if word_clean and word_clean[0].isalpha():
        return word_clean[0].upper()
    
    # Fallback to Idle for unrecognized words
    return 'Idle'

@translation_bp.route('/translate/text-to-asl', methods=['POST'])
@limiter.limit("30 per minute")
def translate_text_to_asl():
    """
    Translate English text to ASL animation commands
    
    Request:
    {
        "text": "Hello, how are you?"
    }
    
    Response:
    {
        "success": true,
        "data": {
            "animation_sequence": ["H", "E", "L", "L", "O", ...],
            "original_text": "Hello, how are you?",
            "processed_text": "hello how are you"
        }
    }
    """
    try:
        if not request.json or 'text' not in request.json:
            return jsonify({'success': False, 'error': 'text field required'}), 400
        
        text = request.json['text']
        
        # Clean and split text
        processed_text = re.sub(r'[^\w\s]', '', text).lower().split()
        
        # Convert each word to animation
        animation_sequence = []
        for word in processed_text:
            if word:
                anim = word_to_animation(word)
                if anim:
                    animation_sequence.append(anim)
        
        # If no valid animations found, spell it out letter by letter
        if not animation_sequence:
            text_clean = re.sub(r'[^\w]', '', text).lower()
            for char in text_clean[:20]:  # Max 20 letters
                if char.isalpha():
                    animation_sequence.append(char.upper())
        
        return jsonify({
            'success': True,
            'data': {
                'animation_sequence': animation_sequence,
                'original_text': text,
                'processed_text': ' '.join(processed_text),
                'method': 'mapping'
            }
        }), 200
    
    except Exception as e:
        current_app.logger.error(f"Translation error: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@translation_bp.route('/translate/asl-to-text', methods=['POST'])
@limiter.limit("30 per minute")
def translate_asl_to_text():
    """
    Translate ASL gesture sequence to English text
    
    Request:
    {
        "gesture_sequence": ["hello", "friend"],
        "confidence_threshold": 0.75
    }
    
    Response:
    {
        "success": true,
        "data": {
            "text": "hello friend",
            "confidence": 0.87
        }
    }
    """
    try:
        if not request.json or 'gesture_sequence' not in request.json:
            return jsonify({'success': False, 'error': 'gesture_sequence required'}), 400
        
        gestures = request.json['gesture_sequence']
        
        # TODO: Implement ASL→Text conversion
        # For now, simple mock
        text = ' '.join(gestures)
        
        return jsonify({
            'success': True,
            'data': {
                'text': text,
                'confidence': 0.85
            }
        }), 200
    
    except Exception as e:
        current_app.logger.error(f"ASL to text error: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500
