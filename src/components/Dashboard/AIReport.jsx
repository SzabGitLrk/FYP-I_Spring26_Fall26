import React, { useState } from 'react';
import './AIReport.css';

const AIReport = () => {
  const [activeStep, setActiveStep] = useState(1);

  const StepIndicator = () => (
    <div className="steps-progress">
      <div className={`step ${activeStep >= 1 ? 'active' : ''}`}>
        <div className="step-circle">1</div>
        <p>Upload Images</p>
      </div>
      <div className="step-line"></div>
      <div className={`step ${activeStep >= 2 ? 'active' : ''}`}>
        <div className="step-circle">2</div>
        <p>Review Damage</p>
      </div>
      <div className="step-line"></div>
      <div className={`step ${activeStep >= 3 ? 'active' : ''}`}>
        <div className="step-circle">3</div>
        <p>Generate Report</p>
      </div>
    </div>
  );

  const UploadStep = () => {
    const fileInputRef = React.useRef(null);
    const [uploadedImages, setUploadedImages] = React.useState([]);

    const handleBrowseClick = () => {
      fileInputRef.current.click();
    };

    const handleFileChange = (event) => {
      const files = Array.from(event.target.files);
      files.forEach(file => {
        const reader = new FileReader();
        reader.onload = (e) => {
          setUploadedImages(prev => [...prev, {
            name: file.name,
            size: file.size,
            preview: e.target.result
          }]);
        };
        reader.readAsDataURL(file);
      });
    };

    const removeImage = (index) => {
      setUploadedImages(prev => prev.filter((_, i) => i !== index));
    };

    return (
      <div className="upload-step">
        <h2>Upload Vehicle Images</h2>
        <div className="upload-box">
          <div className="upload-icon">📤</div>
          <p>Drag and drop images or</p>
          <button className="browse-btn" onClick={handleBrowseClick}>
            browse
          </button>
          <input 
            ref={fileInputRef}
            type="file"
            accept="image/*"
            multiple
            onChange={handleFileChange}
            style={{ display: 'none' }}
          />
          <small>JPG, PNG up to 5MB</small>
        </div>

        {/* Image Preview Section */}
        {uploadedImages.length > 0 && (
          <div style={{ marginTop: '30px' }}>
            <h3 style={{ marginBottom: '15px' }}>Uploaded Images ({uploadedImages.length})</h3>
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))',
              gap: '15px'
            }}>
              {uploadedImages.map((image, index) => (
                <div key={index} style={{
                  position: 'relative',
                  borderRadius: '8px',
                  overflow: 'hidden',
                  border: '2px solid #ddd',
                  backgroundColor: '#f5f5f5'
                }}>
                  <img 
                    src={image.preview} 
                    alt={image.name}
                    style={{
                      width: '100%',
                      height: '150px',
                      objectFit: 'cover',
                      display: 'block'
                    }}
                  />
                  <div style={{
                    position: 'absolute',
                    top: '5px',
                    right: '5px',
                    background: 'rgba(0,0,0,0.7)',
                    color: 'white',
                    border: 'none',
                    borderRadius: '50%',
                    width: '30px',
                    height: '30px',
                    cursor: 'pointer',
                    fontSize: '18px',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}>
                    <button 
                      onClick={() => removeImage(index)}
                      style={{
                        background: 'none',
                        border: 'none',
                        color: 'white',
                        cursor: 'pointer',
                        fontSize: '18px',
                        padding: '0'
                      }}
                    >
                      ✕
                    </button>
                  </div>
                  <p style={{
                    fontSize: '11px',
                    padding: '5px',
                    margin: '0',
                    whiteSpace: 'nowrap',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    color: '#666'
                  }}>
                    {image.name}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="search-model">
          <input 
           
            placeholder="Search Car Model (e.g. Mehran, Prius, BMW...)" 
          />
        </div>
      </div>
    );
  };

  const ReviewStep = () => (
    <div className="review-step">
      <h2>Review Damage</h2>
      <p>Review the detected damage from the uploaded images.</p>
      
      <div className="ai-assessment">
        <h3>AI Assessment Summary</h3>
        <div className="assessment-table">
          <div className="table-header">
            <div>Car Model</div>
            <div>Damaged parts</div>
            <div>Severity</div>
            <div>Cost</div>
          </div>
          <div className="table-rows">
            {/* Empty rows with placeholder styling */}
            <div className="table-row">
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
            </div>
            <div className="table-row">
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
            </div>
            <div className="table-row">
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
              <div className="placeholder-cell"></div>
            </div>
          </div>
          <div className="table-footer">
            <div>Total estimated repair cost:</div>
            <div className="placeholder-total"></div>
          </div>
        </div>
      </div>
    </div>
  );

  const ReportStep = () => (
    <div className="report-step">
      <h2>Vehicle Damage Report</h2>
      <div className="report-content">
        <h3>Generate Report</h3>
        <p>Generate the final AI report for the damaged vehicle.</p>
      </div>
    </div>
  );

  return (
    <div className="ai-report">
      <div className="main-header">
        <h1 className="report-title">Generate AI Report</h1>
      </div>

      <StepIndicator />
      
      <div className="step-content">
        {activeStep === 1 && <UploadStep />}
        {activeStep === 2 && <ReviewStep />}
        {activeStep === 3 && <ReportStep />}
      </div>

      <div className="step-actions">
        {activeStep > 1 && (
          <button 
            className="back-btn"
            onClick={() => setActiveStep(curr => curr - 1)}
          >
            Back
          </button>
        )}
        {activeStep < 3 && (
          <button 
            className="next-btn"
            onClick={() => setActiveStep(curr => curr + 1)}
          >
            Next
          </button>
        )}
      </div>
    </div>
  );
};

export default AIReport;