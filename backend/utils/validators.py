# Utility Validators

import numpy as np

def validate_keypoints(keypoints):
    """
    Validate keypoints format and values
    
    Args:
        keypoints: Should be 60×21×3 array (60 frames, 21 landmarks, 3 coordinates)
    
    Returns:
        str: Error message if invalid, None if valid
    """
    if not keypoints:
        return "Keypoints cannot be empty"
    
    try:
        arr = np.array(keypoints, dtype=np.float32)
        
        if arr.ndim != 3:
            return f"Expected 3D array, got {arr.ndim}D"
        
        if arr.shape[0] != 60:
            return f"Expected 60 frames, got {arr.shape[0]}"
        
        if arr.shape[1] != 21:
            return f"Expected 21 landmarks, got {arr.shape[1]}"
        
        if arr.shape[2] != 3:
            return f"Expected 3 coordinates (x,y,z), got {arr.shape[2]}"
        
        # Check for NaN/Inf values
        if np.any(np.isnan(arr)) or np.any(np.isinf(arr)):
            return "Keypoints contain NaN or Inf values"
        
        # Check value ranges (should be normalized 0-1)
        if np.any(arr < -1) or np.any(arr > 1):
            return "Keypoint values should be normalized between -1 and 1"
        
        return None  # Valid
    
    except Exception as e:
        return f"Invalid keypoints format: {str(e)}"

def validate_text_input(text):
    """Validate text input"""
    if not text:
        return "Text cannot be empty"
    
    if len(text) > 1000:
        return "Text too long (max 1000 characters)"
    
    return None

def validate_language_code(language_code):
    """Validate language code"""
    valid_codes = ['en-US', 'es-ES', 'fr-FR', 'de-DE', 'it-IT', 'ja-JP', 'zh-CN']
    
    if language_code not in valid_codes:
        return f"Unsupported language: {language_code}"
    
    return None
