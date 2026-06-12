# Prediction Routes - Real-time Sign Recognition from Video

from flask import Blueprint, request, jsonify, current_app
from datetime import datetime
import numpy as np
import cv2
import time
from backend.utils.validators import validate_keypoints
from backend.database.models import Prediction, Session
from backend.app import db, limiter

prediction_bp = Blueprint('prediction', __name__)

@prediction_bp.route('/predict/sign', methods=['POST'])
@limiter.limit("30 per minute")
def predict_sign():
    """
    Real-time sign language prediction from keypoints
    
    Request:
    {
        "keypoints": [[[x, y, z], ...], ...],  # 60 frames × 21 landmarks
        "session_id": "uuid"
    }
    
    Response:
    {
        "success": true,
        "data": {
            "prediction": "drink",
            "confidence": 0.92,
            "alternatives": [{"word": "water", "confidence": 0.06}],
            "latency_ms": 45,
            "method": "lstm"
        }
    }
    """
    try:
        start_time = time.time()
        
        # Validate request
        if not request.json:
            return jsonify({'success': False, 'error': 'Request body is required'}), 400
        
        keypoints = request.json.get('keypoints')
        session_id = request.json.get('session_id')
        
        # Validate keypoints format
        validation_error = validate_keypoints(keypoints)
        if validation_error:
            return jsonify({'success': False, 'error': validation_error}), 400
        
        # Convert to numpy array and reshape for model
        # Handles: (60, 21, 3) or (60, 63) or (60, 258) or (1, 60, 21, 3)
        keypoints_array = np.array(keypoints, dtype=np.float32)

        # Flatten batched dimension if present
        while keypoints_array.ndim > 2 and keypoints_array.shape[0] == 1:
            keypoints_array = keypoints_array[0]
        while keypoints_array.ndim > 2 and keypoints_array.shape[-1] <= 4 and keypoints_array.shape[-2] <= 21:
            keypoints_array = keypoints_array.reshape(keypoints_array.shape[0], -1)

        # If still 3D (60, 21, 3), flatten landmarks
        if keypoints_array.ndim == 3:
            keypoints_array = keypoints_array.reshape(keypoints_array.shape[0], -1)

        # Pad or truncate to 258 features
        if keypoints_array.shape[1] < 258:
            pad_width = 258 - keypoints_array.shape[1]
            keypoints_array = np.pad(keypoints_array, ((0, 0), (0, pad_width)), mode='constant')
        elif keypoints_array.shape[1] > 258:
            keypoints_array = keypoints_array[:, :258]
        
        # Get model manager
        model_manager = current_app.model_manager
        if not model_manager.sign_model:
            return jsonify({'success': False, 'error': 'Sign model not loaded'}), 503
        
        # Make prediction
        prediction = model_manager.sign_model.predict(
            np.expand_dims(keypoints_array, axis=0),
            verbose=0
        )[0]
        
        # Get top predictions
        top_indices = np.argsort(prediction)[::-1][:3]
        top_predictions = [
            {
                'word': current_app.config.get('TARGET_WORDS', [])[idx] if idx < len(current_app.config.get('TARGET_WORDS', [])) else f'word_{idx}',
                'confidence': float(prediction[idx])
            }
            for idx in top_indices
        ]
        
        latency_ms = (time.time() - start_time) * 1000
        
        # Get primary prediction
        primary_idx = np.argmax(prediction)
        primary_word = current_app.config.get('TARGET_WORDS', [])[primary_idx] if primary_idx < len(current_app.config.get('TARGET_WORDS', [])) else f'word_{primary_idx}'
        primary_confidence = float(prediction[primary_idx])
        
        # Store prediction in database
        if session_id:
            try:
                pred_record = Prediction(
                    session_id=session_id,
                    input_type='video',
                    prediction=primary_word,
                    confidence=primary_confidence,
                    alternatives=top_predictions[1:],
                    latency_ms=latency_ms,
                    model_used='lstm',
                    model_version='v2.1'
                )
                db.session.add(pred_record)
                db.session.commit()
            except Exception as e:
                current_app.logger.warning(f"Could not store prediction: {str(e)}")
                db.session.rollback()
        
        current_app.logger.info(f"✅ Prediction: {primary_word} ({primary_confidence:.2f}) - {latency_ms:.1f}ms")
        
        return jsonify({
            'success': True,
            'data': {
                'prediction': primary_word,
                'confidence': primary_confidence,
                'alternatives': top_predictions[1:],
                'latency_ms': latency_ms,
                'method': 'lstm'
            },
            'metadata': {
                'session_id': session_id,
                'timestamp': datetime.utcnow().isoformat(),
                'model_version': 'v2.1'
            }
        }), 200
    
    except Exception as e:
        current_app.logger.error(f"Prediction error: {str(e)}", exc_info=True)
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@prediction_bp.route('/predict/alphabet', methods=['POST'])
@limiter.limit("30 per minute")
def predict_alphabet():
    """
    Predict single letter from hand keypoints
    
    Request:
    {
        "keypoints": [[x, y, z], ...],  # 21 landmarks × 3 coordinates
        "session_id": "uuid"
    }
    
    Response:
    {
        "success": true,
        "data": {
            "letter": "A",
            "confidence": 0.95,
            "alternatives": [{"letter": "B", "confidence": 0.04}]
        }
    }
    """
    try:
        start_time = time.time()
        
        if not request.json:
            return jsonify({'success': False, 'error': 'Request body is required'}), 400
        
        keypoints = request.json.get('keypoints')
        session_id = request.json.get('session_id')
        
        # Normalize keypoints: handle both (21,3) and flat (63,) formats
        keypoints_array = np.array(keypoints, dtype=np.float32).flatten()
        if len(keypoints_array) != 21 * 3:
            return jsonify({'success': False, 'error': f'Expected 63 values (21 landmarks × 3), got {len(keypoints_array)}'}), 400
        
        # Get alphabet model
        model_manager = current_app.model_manager
        if not model_manager.alphabet_model:
            return jsonify({'success': False, 'error': 'Alphabet model not loaded'}), 503
        
        # Convert to DataFrame format (expected by sklearn model)
        import pandas as pd
        columns = [f'{axis}{i}' for i in range(21) for axis in ['x', 'y', 'z']]
        df = pd.DataFrame([keypoints_array], columns=columns)
        
        # Predict
        letter = model_manager.alphabet_model.predict(df)[0]
        confidence = model_manager.alphabet_model.predict_proba(df)[0].max()
        
        latency_ms = (time.time() - start_time) * 1000
        
        current_app.logger.info(f"✅ Letter prediction: {letter} ({confidence:.2f})")
        
        return jsonify({
            'success': True,
            'data': {
                'letter': letter,
                'confidence': float(confidence),
                'latency_ms': latency_ms
            },
            'metadata': {
                'session_id': session_id,
                'timestamp': datetime.utcnow().isoformat()
            }
        }), 200
    
    except Exception as e:
        current_app.logger.error(f"Alphabet prediction error: {str(e)}", exc_info=True)
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@prediction_bp.route('/predict/batch', methods=['POST'])
@limiter.limit("10 per minute")
def predict_batch():
    """
    Batch prediction for multiple frames
    
    Request:
    {
        "keypoints_batch": [[[...], ...], ...],
        "session_id": "uuid"
    }
    
    Response array of predictions
    """
    try:
        if not request.json:
            return jsonify({'success': False, 'error': 'Request body is required'}), 400
        
        keypoints_batch = request.json.get('keypoints_batch', [])
        session_id = request.json.get('session_id')
        
        if len(keypoints_batch) == 0:
            return jsonify({'success': False, 'error': 'Empty batch'}), 400
        
        # Convert all to array
        batch_array = np.array(keypoints_batch, dtype=np.float32)
        
        # Make batch predictions
        model_manager = current_app.model_manager
        if not model_manager.sign_model:
            return jsonify({'success': False, 'error': 'Sign model not loaded'}), 503
        predictions = model_manager.sign_model.predict(batch_array, verbose=0)
        
        results = []
        for idx, pred in enumerate(predictions):
            top_idx = np.argmax(pred)
            results.append({
                'frame': idx,
                'prediction': str(top_idx),
                'confidence': float(pred[top_idx])
            })
        
        return jsonify({
            'success': True,
            'data': {
                'predictions': results,
                'batch_size': len(keypoints_batch)
            }
        }), 200
    
    except Exception as e:
        current_app.logger.error(f"Batch prediction error: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500
