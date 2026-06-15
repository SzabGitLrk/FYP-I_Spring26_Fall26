import React from "react";
import { useNavigate } from "react-router-dom";
import "./AdminDashboard.css";

export default function AdminDashboard() {
  const navigate = useNavigate();

  return (
    <div className="admin-container">
      {/* Header */}
      <div className="admin-header">
        <div>
          <h1>Admin Dashboard</h1>
          <p>Review and manage all insurance claims</p>
        </div>
        <div className="admin-profile">
          <div className="profile-info">
            <span className="user-name">Admin User</span>
            <span className="user-role">Administrator</span>
          </div>
          <button
            onClick={() => navigate("/login-selection")}
            className="logout-btn"
          >
            Logout
          </button>
        </div>
      </div>

      {/* Statistics Container */}
      <div className="stats-container">
        {/* Total Claims Card */}
        <div className="stat-card">
          <div className="stat-info">
            <h3>Total Claims</h3>
            <span className="stat-number">0</span>
          </div>
          <div className="stat-icon total">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M14 2H6a2 2 0 0 0-2 2v16c0 1.1.9 2 2 2h12a2 2 0 0 0 2-2V8l-6-6z" />
            </svg>
          </div>
        </div>

        {/* Pending Review Card */}
        <div className="stat-card">
          <div className="stat-info">
            <h3>Pending Review</h3>
            <span className="stat-number">0</span>
          </div>
          <div className="stat-icon pending">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm0 18c-4.4 0-8-3.6-8-8s3.6-8 8-8 8 3.6 8 8-3.6 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z" />
            </svg>
          </div>
        </div>

        {/* Approved Claims Card */}
        <div className="stat-card">
          <div className="stat-info">
            <h3>Approved</h3>
            <span className="stat-number">0</span>
          </div>
          <div className="stat-icon approved">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z" />
            </svg>
          </div>
        </div>

        {/* Rejected Claims Card */}
        <div className="stat-card">
          <div className="stat-info">
            <h3>Rejected Claims</h3>
            <span className="stat-number">0</span>
          </div>
          <div className="stat-icon rejected">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12 19 6.41z" />
            </svg>
          </div>
        </div>
      </div>

      {/* Claims Management Section */}
      <div className="claims-section">
        <div className="claims-header">
          <div>
            <h2>Claims Management</h2>
            <p>Review and approve submitted claims</p>
          </div>
          <div className="claims-actions">
            <div className="search-box">
              <input type="text" placeholder="Search claims..." />
            </div>
            <select className="status-filter">
              <option value="allclaims">All claims</option>
              <option value="rejected">Rejected</option>
              <option value="approved">Approved</option>
              <option value="pending">Pending</option>
            </select>
          </div>
        </div>

        <div className="claims-content">
          <div className="no-claims">
            <div className="no-claims-icon">
              <svg viewBox="0 0 24 24" fill="currentColor">
                <path d="M14 2H6a2 2 0 0 0-2 2v16c0 1.1.9 2 2 2h12a2 2 0 0 0 2-2V8l-6-6zM6 20V4h7v5h5v11H6z"/>
              </svg>
            </div>
            <h3>No Claims Found</h3>
            <p>No claims match your search criteria</p>
          </div>
        </div>
      </div>
    </div>
  );
}
