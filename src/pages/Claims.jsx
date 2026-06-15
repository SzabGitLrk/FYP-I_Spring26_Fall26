import React from 'react';

export default function Claims() {
  return (
    <div className="container section">
      <h1 className="section-title">Claims</h1>
      <div className="card">
        <p className="muted">Submit your claim with details and we'll reach out shortly.</p>
        <div className="form-row">
          <div className="form-field">
            <label>Policy Number</label>
            <input placeholder="AS-123456" />
          </div>
          <div className="form-field">
            <label>Phone</label>
            <input placeholder="0300-1234567" />
          </div>
        </div>
        <div className="form-field">
          <label>Incident Description</label>
          <input placeholder="Describe what happened..." />
        </div>
        <div className="form-actions">
          <button className="btn-primary">Submit Claim</button>
        </div>
      </div>
    </div>
  )
}



