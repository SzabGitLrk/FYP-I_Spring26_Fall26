# Model Manager - Loads and manages ML models

import os
import logging
import numpy as np

os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'

logger = logging.getLogger(__name__)

# The 30-word vocabulary the sign model was trained on
TARGET_WORDS = [
    'sick', 'owie', 'bad', 'better', 'sleep', 'awake',
    'food', 'drink', 'hungry', 'bath', 'bed', 'room',
    'callonphone', 'wait', 'stay', 'go', 'find', 'have',
    'please', 'thankyou', 'yes', 'no', 'listen', 'look',
    'hear', 'time', 'night', 'yesterday', 'person', 'brother'
]


class ModelManager:
    """Manages loading and access to ML models"""

    def __init__(self):
        self.sign_model = None
        self.alphabet_model = None
        self.sign_model_loaded = False
        self.alphabet_model_loaded = False

    def load_all_models(self):
        """Load all models configured in environment"""
        self.load_sign_model()
        self.load_alphabet_model()

    def load_sign_model(self):
        """Load the LSTM sign language model"""
        model_path = os.getenv('SIGN_MODEL_PATH', 'fyp_30_word_kaggle_model.keras')
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

        # Try multiple possible locations
        possible_paths = [
            model_path,
            os.path.join(project_root, model_path),
            os.path.join(os.getcwd(), model_path),
            os.path.join(os.path.dirname(__file__), '..', '..', 'fyp_env', model_path),
        ]

        for path in possible_paths:
            path = os.path.normpath(path)
            if os.path.exists(path):
                try:
                    import tensorflow as tf
                    tf.get_logger().setLevel(logging.ERROR)
                    try:
                        import absl.logging
                        absl.logging.set_verbosity('error')
                    except ImportError:
                        pass
                    from keras.models import Sequential
                    from keras.layers import LSTM, Dense, Dropout, Masking, BatchNormalization, Input

                    logger.info(f"Loading sign model from: {path}")

                    # Build architecture first (avoids Keras version compatibility issues)
                    model = Sequential([Input(shape=(60, 258))])
                    model.add(Masking(mask_value=0.0))
                    model.add(LSTM(128, return_sequences=True, activation='tanh'))
                    model.add(BatchNormalization())
                    model.add(Dropout(0.3))
                    model.add(LSTM(256, return_sequences=True, activation='tanh'))
                    model.add(BatchNormalization())
                    model.add(Dropout(0.3))
                    model.add(LSTM(128, return_sequences=False, activation='tanh'))
                    model.add(BatchNormalization())
                    model.add(Dropout(0.3))
                    model.add(Dense(128, activation='relu'))
                    model.add(Dense(len(TARGET_WORDS), activation='softmax'))

                    # Load trained weights
                    model.load_weights(path)

                    self.sign_model = model
                    self.sign_model_loaded = True
                    logger.info(f"Sign model loaded: {len(TARGET_WORDS)} classes, input (60, 258)")
                    return
                except Exception as e:
                    logger.error(f"Failed to load sign model from {path}: {e}")
                    continue

        logger.warning(f"Sign model not found at any expected path. Tried: {possible_paths}")

    def load_alphabet_model(self):
        """Load the Random Forest alphabet classifier"""
        model_path = os.getenv('ALPHABET_MODEL_PATH', 'fyp_env/alphabet_classifier.pkl')
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

        possible_paths = [
            model_path,
            os.path.join(project_root, model_path),
            os.path.join(os.getcwd(), model_path),
            os.path.join(os.path.dirname(__file__), '..', '..', model_path),
        ]

        for path in possible_paths:
            path = os.path.normpath(path)
            if os.path.exists(path):
                try:
                    import joblib
                    logger.info(f"Loading alphabet model from: {path}")
                    self.alphabet_model = joblib.load(path)
                    self.alphabet_model_loaded = True
                    logger.info(f"Alphabet model loaded: {len(self.alphabet_model.classes_)} classes")
                    return
                except Exception as e:
                    logger.error(f"Failed to load alphabet model from {path}: {e}")
                    continue

        logger.warning(f"Alphabet model not found at any expected path. Tried: {possible_paths}")
