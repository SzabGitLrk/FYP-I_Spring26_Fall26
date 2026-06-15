import React, { useState } from 'react';
import './NewClaimForm.css';

const NewClaimForm = ({ onClose }) => {
  const [step, setStep] = useState(1);
  const [uploadedFiles, setUploadedFiles] = useState({
    registration: null,
    drivingLicense: null,
    nic: null
  });
  const [formData, setFormData] = useState({
    vehicleDetails: {
      policyNo: '',
      vehicleMake: '',
      policyStartDate: '',
      claimCount: '',
      engine: '',
      policyEndDate: '',
      claimAmount: '',
      vehicleColor: '',
      vehicleStartDate: '',
      deductibleAmount: '',
      registrationNo: '',
      yearOfManufacture: '',
      vehicleEndDate: ''
    },
    claimForm: {
      claimType: '',
      branch: '',
      dateTime: '',
      incidentPlace: '',
      currentLocation: '',
      circumstances: '',
      missingParts: '',
      workshopType: '',
      vehicleType: '',
      dateField: '',
      workshopName: '',
      vehicleAvailability: ''
    },
    documents: {
      relationWithInsured: 'Self',
      name: '',
      contact: '',
      email: '',
      remarks: '',
      remarks2: '',
      dateTime: '',
      uploads: {
        registration: null,
        drivingLicense: null,
        nic: null
      }
    }
  });

  const handleInputChange = (field, value) => {
    setFormData(prev => ({
      ...prev,
      vehicleDetails: {
        ...prev.vehicleDetails,
        [field]: value
      }
    }));
  };

  const handleDocumentChange = (field, value) => {
    setFormData(prev => ({
      ...prev,
      documents: {
        ...prev.documents,
        [field]: value
      }
    }));
  };

  const handleFileUpload = (field, event) => {
    const file = event.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (e) => {
        setUploadedFiles(prev => ({
          ...prev,
          [field]: {
            name: file.name,
            size: file.size,
            type: file.type,
            preview: e.target.result
          }
        }));
      };
      reader.readAsDataURL(file);
    }
  };

  const removeFile = (field) => {
    setUploadedFiles(prev => ({
      ...prev,
      [field]: null
    }));
  };

  const renderStep = () => {
    switch(step) {
      case 1:
        return (
          <div className="vehicle-details">
            <h2>Vehicle Details</h2>
            <div className="form-grid">
              <div className="form-group">
                <label>Policy No</label>
                <input 
                  type="text" 
                  placeholder="e.g. POL/XX/XXXX"
                  value={formData.vehicleDetails.policyNo}
                  onChange={(e) => handleInputChange('policyNo', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Vehicle Make</label>
                <input 
                  type="text" 
                  placeholder="e.g. Suzuki"
                  value={formData.vehicleDetails.vehicleMake}
                  onChange={(e) => handleInputChange('vehicleMake', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Policy Start Date</label>
                <input 
                  type="date"
                  value={formData.vehicleDetails.policyStartDate}
                  onChange={(e) => handleInputChange('policyStartDate', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Claim Count</label>
                <input 
                  type="number"
                  placeholder="e.g. 2"
                  value={formData.vehicleDetails.claimCount}
                  onChange={(e) => handleInputChange('claimCount', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Engine</label>
                <input 
                  type="text"
                  placeholder="e.g. XXX/XX/XXXXXXX"
                  value={formData.vehicleDetails.engine}
                  onChange={(e) => handleInputChange('engine', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Policy End Date</label>
                <input 
                  type="date"
                  value={formData.vehicleDetails.policyEndDate}
                  onChange={(e) => handleInputChange('policyEndDate', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Claim Amount</label>
                <input 
                  type="number"
                  placeholder="e.g. 15000"
                  value={formData.vehicleDetails.claimAmount}
                  onChange={(e) => handleInputChange('claimAmount', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Vehicle Color</label>
                <input 
                  type="text"
                  placeholder="e.g. White"
                  value={formData.vehicleDetails.vehicleColor}
                  onChange={(e) => handleInputChange('vehicleColor', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Vehicle Start Date</label>
                <input 
                  type="date"
                  value={formData.vehicleDetails.vehicleStartDate}
                  onChange={(e) => handleInputChange('vehicleStartDate', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Deductible Amount</label>
                <input 
                  type="number"
                  placeholder="e.g. 5000"
                  value={formData.vehicleDetails.deductibleAmount}
                  onChange={(e) => handleInputChange('deductibleAmount', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Registration No</label>
                <input 
                  type="text"
                  placeholder="e.g. ABC-123"
                  value={formData.vehicleDetails.registrationNo}
                  onChange={(e) => handleInputChange('registrationNo', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Year of Manufacture</label>
                <input 
                  type="number"
                  placeholder="e.g. 2015"
                  value={formData.vehicleDetails.yearOfManufacture}
                  onChange={(e) => handleInputChange('yearOfManufacture', e.target.value)}
                />
              </div>
              <div className="form-group">
                <label>Vehicle End Date</label>
                <input 
                  type="date"
                  value={formData.vehicleDetails.vehicleEndDate}
                  onChange={(e) => handleInputChange('vehicleEndDate', e.target.value)}
                />
              </div>

            </div>
          </div>
        );
      
      case 2:
        return (
          <div className="claim-form">
            <h2>Claim Form</h2>
            <div className="form-grid">
              <div className="form-group">
                <label>Claim Type</label>
                <select>
                  <option value="">Select Claim Type</option>
                  <option value="accident">Accident</option>
                  <option value="theft">Theft</option>
                </select>
              </div>
              <div className="form-group">
                <label>Branch</label>
                <select>
                  <option value="">Select Branch</option>
                  <option value="karachi">Karachi Branch</option>
                  <option value="lahore">Lahore Branch</option>
                  <option value="islamabad">Islamabad Branch</option>
                  <option value="hyderabad">Hyderabad Branch</option>
                  <option value="multan">Multan Branch</option>
                  <option value="peshawar">Peshawar Branch</option>
                </select>
              </div>
              <div className="form-group">
                <label>Date & Time</label>
                <input type="datetime-local" />
              </div>
              <div className="form-group">
                <label>Incident Place</label>
                <input type="text" placeholder="Enter incident location" />
              </div>
              <div className="form-group full-width">
                <label>Current Location</label>
                <input type="text" placeholder="Current location" />
              </div>
              <div className="form-group full-width">
                <label>Circumstances of Claim/Loss</label>
                <textarea placeholder="Write your message..."></textarea>
              </div>
              <div className="form-group">
                <label>Missing Parts Details</label>
                <select>
                  <option value="">Select Model</option>
                  <option value="front-bumper">Front Bumper</option>
                  <option value="rear-bumper">Rear Bumper</option>
                  <option value="headlights">Headlights</option>
                  <option value="taillights">Taillights</option>
                  <option value="side-mirror">Side Mirror</option>
                  <option value="door-panel">Door Panel</option>
                  <option value="windshield">Windshield</option>
                  <option value="hood-bonnet">Hood/Bonnet</option>
                  <option value="trunk">Trunk</option>
                </select>
              </div>
              <div className="form-group">
                <label>Workshop Type</label>
                <select>
                  <option value="">Select Workshop</option>
                  <option value="authorized">Authorized Workshop</option>
                  <option value="partner">Partner Workshop</option>
                  <option value="local">Local Workshop</option>
                  <option value="in-house">In-House Workshop</option>
                </select>
              </div>
              <div className="form-group">
                <label>Vehicle Type</label>
                <select>
                  <option value="">Select Vehicle</option>
                  <option value="toyota-corolla">Toyota Corolla</option>
                  <option value="honda-civic">Honda Civic</option>
                  <option value="suzuki-alto">Suzuki Alto</option>
                  <option value="suzuki-cultus">Suzuki Cultus</option>
                  <option value="honda-city">Honda City</option>
                  <option value="toyota-yaris">Toyota Yaris</option>
                  <option value="kia-sportage">Kia Sportage</option>
                  <option value="hyundai-tucson">Hyundai Tucson</option>
                  <option value="mg-hs">MG HS</option>
                  <option value="daihatsu-mira">Daihatsu Mira</option>
                  <option value="nissan-dayz">Nissan Dayz</option>
                  <option value="toyota-vitz">Toyota Vitz</option>
                  <option value="honda-br-v">Honda BR-V</option>
                </select>
              </div>
              <div className="form-group">
                <label>Date Field</label>
                <input type="date" />
              </div>
              <div className="form-group">
                <label>Workshop Name</label>
                <input type="text" placeholder="Enter workshop name" />
              </div>
              <div className="form-group">
                <label>Vehicle Availability</label>
                <input type="text" placeholder="Enter availability" />
              </div>
            </div>
          </div>
        );
      
      case 3:
        return (
          <div className="documents">
            <h2>Required Documents & Customer Details</h2>
            <div className="form-grid">
              <div className="form-group">
                <label>Relation with Insured</label>
                <select
                  value={formData.documents.relationWithInsured}
                  onChange={(e) => handleDocumentChange('relationWithInsured', e.target.value)}
                >
        
                  <option value="Self">Self</option>
                  <option value="Other Family Member">Other Family Member</option>
                </select>
              </div>
              <div className="form-group">
                <label>Name</label>
                <input type="text" placeholder="Full name" />
              </div>
              <div className="form-group">
                <label>Contact</label>
                <input type="text" placeholder="Phone number" />
              </div>
              <div className="form-group">
                <label>Email</label>
                <input type="email" placeholder="Email address" />
              </div>
              <div className="form-group full-width">
                <label>Remarks</label>
                <input type="text" placeholder="n/a" />
              </div>
              <div className="form-group full-width">
                <label>Remarks 2 / Additional Info</label>
                <textarea placeholder="n/a"></textarea>
              </div>
              <div className="form-group">
                <label>Date/Time</label>
                <input type="datetime-local" />
              </div>
            </div>
            <div className="document-uploads">
              <div className="upload-box">
                <label>Registration Book Copy</label>
                <input 
                  type="file" 
                  accept="image/*,.pdf"
                  onChange={(e) => handleFileUpload('registration', e)}
                />
                {uploadedFiles.registration && (
                  <div style={{
                    marginTop: '10px',
                    padding: '10px',
                    backgroundColor: '#f0f0f0',
                    borderRadius: '5px',
                    position: 'relative'
                  }}>
                    {uploadedFiles.registration.type.startsWith('image') ? (
                      <img 
                        src={uploadedFiles.registration.preview} 
                        alt="Registration" 
                        style={{ width: '100%', maxHeight: '120px', objectFit: 'cover', borderRadius: '4px' }}
                      />
                    ) : (
                      <div style={{ padding: '10px', textAlign: 'center', color: '#666' }}>
                        📄 PDF File
                      </div>
                    )}
                    <p style={{ margin: '8px 0 0 0', fontSize: '12px', wordBreak: 'break-all' }}>
                      {uploadedFiles.registration.name}
                    </p>
                    <button
                      onClick={() => removeFile('registration')}
                      style={{
                        position: 'absolute',
                        top: '5px',
                        right: '5px',
                        background: 'rgba(0,0,0,0.7)',
                        color: 'white',
                        border: 'none',
                        borderRadius: '50%',
                        width: '25px',
                        height: '25px',
                        cursor: 'pointer',
                        fontSize: '16px'
                      }}
                    >
                      ✕
                    </button>
                  </div>
                )}
              </div>

              <div className="upload-box">
                <label>Driving License</label>
                <input 
                  type="file" 
                  accept="image/*,.pdf"
                  onChange={(e) => handleFileUpload('drivingLicense', e)}
                />
                {uploadedFiles.drivingLicense && (
                  <div style={{
                    marginTop: '10px',
                    padding: '10px',
                    backgroundColor: '#f0f0f0',
                    borderRadius: '5px',
                    position: 'relative'
                  }}>
                    {uploadedFiles.drivingLicense.type.startsWith('image') ? (
                      <img 
                        src={uploadedFiles.drivingLicense.preview} 
                        alt="Driving License" 
                        style={{ width: '100%', maxHeight: '120px', objectFit: 'cover', borderRadius: '4px' }}
                      />
                    ) : (
                      <div style={{ padding: '10px', textAlign: 'center', color: '#666' }}>
                        📄 PDF File
                      </div>
                    )}
                    <p style={{ margin: '8px 0 0 0', fontSize: '12px', wordBreak: 'break-all' }}>
                      {uploadedFiles.drivingLicense.name}
                    </p>
                    <button
                      onClick={() => removeFile('drivingLicense')}
                      style={{
                        position: 'absolute',
                        top: '5px',
                        right: '5px',
                        background: 'rgba(0,0,0,0.7)',
                        color: 'white',
                        border: 'none',
                        borderRadius: '50%',
                        width: '25px',
                        height: '25px',
                        cursor: 'pointer',
                        fontSize: '16px'
                      }}
                    >
                      ✕
                    </button>
                  </div>
                )}
              </div>

              <div className="upload-box">
                <label>Upload NIC</label>
                <input 
                  type="file" 
                  accept="image/*,.pdf"
                  onChange={(e) => handleFileUpload('nic', e)}
                />
                {uploadedFiles.nic && (
                  <div style={{
                    marginTop: '10px',
                    padding: '10px',
                    backgroundColor: '#f0f0f0',
                    borderRadius: '5px',
                    position: 'relative'
                  }}>
                    {uploadedFiles.nic.type.startsWith('image') ? (
                      <img 
                        src={uploadedFiles.nic.preview} 
                        alt="NIC" 
                        style={{ width: '100%', maxHeight: '120px', objectFit: 'cover', borderRadius: '4px' }}
                      />
                    ) : (
                      <div style={{ padding: '10px', textAlign: 'center', color: '#666' }}>
                        📄 PDF File
                      </div>
                    )}
                    <p style={{ margin: '8px 0 0 0', fontSize: '12px', wordBreak: 'break-all' }}>
                      {uploadedFiles.nic.name}
                    </p>
                    <button
                      onClick={() => removeFile('nic')}
                      style={{
                        position: 'absolute',
                        top: '5px',
                        right: '5px',
                        background: 'rgba(0,0,0,0.7)',
                        color: 'white',
                        border: 'none',
                        borderRadius: '50%',
                        width: '25px',
                        height: '25px',
                        cursor: 'pointer',
                        fontSize: '16px'
                      }}
                    >
                      ✕
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        );
      default:
        return null;
    }
  };

  const handleClose = () => {
    onClose();
  };

  return (
    <div className="new-claim-modal" onClick={(e) => {
      if (e.target === e.currentTarget) handleClose();
    }}>
      <div className="modal-content">
        <button className="close-btn" onClick={handleClose}>&times;</button>
        
        <div className="steps-indicator">
          <div className={`step ${step >= 1 ? 'active' : ''}`}>
            <span>1</span>
            <p>Vehicle Details</p>
          </div>
          <div className={`step ${step >= 2 ? 'active' : ''}`}>
            <span>2</span>
            <p>Claim Form</p>
          </div>
          <div className={`step ${step >= 3 ? 'active' : ''}`}>
            <span>3</span>
            <p>Documents & Contact</p>
          </div>
        </div>

        <form onSubmit={(e) => e.preventDefault()}>
          {renderStep()}
          
          <div className="form-actions">
            {step > 1 && (
              <button type="button" className="back-btn" onClick={() => setStep(step - 1)}>
                Back
              </button>
            )}
            {step < 3 ? (
              <button type="button" className="next-btn" onClick={() => setStep(step + 1)}>
                Next
              </button>
            ) : (
              <button type="submit" className="submit-btn">
                Submit
              </button>
            )}
          </div>
        </form>
      </div>
    </div>
  );
};

export default NewClaimForm;