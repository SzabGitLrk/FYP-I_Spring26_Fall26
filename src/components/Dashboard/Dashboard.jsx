import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import ClaimsList from './ClaimsList';
import NewClaimForm from './NewClaimForm';
import AIReport from './AIReport';
import History from './History';
import './Dashboard.css';

const Dashboard = () => {
  const [activeSection, setActiveSection] = useState('claims');
  const [showNewClaim, setShowNewClaim] = useState(false);
  const navigate = useNavigate();

  const renderContent = () => {
    switch (activeSection) {
      case 'claims':
        return (
          <div className="claims-section">
            <div className="claims-header">
              <h1>Claims Management</h1>
              <button
                className="new-claim-btn"
                onClick={() => setShowNewClaim(true)}
              >
                New Claim
              </button>
            </div>

            <div className="claims-table">
              <div className="table-header">
                <div className="cell">Claim Number</div>
                <div className="cell">Customer Name</div>
                <div className="cell">Date</div>
                <div className="cell">Amount</div>
                <div className="cell">Status</div>
                <div className="cell">Actions</div>
                <div className="cell">AI Report</div>
              </div>

              <div className="table-body">
                <div className="no-claims">No claims found</div>
              </div>
            </div>
          </div>
        );
      case 'aiReport':
        return <AIReport />;
      case 'history':
        return <History />;
      default:
        return null;
    }
  };

  return (
    <div className="dashboard-container">
      <aside className="sidebar">
        <div className="logo">TPL Claims</div>
        <nav>
          <button
            className={activeSection === 'claims' ? 'active' : ''}
            onClick={() => setActiveSection('claims')}
          >
            Claims
          </button>
          <button
            className={activeSection === 'aiReport' ? 'active' : ''}
            onClick={() => setActiveSection('aiReport')}
          >
            AI Report
          </button>
          <button
            className={activeSection === 'history' ? 'active' : ''}
            onClick={() => setActiveSection('history')}
          >
            History
          </button>
          <button
            className="logout-btn"
            onClick={() => navigate('/login-selection')}
          >
            Logout
          </button>
        </nav>
      </aside>

      <main className="main-content">{renderContent()}</main>

      {showNewClaim && (
        <NewClaimForm onClose={() => setShowNewClaim(false)} />
      )}
    </div>
  );
};

export default Dashboard;