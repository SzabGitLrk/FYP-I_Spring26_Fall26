import React from 'react';

export default function Contact() {
  return (
    <div className="container section">
      <h1 className="section-title">Contact</h1>
      <div className="card">
        <div className="form-row">
          <div className="form-field">
            <label>Name</label>
            <input placeholder="Your name" />
          </div>
          <div className="form-field">
            <label>Email</label>
            <input placeholder="you@example.com" />
          </div>
        </div>
        <div className="form-field">
          <label>Message</label>
          <input placeholder="How can we help?" />
        </div>
        <div className="form-actions">
          <button className="btn-primary">Send</button>
        </div>
      </div>
    </div>
  )
}






