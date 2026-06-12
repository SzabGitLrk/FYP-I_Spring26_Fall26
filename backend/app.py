# Flask Application Factory - Main Backend Server

import logging
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '3')
os.environ.setdefault('TF_ENABLE_ONEDNN_OPTS', '0')

from flask import Flask
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from dotenv import load_dotenv
from datetime import datetime
import json

# Load environment variables
load_dotenv()

# Initialize extensions
db = SQLAlchemy()
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://"
)

# Configure logging
def setup_logging(app):
    """Configure JSON logging"""
    log_level = os.getenv('LOG_LEVEL', 'INFO')
    
    # Create logs directory if it doesn't exist
    if not os.path.exists('logs'):
        os.makedirs('logs')
    
    # JSON formatter for structured logging
    class JSONFormatter(logging.Formatter):
        def format(self, record):
            log_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'level': record.levelname,
                'logger': record.name,
                'message': record.getMessage(),
                'module': record.module,
                'lineno': record.lineno
            }
            if record.exc_info:
                log_data['exception'] = self.formatException(record.exc_info)
            return json.dumps(log_data)
    
    # File handler
    file_handler = logging.FileHandler('logs/dual_sense_ai.log')
    file_handler.setFormatter(JSONFormatter())
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    ))
    
    # Configure app logger
    app.logger.addHandler(file_handler)
    app.logger.addHandler(console_handler)
    app.logger.setLevel(log_level)
    
    return app.logger

def create_app(config_name='development'):
    """Application factory"""
    app = Flask(__name__)
    
    # Load configuration
    if config_name == 'production':
        from backend.config import ProductionConfig
        app.config.from_object(ProductionConfig)
    elif config_name == 'testing':
        from backend.config import TestingConfig
        app.config.from_object(TestingConfig)
    else:
        from backend.config import DevelopmentConfig
        app.config.from_object(DevelopmentConfig)
    
    # Initialize extensions
    db.init_app(app)
    limiter.init_app(app)

    # CORS - allow all origins by default; browsers treat 127.0.0.1 and localhost as different origins
    cors_origins = os.getenv('CORS_ORIGINS', '*').split(',')
    CORS(app, origins=cors_origins, methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
         allow_headers=['Content-Type', 'Authorization', 'Accept', 'X-Session-ID'],
         expose_headers=['Content-Type', 'Authorization'],
         max_age=600)
    
    # Setup logging
    logger = setup_logging(app)
    logger.info(f"🚀 Initializing Dual Sense AI Backend ({config_name.upper()} mode)")
    
    # Register error handlers
    register_error_handlers(app)
    
    # Register blueprints
    from backend.routes.health_routes import health_bp
    from backend.routes.prediction_routes import prediction_bp
    from backend.routes.translation_routes import translation_bp
    from backend.routes.speech_routes import speech_bp
    
    app.register_blueprint(health_bp, url_prefix='/api')
    app.register_blueprint(prediction_bp, url_prefix='/api')
    app.register_blueprint(translation_bp, url_prefix='/api')
    app.register_blueprint(speech_bp, url_prefix='/api')
    
    # Create database tables
    with app.app_context():
        db.create_all()
        logger.info("✅ Database tables initialized")
    
    # Set TARGET_WORDS in config (for routes to access)
    from backend.models.loader import TARGET_WORDS, ModelManager
    app.config['TARGET_WORDS'] = TARGET_WORDS

    # Load models
    app.model_manager = ModelManager()
    app.model_manager.load_all_models()
    
    logger.info("✅ All models loaded successfully")
    
    return app

def register_error_handlers(app):
    """Register global error handlers"""
    
    @app.errorhandler(400)
    def bad_request(error):
        return {
            'success': False,
            'error': 'Bad Request',
            'message': str(error),
            'status': 400
        }, 400
    
    @app.errorhandler(404)
    def not_found(error):
        return {
            'success': False,
            'error': 'Not Found',
            'message': 'The requested resource does not exist',
            'status': 404
        }, 404
    
    @app.errorhandler(500)
    def internal_error(error):
        app.logger.error(f"Internal Server Error: {str(error)}")
        return {
            'success': False,
            'error': 'Internal Server Error',
            'message': 'An unexpected error occurred',
            'status': 500
        }, 500
    
    @app.errorhandler(429)
    def ratelimit_handler(e):
        return {
            'success': False,
            'error': 'Rate Limit Exceeded',
            'message': 'Too many requests. Please try again later.',
            'status': 429
        }, 429

if __name__ == '__main__':
    app = create_app()
    debug_mode = os.getenv('FLASK_DEBUG', 'False').lower() in ('true', '1', 'yes')
    app.run(
        host=os.getenv('FLASK_HOST', '0.0.0.0'),
        port=int(os.getenv('FLASK_PORT', 5000)),
        debug=debug_mode
    )
