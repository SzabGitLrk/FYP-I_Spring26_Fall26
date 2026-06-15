import React from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export const ProtectedRoute = ({ children }) => {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        height: "100vh",
        background: "#f7f7f7"
      }}>
        <div style={{ textAlign: "center" }}>
          <div style={{
            fontSize: "2rem",
            marginBottom: "16px"
          }}>⏳</div>
          <p style={{ fontSize: "1.1rem", color: "#666" }}>Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/user-login" replace />;
  }

  return children;
};
