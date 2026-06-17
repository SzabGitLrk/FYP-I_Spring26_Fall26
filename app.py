import os
import io
import base64
import torch
import torchvision
from flask import Flask, render_template, request, jsonify, session, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from PIL import Image, ImageDraw
from torchvision import transforms as T
from torchvision.models.detection.faster_rcnn import FastRCNNPredictor

app = Flask(__name__)
app.config['SECRET_KEY'] = 'my_secret_key_123'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///database.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Device Configuration
device = torch.device('cpu')

# ==========================================
# 1. DATABASE MODEL
# ==========================================
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)

# ==========================================
# 2. MODEL LOADING FUNCTION
# ==========================================
def load_detection_model():
    model = torchvision.models.detection.fasterrcnn_resnet50_fpn(weights=None)
    num_classes = 3 
    in_features = model.roi_heads.box_predictor.cls_score.in_features
    model.roi_heads.box_predictor = FastRCNNPredictor(in_features, num_classes)
    
    model_path = "final_model.pth"
    if os.path.exists(model_path):
        try:
            checkpoint = torch.load(model_path, map_location=device, weights_only=False)
            if isinstance(checkpoint, dict) and 'model' in checkpoint:
                model.load_state_dict(checkpoint['model'])
            else:
                model.load_state_dict(checkpoint)
            print("✅ SUCCESS: Model loaded perfectly!")
        except Exception as e:
            print(f"❌ Error loading weights: {e}")
    else:
        print(f"❌ Error: {model_path} file nahi mili!")
    
    model.to(device)
    model.eval()
    return model

detection_model = load_detection_model()

# ==========================================
# 3. ROUTES
# ==========================================

@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        uname = request.form.get('username')
        pwd = request.form.get('password')
        
        if User.query.filter_by(username=uname).first():
            flash('Username already exists!')
            return redirect(url_for('signup'))
            
        new_user = User(username=uname, password=generate_password_hash(pwd))
        db.session.add(new_user)
        db.session.commit()
        return redirect(url_for('login'))
    return render_template('signup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':

        user = User.query.filter_by(
            username=request.form.get('username')
        ).first()

        if user:

            if check_password_hash(
                user.password,
                request.form.get('password')
            ):

                session['user_id'] = user.id
                session['username'] = user.username

                return redirect(url_for('dashboard'))

            else:
                flash('Incorrect Password!')
                return redirect(url_for('login'))

        else:
            flash('Username does not exist!')
            return redirect(url_for('login'))

    return render_template('login.html')

@app.route('/dashboard')
def dashboard():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    return render_template('dashboard.html')

@app.route('/predict', methods=['POST'])
def predict():
    if 'image' not in request.files:
        return jsonify({'output': ['No image uploaded']})

    file = request.files['image']

    if file.filename == '':
        return jsonify({'output': ['No file selected']})

    try:
        img = Image.open(file.stream).convert("RGB")
        draw = ImageDraw.Draw(img)

        transform = T.Compose([T.ToTensor()])
        img_tensor = transform(img).unsqueeze(0).to(device)

        with torch.no_grad():
            prediction = detection_model(img_tensor)

        labels = prediction[0]['labels'].cpu().tolist()
        scores = prediction[0]['scores'].cpu().tolist()
        boxes = prediction[0]['boxes'].cpu().tolist()

        results = []
        found = False

        for box, label, score in zip(boxes, labels, scores):

            if score >= 0.5 and label == 1:

                found = True

                draw.rectangle(
                    [(box[0], box[1]), (box[2], box[3])],
                    outline="red",
                    width=5
                )

                results.append("Meter Reading Detected")

        buffered = io.BytesIO()
        img.save(buffered, format="JPEG")
        img_str = base64.b64encode(buffered.getvalue()).decode()

        return jsonify({
            'output': results if found else ["No Meter Reading Detected"],
            'image': img_str if found else None
        })

    except Exception as e:
        return jsonify({
            'output': [f"Error: {str(e)}"]
        })
@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(debug=True)