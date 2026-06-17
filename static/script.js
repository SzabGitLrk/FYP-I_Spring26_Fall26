document.addEventListener('DOMContentLoaded', () => {
    const uploadForm = document.getElementById('uploadForm');
    const imageInput = document.getElementById('imageInput');
    const preview = document.getElementById('imagePreview');
    const iconBox = document.getElementById('iconBox');
    const fileText = document.getElementById('fileText');

    // Preview handling
    imageInput.onchange = function() {
        const file = this.files[0];
        if (file) {
            fileText.innerText = file.name;
            iconBox.style.display = 'none';
            const reader = new FileReader();
            reader.onload = (e) => {
                preview.src = e.target.result;
                preview.style.display = 'block';
            }
            reader.readAsDataURL(file);
        }
    };

    // Form Submission
    uploadForm.onsubmit = async (e) => {
        e.preventDefault();
        const btn = document.getElementById('analyzeBtn');
        
        if (!imageInput.files[0]) {
            alert("Please select an image first!");
            return;
        }

        btn.innerText = "Analyzing...";
        btn.disabled = true;

        const formData = new FormData(uploadForm);

        try {
            // URL MUST match your app.py route (@app.route('/predict'))
            const response = await fetch('/predict', { 
                method: 'POST', 
                body: formData 
            });

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.output ? errorData.output[0] : "Server Error");
            }

            const data = await response.json();

            if (data.image) {
                // Hide Upload, Show Result
                document.getElementById('uploadSection').style.display = 'none';
                document.getElementById('resultSection').style.display = 'block';
                
                // Set Image and Results
                document.getElementById('labeledImage').src = "data:image/jpeg;base64," + data.image;
                
                const list = document.getElementById('predictionList');
                list.innerHTML = "";
                data.output.forEach(text => {
                    list.innerHTML += `<div style="background:#0f172a; padding:12px; border-radius:10px; margin-top:10px; border-left:4px solid #38bdf8; text-align:left; font-size:14px;">✅ ${text}</div>`;
                });
            } else {
                alert("Processing failed. Please try a clearer image.");
            }
        } catch (err) {
            console.error(err);
            alert("Error: " + err.message);
        } finally {
            btn.innerText = "Process Reading";
            btn.disabled = false;
        }
    };
});