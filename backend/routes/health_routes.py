# Health Check & Status Routes

from flask import Blueprint, jsonify, current_app
from datetime import datetime
from sqlalchemy import text
import os

health_bp = Blueprint('health', __name__)

@health_bp.route('/health', methods=['GET'])
def health_check():
    """
    Health check endpoint - Basic system status
    
    Returns:
        {
            "success": true,
            "status": "healthy",
            "timestamp": "2024-01-01T12:00:00Z",
            "uptime_seconds": 3600,
            "environment": "production"
        }
    """
    return jsonify({
        'success': True,
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'environment': os.getenv('FLASK_ENV', 'development'),
        'api_version': '1.0.0'
    }), 200

@health_bp.route('/status/models', methods=['GET'])
def model_status():
    """
    Get status of loaded models
    
    Returns model availability and inference statistics
    """
    try:
        model_manager = current_app.model_manager
        
        status = {
            'success': True,
            'models': {
                'sign_recognition': {
                    'loaded': model_manager.sign_model is not None,
                    'path': os.getenv('SIGN_MODEL_PATH', 'N/A'),
                    'type': 'LSTM (Keras)',
                    'classes': 30,
                    'input_shape': (60, 258)
                },
                'alphabet_classifier': {
                    'loaded': model_manager.alphabet_model is not None,
                    'path': os.getenv('ALPHABET_MODEL_PATH', 'N/A'),
                    'type': 'Random Forest (Sklearn)',
                    'classes': 26,
                    'input_shape': (63,)
                }
            },
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return jsonify(status), 200
    
    except Exception as e:
        current_app.logger.error(f"Model status error: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e),
            'status': 'error'
        }), 500

@health_bp.route('/status/system', methods=['GET'])
def system_status():
    """
    Get system resource usage
    
    Returns CPU, memory, and GPU statistics
    """
    try:
        import psutil
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        status = {
            'success': True,
            'cpu': {
                'usage_percent': cpu_percent,
                'cores': psutil.cpu_count()
            },
            'memory': {
                'total_mb': memory.total / (1024 ** 2),
                'used_mb': memory.used / (1024 ** 2),
                'percent': memory.percent
            },
            'disk': {
                'total_mb': disk.total / (1024 ** 2),
                'used_mb': disk.used / (1024 ** 2),
                'percent': disk.percent
            },
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return jsonify(status), 200
    
    except ImportError:
        current_app.logger.warning("psutil not installed — system status unavailable")
        return jsonify({
            'success': False,
            'error': 'psutil not installed',
            'status': 'degraded'
        }), 503
    except Exception as e:
        current_app.logger.error(f"System status error: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e),
            'status': 'degraded'
        }), 500

@health_bp.route('/status/services', methods=['GET'])
def service_status():
    """
    Check external service connectivity
    
    Returns status of Azure Speech, Database, Cache, etc.
    """
    status = {
        'success': True,
        'services': {}
    }
    
    # Check Database
    try:
        from backend.app import db
        db.session.execute(text('SELECT 1'))
        status['services']['database'] = {'status': 'ok', 'type': 'SQLAlchemy'}
    except Exception as e:
        status['services']['database'] = {'status': 'error', 'error': str(e)}
    
    # Check Redis (optional)
    try:
        import redis
        redis_host = os.getenv('REDIS_HOST', 'localhost')
        redis_port = int(os.getenv('REDIS_PORT', 6379))
        r = redis.Redis(host=redis_host, port=redis_port, db=0, socket_connect_timeout=5)
        r.ping()
        status['services']['redis'] = {'status': 'ok', 'host': redis_host}
    except Exception as e:
        status['services']['redis'] = {'status': 'warning', 'error': 'Not available (optional)'}
    
    # Check Azure Speech (optional)
    if os.getenv('AZURE_SPEECH_KEY'):
        status['services']['azure_speech'] = {'status': 'configured', 'region': os.getenv('AZURE_SPEECH_REGION')}
    else:
        status['services']['azure_speech'] = {'status': 'not_configured'}
    
    status['timestamp'] = datetime.utcnow().isoformat()
    
    return jsonify(status), 200
