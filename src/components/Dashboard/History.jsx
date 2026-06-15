import React from 'react';
import './History.css';

const History = () => {
  return (
    <div className="history-container">
      <div className="history-header">
        <h1>Damage Report History</h1>
        <div className="search-box">
          <input 
            type="text" 
            placeholder="Search by car model..."
          />
        </div>
      </div>

      <div className="history-table">
        <div className="table-header">
          <div className="header-cell">Damage</div>
          <div className="header-cell">Severity</div>
          <div className="header-cell">Date</div>
          <div className="header-cell">Car Model</div>
          <div className="header-cell">Estimated Cost (PKR)</div>
        </div>
        
        <div className="no-history">
          No damage reports found
        </div>
      </div>
    </div>
  );
};

export default History;