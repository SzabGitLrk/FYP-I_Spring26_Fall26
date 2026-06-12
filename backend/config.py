# Configuration Management

import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    """Base configuration"""
    DEBUG = False
    TESTING = False
    
    # Flask
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')
    JSONIFY_PRETTYPRINT_REGULAR = True
    
    # Database
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL', 'sqlite:///dual_sense_ai.db')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ECHO = False
    
    # Logging
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    LOG_FILE = os.getenv('LOG_FILE', 'logs/dual_sense_ai.log')
    LOG_MAX_BYTES = int(os.getenv('LOG_MAX_BYTES', 10485760))
    LOG_BACKUP_COUNT = int(os.getenv('LOG_BACKUP_COUNT', 5))
    
    # Model Configuration
    SIGN_MODEL_PATH = os.getenv('SIGN_MODEL_PATH', 'fyp_30_word_kaggle_model.keras')
    ALPHABET_MODEL_PATH = os.getenv('ALPHABET_MODEL_PATH', 'fyp_env/alphabet_classifier.pkl')

    # Target words for sign recognition (30 classes)
    TARGET_WORDS = [
        'sick', 'owie', 'bad', 'better', 'sleep', 'awake',
        'food', 'drink', 'hungry', 'bath', 'bed', 'room',
        'callonphone', 'wait', 'stay', 'go', 'find', 'have',
        'please', 'thankyou', 'yes', 'no', 'listen', 'look',
        'hear', 'time', 'night', 'yesterday', 'person', 'brother'
    ]
    
    # Performance
    CONFIDENCE_THRESHOLD = float(os.getenv('CONFIDENCE_THRESHOLD', 0.75))
    PREDICTION_FRAMES = int(os.getenv('PREDICTION_FRAMES', 60))
    MAX_QUEUE_SIZE = int(os.getenv('MAX_QUEUE_SIZE', 100))
    
    # MediaPipe Configuration
    MEDIAPIPE_MIN_DETECTION_CONFIDENCE = float(os.getenv('MEDIAPIPE_MIN_DETECTION_CONFIDENCE', 0.5))
    MEDIAPIPE_MIN_TRACKING_CONFIDENCE = float(os.getenv('MEDIAPIPE_MIN_TRACKING_CONFIDENCE', 0.5))
    
    # Azure Services
    AZURE_SPEECH_KEY = os.getenv('AZURE_SPEECH_KEY')
    AZURE_SPEECH_REGION = os.getenv('AZURE_SPEECH_REGION', 'eastus')
    
    # Redis Cache
    REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
    REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
    REDIS_DB = int(os.getenv('REDIS_DB', 0))
    REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', '')
    
    # Rate Limiting
    RATELIMIT_STORAGE_URL = os.getenv('RATELIMIT_STORAGE_URL', 'memory://')
    RATELIMIT_DEFAULT = os.getenv('RATELIMIT_DEFAULT', '200/day,50/hour')
    
    # CORS
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', 'http://localhost:3000,http://localhost:8000').split(',')
    
    # Security
    ENABLE_HTTPS = os.getenv('ENABLE_HTTPS', 'False').lower() == 'true'
    SSL_CERT_PATH = os.getenv('SSL_CERT_PATH')
    SSL_KEY_PATH = os.getenv('SSL_KEY_PATH')

class DevelopmentConfig(Config):
    """Development configuration"""
    DEBUG = True
    SQLALCHEMY_ECHO = True
    LOG_LEVEL = 'DEBUG'

class TestingConfig(Config):
    """Testing configuration"""
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    LOG_LEVEL = 'DEBUG'

class ProductionConfig(Config):
    """Production configuration"""
    DEBUG = False
    TESTING = False
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'WARNING')
    
    # Enforce HTTPS in production
    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    PERMANENT_SESSION_LIFETIME = 3600  # 1 hour
