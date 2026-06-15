import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import "./AdminLogin.css";

export default function AdminLogin() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const navigate = useNavigate();

  const handleSubmit = (e) => {
    e.preventDefault();
    setError("");

    const ADMIN_EMAIL = "Admin@gmail.com";
    const ADMIN_PASSWORD = "Hanish@12";

    if (!email || !password) {
      setError("Please enter both email and password");
      return;
    }

    // Check admin credentials
    if (email === ADMIN_EMAIL && password === ADMIN_PASSWORD) {
      navigate("/admin-dashboard");
    } else if (email !== ADMIN_EMAIL) {
      setError("Invalid admin email");
    } else {
      setError("Invalid admin password");
    }
  };

  return (
    <div style={{
      display: "flex",
      width: "100vw",
      height: "100vh",
      minHeight: "100vh",
      margin: 0,
      padding: 0,
      overflow: "hidden"
    }}>
      {/* Left Admin Illustration */}
      <div style={{
        flex: 1,
        background: "linear-gradient(135deg, #667eea 0%, #764ba2 25%, #f093fb 50%, #f5576c 75%, #4facfe 100%)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minWidth: 0,
        height: "100vh",
        position: "relative",
        overflow: "hidden"
      }}>

        {/* Background Images */}
        <div style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundImage: `
            url('https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=400&h=300&fit=crop&crop=center'),
            url('https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=400&h=300&fit=crop&crop=center'),
            url('https://images.unsplash.com/photo-1552664730-d307ca884978?w=400&h=300&fit=crop&crop=center')
          `,
          backgroundSize: "200px 150px, 180px 135px, 160px 120px",
          backgroundPosition: "20% 20%, 80% 70%, 60% 40%",
          backgroundRepeat: "no-repeat",
          opacity: 0.1,
          animation: "floatImages 25s ease-in-out infinite"
        }}></div>

        {/* Floating Elements */}
        <div style={{
          position: "absolute",
          top: "15%",
          left: "10%",
          width: "60px",
          height: "60px",
          background: "rgba(255,255,255,0.1)",
          borderRadius: "50%",
          backdropFilter: "blur(10px)",
          animation: "float1 6s ease-in-out infinite"
        }}></div>

        <div style={{
          position: "absolute",
          top: "60%",
          right: "15%",
          width: "40px",
          height: "40px",
          background: "rgba(255,255,255,0.15)",
          borderRadius: "20px",
          backdropFilter: "blur(10px)",
          animation: "float2 8s ease-in-out infinite reverse"
        }}></div>

        <div style={{
          position: "absolute",
          bottom: "20%",
          left: "20%",
          width: "50px",
          height: "50px",
          background: "rgba(255,255,255,0.08)",
          borderRadius: "25px",
          backdropFilter: "blur(10px)",
          animation: "float3 7s ease-in-out infinite"
        }}></div>

        <div style={{
          position: "absolute",
          top: "40%",
          right: "25%",
          width: "35px",
          height: "35px",
          background: "rgba(255,255,255,0.12)",
          borderRadius: "50%",
          backdropFilter: "blur(10px)",
          animation: "float4 9s ease-in-out infinite reverse"
        }}></div>

        <div style={{
          textAlign: "center",
          zIndex: 3,
          position: "relative",
          animation: "fadeInUp 1.2s ease-out"
        }}>
          <div style={{
            background: "rgba(255,255,255,0.25)",
            backdropFilter: "blur(20px)",
            borderRadius: "25px",
            padding: "50px",
            boxShadow: "0 12px 40px rgba(0,0,0,0.15), inset 0 1px 0 rgba(255,255,255,0.2)",
            border: "1px solid rgba(255,255,255,0.4)",
            position: "relative",
            overflow: "hidden"
          }}>

            <h1 style={{
              color: "#fff",
              fontWeight: 900,
              fontSize: "3.5rem",
              marginBottom: 40,
              letterSpacing: "-0.03em"
            }}>
              Admin Portal
            </h1>

            {/* Enhanced Admin SVG Illustration */}
            <svg width="320" height="180" viewBox="0 0 320 180" fill="none" xmlns="http://www.w3.org/2000/svg" style={{ marginBottom: "25px" }}>
              <defs>
                <filter id="adminShadow">
                  <feDropShadow dx="1" dy="1" stdDeviation="0.5" flood-color="#667eea" flood-opacity="0.8"/>
                </filter>
              </defs>

              {/* Background Elements */}
              <circle cx="80" cy="45" r="30" fill="rgba(255,255,255,0.12)" />
              <circle cx="240" cy="135" r="25" fill="rgba(255,255,255,0.1)" />
              <circle cx="160" cy="90" r="20" fill="rgba(255,255,255,0.08)" />

              {/* Main Admin Dashboard */}
              <rect x="35" y="35" width="160" height="90" rx="25" fill="rgba(255,255,255,0.18)" stroke="rgba(255,255,255,0.25)" strokeWidth="1.5"/>
              <rect x="55" y="55" width="120" height="60" rx="18" fill="rgba(255,255,255,0.3)" />

              {/* Admin Dashboard Elements */}
              <g transform="translate(70, 70)">
                {/* Settings Gear */}
                <circle cx="15" cy="15" r="12" fill="rgba(255,255,255,0.9)" stroke="#667eea" strokeWidth="2"/>
                <circle cx="15" cy="15" r="8" fill="none" stroke="#667eea" strokeWidth="1.5"/>
                <rect x="13" y="8" width="4" height="4" rx="1" fill="#667eea"/>
                <rect x="13" y="18" width="4" height="4" rx="1" fill="#667eea"/>
                <rect x="8" y="13" width="4" height="4" rx="1" fill="#667eea"/>
                <rect x="18" y="13" width="4" height="4" rx="1" fill="#667eea"/>
              </g>

              <g transform="translate(105, 70)">
                {/* Users Icon */}
                <circle cx="12.5" cy="10" r="8" fill="rgba(255,255,255,0.9)" stroke="#764ba2" strokeWidth="2"/>
                <circle cx="12.5" cy="8" r="4" fill="#764ba2"/>
                <circle cx="8" cy="6" r="2" fill="rgba(255,255,255,0.8)"/>
                <circle cx="17" cy="6" r="2" fill="rgba(255,255,255,0.8)"/>
                <rect x="6" y="14" width="13" height="8" rx="4" fill="rgba(255,255,255,0.9)" stroke="#764ba2" strokeWidth="1.5"/>
              </g>

              <g transform="translate(140, 70)">
                {/* Analytics Chart */}
                <rect x="0" y="10" width="25" height="15" rx="3" fill="rgba(255,255,255,0.9)" stroke="#f093fb" strokeWidth="1.5"/>
                <rect x="3" y="18" width="4" height="5" fill="#f093fb"/>
                <rect x="9" y="15" width="4" height="8" fill="#f5576c"/>
                <rect x="15" y="12" width="4" height="11" fill="#4facfe"/>
                <rect x="21" y="16" width="4" height="7" fill="#667eea"/>
              </g>
            </svg>

            <p style={{
              color: "rgba(255,255,255,0.95)",
              fontSize: "1.2rem",
              fontWeight: 600,
              margin: 0,
              textShadow: "1px 1px 3px rgba(0,0,0,0.3)"
            }}>
              Administrative Control Center
            </p>
            <p style={{
              color: "rgba(255,255,255,0.8)",
              fontSize: "0.9rem",
              fontWeight: 400,
              margin: "8px 0 0 0",
              textShadow: "1px 1px 2px rgba(0,0,0,0.2)"
            }}>
              Manage claims, users, and system settings
            </p>
          </div>
        </div>
      </div>

      {/* Right Admin Login Form */}
      <div style={{
        flex: 1,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#fff",
        height: "100vh"
      }}>
        <form onSubmit={handleSubmit} style={{
          width: 420,
          maxWidth: "90%",
          background: "linear-gradient(135deg, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.9) 100%)",
          backdropFilter: "blur(25px)",
          borderRadius: 28,
          boxShadow: "0 20px 60px rgba(102, 126, 234, 0.2), 0 10px 30px rgba(118, 75, 162, 0.15), 0 5px 15px rgba(240, 147, 251, 0.1), inset 0 1px 0 rgba(255,255,255,0.4)",
          border: "1px solid rgba(255,255,255,0.5)",
          padding: "50px 45px 40px 45px",
          position: "relative",
          overflow: "hidden"
        }}>
          <div style={{ textAlign: 'center', marginBottom: 32 }}>
            <div style={{
              background: 'linear-gradient(135deg, #667eea 0%, #764ba2 50%, #f093fb 100%)',
              width: '80px',
              height: '80px',
              borderRadius: '50%',
              margin: '0 auto 20px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '32px',
              boxShadow: '0 8px 25px rgba(102, 126, 234, 0.3)',
              border: '3px solid rgba(255,255,255,0.3)'
            }}>
              👨‍💼
            </div>
            <h2 style={{
              fontWeight: 800,
              marginBottom: 12,
              color: '#333',
              fontSize: '2.2rem',
              letterSpacing: '-0.02em'
            }}>Admin Login</h2>
            <p style={{
              color: '#666',
              fontSize: '16px',
              margin: 0,
              fontWeight: 500
            }}>
              Secure access to administrative controls
            </p>
          </div>
          
          {error && <div style={{ color: "red", marginBottom: 12, textAlign: "center" }}>{error}</div>}
          
          <div style={{ marginBottom: 18 }}>
            <label style={{ fontWeight: 500, marginBottom: 4, display: "block", color: '#333' }}>Admin Email</label>
            <div style={{
              position: 'relative',
              display: 'flex',
              alignItems: 'center'
            }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" style={{
                position: 'absolute',
                left: '14px',
                zIndex: 1,
                color: 'rgba(102, 126, 234, 0.7)'
              }}>
                <path d="M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z" fill="currentColor"/>
              </svg>
              <input
                type="email"
                placeholder="admin@intelliclaims.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                style={{
                  width: "100%",
                  padding: "14px 18px 14px 44px",
                  borderRadius: 12,
                  border: "2px solid rgba(255,255,255,0.3)",
                  background: "rgba(255,255,255,0.1)",
                  backdropFilter: "blur(10px)",
                  fontSize: '16px',
                  color: '#333',
                  transition: 'all 0.3s ease',
                  outline: 'none'
                }}
                onFocus={(e) => {
                  e.target.style.borderColor = 'rgba(102, 126, 234, 0.6)';
                  e.target.style.background = 'rgba(255,255,255,0.2)';
                  e.target.style.transform = 'translateY(-1px)';
                }}
                onBlur={(e) => {
                  e.target.style.borderColor = 'rgba(255,255,255,0.3)';
                  e.target.style.background = 'rgba(255,255,255,0.1)';
                  e.target.style.transform = 'translateY(0)';
                }}
              />
            </div>
          </div>

          <div style={{ marginBottom: 24 }}>
            <label style={{ fontWeight: 500, marginBottom: 4, display: "block", color: '#333' }}>Password</label>
            <div style={{
              position: 'relative',
              display: 'flex',
              alignItems: 'center'
            }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" style={{
                position: 'absolute',
                left: '14px',
                zIndex: 1,
                color: 'rgba(102, 126, 234, 0.7)'
              }}>
                <path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zM9 6c0-1.66 1.34-3 3-3s3 1.34 3 3v2H9V6zm3 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z" fill="currentColor"/>
              </svg>
              <input
                type="password"
                placeholder="Enter admin password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                style={{
                  width: "100%",
                  padding: "14px 18px 14px 44px",
                  borderRadius: 12,
                  border: "2px solid rgba(255,255,255,0.3)",
                  background: "rgba(255,255,255,0.1)",
                  backdropFilter: "blur(10px)",
                  fontSize: '16px',
                  color: '#333',
                  transition: 'all 0.3s ease',
                  outline: 'none'
                }}
                onFocus={(e) => {
                  e.target.style.borderColor = 'rgba(102, 126, 234, 0.6)';
                  e.target.style.background = 'rgba(255,255,255,0.2)';
                  e.target.style.transform = 'translateY(-1px)';
                }}
                onBlur={(e) => {
                  e.target.style.borderColor = 'rgba(255,255,255,0.3)';
                  e.target.style.background = 'rgba(255,255,255,0.1)';
                  e.target.style.transform = 'translateY(0)';
                }}
              />
            </div>
          </div>
          
          <button
            type="submit"
            style={{
              width: "100%",
              background: "linear-gradient(135deg, #667eea 0%, #764ba2 25%, #f093fb 50%, #f5576c 75%, #4facfe 100%)",
              color: "#fff",
              fontWeight: 700,
              border: "none",
              borderRadius: 12,
              padding: "16px 0",
              fontSize: "16px",
              cursor: "pointer",
              marginBottom: 16,
              transition: 'all 0.3s ease',
              boxShadow: "0 4px 15px rgba(102, 126, 234, 0.3)",
              position: "relative",
              overflow: "hidden"
            }}
            onMouseOver={(e) => {
              e.target.style.transform = 'translateY(-2px)';
              e.target.style.boxShadow = '0 8px 25px rgba(102, 126, 234, 0.4)';
            }}
            onMouseOut={(e) => {
              e.target.style.transform = 'translateY(0)';
              e.target.style.boxShadow = '0 4px 15px rgba(102, 126, 234, 0.3)';
            }}
          >
            Access Admin Panel
          </button>
          
          <div style={{
            textAlign: "center",
            marginTop: 16,
            fontSize: "14px"
          }}>
            <button
              type="button"
              onClick={() => navigate("/login-selection")}
              style={{
                background: 'none',
                border: 'none',
                color: '#667eea',
                cursor: 'pointer',
                textDecoration: 'underline',
                fontSize: '14px'
              }}
            >
              ← Back to Login Selection
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
