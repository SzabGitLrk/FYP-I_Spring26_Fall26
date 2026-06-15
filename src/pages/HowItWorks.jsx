import React from 'react';

export default function HowItWorks() {
  return (
    <section className="how-it-works">
      <div className="hiw-container">
        <div className="hiw-intro">
          <h1 className="section-title">How It Works</h1>
          <p className="muted" style={{ marginBottom: 32 }}>
            IntelliClaim simplifies the claims process with just a few steps.
          </p>
        </div>

        <ol className="steps-list hiw-steps">
          <li>
            <span className="step-badge">1</span>
            <div>
              <strong>Upload Vehicle Photos</strong>
              <p className="muted">
                Snap and send photos directly from the CRM interface or upload
                existing images of the damaged vehicle.
              </p>
            </div>
          </li>
          <li>
            <span className="step-badge">2</span>
            <div>
              <strong>Let AI Analyze</strong>
              <p className="muted">
                Our advanced AI detects damage, assesses severity, and estimates
                repair costs instantly with high accuracy.
              </p>
            </div>
          </li>
          <li>
            <span className="step-badge">3</span>
            <div>
              <strong>Submit & Track</strong>
              <p className="muted">
                Approvals and claim progress are updated in real time, allowing
                you to track the entire process effortlessly.
              </p>
            </div>
          </li>
        </ol>
      </div>
    </section>
  );
}
