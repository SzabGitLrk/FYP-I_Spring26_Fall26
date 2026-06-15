import React, { useState } from 'react';
import './ClaimsList.css';

const ClaimsList = () => {
  const [claims] = useState([]);

  return (
    <div className="claims-list">
      <div className="claims-table">
        <div className="table-header">
          <div>Claim Number</div>
          <div>Customer Name</div>
          <div>Date</div>
          <div>Amount</div>
          <div>Status</div>
          <div>Actions</div>
          <div>AI Report</div>
        </div>
        
        {claims.length === 0 ? (
          <div className="no-claims">
            No claims found
          </div>
        ) : (
          <div className="table-body">
            {claims.map(claim => (
              <div key={claim.id} className="table-row">
                <div>{claim.number}</div>
                <div>{claim.customerName}</div>
                <div>{claim.date}</div>
                <div>Rs. {claim.amount}</div>
                <div className={`status ${claim.status.toLowerCase()}`}>
                  {claim.status}
                </div>
                <div>
                  <button className="view-btn">View</button>
                </div>
                <div>
                  <button className="ai-report-btn">AI Report</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default ClaimsList;