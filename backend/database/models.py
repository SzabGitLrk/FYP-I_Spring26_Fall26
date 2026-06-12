# Database Models - SQLAlchemy ORM

from backend.app import db
from datetime import datetime
import uuid

class Session(db.Model):
    """User session for tracking interactions"""
    __tablename__ = 'sessions'
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_activity = db.Column(db.DateTime, default=datetime.utcnow)
    status = db.Column(db.String(20), default='active')  # active, inactive, closed
    session_metadata = db.Column(db.JSON)
    
    # Relationships
    predictions = db.relationship('Prediction', backref='session', lazy=True, cascade='all, delete-orphan')
    
    def __repr__(self):
        return f'<Session {self.id}>'

class Prediction(db.Model):
    """Store all predictions for analytics"""
    __tablename__ = 'predictions'
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = db.Column(db.String(36), db.ForeignKey('sessions.id'), nullable=False)
    
    # Input details
    input_type = db.Column(db.String(20), nullable=False)  # 'video', 'text', 'speech'
    
    # Prediction details
    prediction = db.Column(db.String(100), nullable=False)
    confidence = db.Column(db.Float, nullable=False)
    
    # Alternative predictions (for debugging)
    alternatives = db.Column(db.JSON)  # List of alternative predictions with confidence
    
    # Performance metrics
    latency_ms = db.Column(db.Float)  # Inference time in milliseconds
    preprocessing_ms = db.Column(db.Float)  # Time to prepare input
    
    # Model info
    model_used = db.Column(db.String(50))  # 'lstm', 'ensemble', etc.
    model_version = db.Column(db.String(20))  # Model version number
    
    # Timestamp
    timestamp = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    
    def __repr__(self):
        return f'<Prediction {self.prediction}@{self.confidence:.2f}>'

class UserFeedback(db.Model):
    """Collect user feedback for model improvement"""
    __tablename__ = 'user_feedback'
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = db.Column(db.String(36), db.ForeignKey('sessions.id'), nullable=False)
    prediction_id = db.Column(db.String(36), db.ForeignKey('predictions.id'))
    
    # Feedback
    correct = db.Column(db.Boolean)  # Was prediction correct?
    actual_value = db.Column(db.String(100))  # What should it have been?
    
    # Comments
    comments = db.Column(db.Text)
    rating = db.Column(db.Integer)  # 1-5 star rating
    
    # Timestamp
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<Feedback {self.id}>'

class PerformanceMetric(db.Model):
    """Track system performance over time"""
    __tablename__ = 'performance_metrics'
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    
    # Metric type
    metric_type = db.Column(db.String(50), nullable=False)  # 'latency', 'accuracy', 'throughput', etc.
    metric_name = db.Column(db.String(100), nullable=False)
    
    # Values
    value = db.Column(db.Float, nullable=False)
    unit = db.Column(db.String(20))  # 'ms', '%', 'req/s', etc.
    
    # Context
    model = db.Column(db.String(50))
    component = db.Column(db.String(50))
    
    # Timestamp
    timestamp = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    
    def __repr__(self):
        return f'<Metric {self.metric_name}={self.value}{self.unit}>'

class ErrorLog(db.Model):
    """Log application errors for debugging"""
    __tablename__ = 'error_logs'
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = db.Column(db.String(36), db.ForeignKey('sessions.id'))
    
    # Error details
    error_type = db.Column(db.String(100), nullable=False)
    error_message = db.Column(db.Text, nullable=False)
    stack_trace = db.Column(db.Text)
    
    # Context
    endpoint = db.Column(db.String(100))
    model = db.Column(db.String(50))
    
    # Timestamp
    timestamp = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    
    def __repr__(self):
        return f'<Error {self.error_type}>'

