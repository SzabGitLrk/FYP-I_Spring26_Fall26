import React from 'react';

export default function Quote() {
  return (
    <div className="container section">
      <h1 className="section-title">Get a Quote</h1>
      <div className="card">
        <div className="form-row">
          <div className="form-field">
            <label>Full Name</label>
            <input placeholder="John Doe" />
          </div>
          <div className="form-field">
            <label>Email</label>
            <input placeholder="john@example.com" />
          </div>
        </div>
        <div className="form-row">
          <div className="form-field">
            <label>Vehicle Make</label>
            <input placeholder="Toyota" />
          </div>
          <div className="form-field">
            <label>Model</label>
            <input placeholder="Corolla" />
          </div>
        </div>
        <div className="form-row">
          <div className="form-field">
            <label>Model Year</label>
            <input placeholder="2022" />
          </div>
          <div className="form-field">
            <label>City</label>
            <input placeholder="Karachi" />
          </div>
        </div>
        <div className="form-actions">
          <button className="btn-primary">Calculate</button>
        </div>
      </div>
    </div>
  )
}



