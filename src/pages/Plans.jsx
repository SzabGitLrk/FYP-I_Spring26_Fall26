import React from 'react';

export default function Plans() {
  return (
    <div className="container section">
      <h1 className="section-title">Plans</h1>
      <p className="muted">Compare our car insurance plans and pick what suits you.</p>
      <div className="cards">
        {["Third-Party", "Comprehensive", "Premium"].map((name) => (
          <div className="card" key={name}>
            <h3 style={{ marginTop: 0 }}>{name}</h3>
            <p className="muted">Great coverage with transparent pricing.</p>
            <ul>
              <li>Accident coverage</li>
              <li>Roadside assistance</li>
              <li>Cashless repair network</li>
            </ul>
            <button className="btn-primary">Choose {name}</button>
          </div>
        ))}
      </div>
    </div>
  )
}



