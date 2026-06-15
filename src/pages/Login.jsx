 import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { signInWithEmailAndPassword } from "firebase/auth";
import { auth } from "../firebase";

export default function UserLogin() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");

    if (!email || !password) {
      setError("Please enter both email and password");
      return;
    }

    setLoading(true);
    try {
      const userCredential = await signInWithEmailAndPassword(auth, email, password);
      console.log("User logged in:", userCredential.user.email);
      navigate("/user-dashboard");
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        setError("No account found with this email. Please signup first.");
      } else if (err.code === "auth/wrong-password") {
        setError("Incorrect password. Please try again.");
      } else if (err.code === "auth/invalid-email") {
        setError("Invalid email address");
      } else if (err.code === "auth/too-many-requests") {
        setError("Too many login attempts. Please try again later.");
      } else {
        setError(err.message || "Failed to login");
      }
      console.error("Login error:", err);
    } finally {
      setLoading(false);
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
      {/* Left Orange Illustration */}
      <div style={{
        flex: 1,
        background: "linear-gradient(135deg, #ff8a00 0%, #ff6b35 25%, #e55a2b 50%, #d44a1f 75%, #c0392b 100%)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minWidth: 0,
        height: "100vh",
        position: "relative",
        overflow: "hidden"
      }}>


        <div style={{
          textAlign: "center",
          zIndex: 3,
          position: "relative",
          animation: "fadeInUp 1.2s ease-out"
        }}>
          <div style={{
            background: "rgba(255,255,255,0.15)",
            backdropFilter: "blur(25px)",
            borderRadius: "30px",
            padding: "60px 40px",
            boxShadow: "0 20px 60px rgba(0,0,0,0.2), inset 0 1px 0 rgba(255,255,255,0.3)",
            border: "1px solid rgba(255,255,255,0.5)",
            position: "relative",
            overflow: "hidden"
          }}>
            {/* Decorative background elements */}
            <div style={{
              position: "absolute",
              top: "-50%",
              left: "-50%",
              width: "200%",
              height: "200%",
              background: "radial-gradient(circle at 30% 20%, rgba(255,255,255,0.1) 0%, transparent 50%), radial-gradient(circle at 70% 80%, rgba(255,255,255,0.05) 0%, transparent 50%)",
              animation: "rotate 20s linear infinite"
            }}></div>

            {/* Car Insurance Icons */}
            <div style={{
              position: "absolute",
              top: "20px",
              left: "20px",
              opacity: 0.3,
              animation: "float 6s ease-in-out infinite"
            }}>
              <svg width="40" height="40" viewBox="0 0 24 24" fill="white">
                <path d="M5,11L6.5,6.5H17.5L19,11V16A1,1 0 0,1 18,17H6A1,1 0 0,1 5,16V11M18,8.5H6.5L5.5,11H18.5L18,8.5M7,12A1.5,1.5 0 0,0 5.5,13.5A1.5,1.5 0 0,0 7,15A1.5,1.5 0 0,0 8.5,13.5A1.5,1.5 0 0,0 7,12M17,12A1.5,1.5 0 0,0 15.5,13.5A1.5,1.5 0 0,0 17,15A1.5,1.5 0 0,0 18.5,13.5A1.5,1.5 0 0,0 17,12Z"/>
              </svg>
            </div>

            <div style={{
              position: "absolute",
              top: "60px",
              right: "30px",
              opacity: 0.2,
              animation: "float 8s ease-in-out infinite reverse"
            }}>
              <svg width="30" height="30" viewBox="0 0 24 24" fill="white">
                <path d="M12,2C13.1,2 14,2.9 14,4C14,5.1 13.1,6 12,6C10.9,6 10,5.1 10,4C10,2.9 10.9,2 12,2M21,9V7L15,1H5C3.89,1 3,1.89 3,3V21A2,2 0 0,0 5,23H19A2,2 0 0,0 21,21V9M19,9H14V4H19V9Z"/>
              </svg>
            </div>

            <div style={{
              position: "absolute",
              bottom: "80px",
              left: "25px",
              opacity: 0.25,
              animation: "float 7s ease-in-out infinite"
            }}>
              <svg width="35" height="35" viewBox="0 0 24 24" fill="white">
                <path d="M18.92,6.01C18.72,5.42 18.16,5 17.5,5H6.5C5.84,5 5.29,5.42 5.08,6.01L3,12V20A1,1 0 0,0 4,21H5A1,1 0 0,0 6,20V19H18V20A1,1 0 0,0 19,21H20A1,1 0 0,0 21,20V12L18.92,6.01M6.5,16C5.67,16 5,15.33 5,14.5S5.67,13 6.5,13 8,13.67 8,14.5 7.33,16 6.5,16M17.5,16C16.67,16 16,15.33 16,14.5S16.67,13 17.5,13 19,13.67 19,14.5 18.33,16 17.5,16M5,11L6.5,6.5H17.5L19,11H5Z"/>
              </svg>
            </div>

            <div style={{
              position: "absolute",
              bottom: "40px",
              right: "20px",
              opacity: 0.3,
              animation: "float 9s ease-in-out infinite reverse"
            }}>
              <svg width="28" height="28" viewBox="0 0 24 24" fill="white">
                <path d="M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M11,16.5L6.5,12L7.91,10.59L11,13.67L16.59,8.08L18,9.5L11,16.5Z"/>
              </svg>
            </div>

            <h1 style={{
              color: "#fff",
              fontWeight: 900,
              fontSize: "4rem",
              marginBottom: 20,
              letterSpacing: "-0.05em",
              textShadow: "0 4px 20px rgba(0,0,0,0.3), 0 0 40px rgba(255,255,255,0.2)",
              position: "relative",
              zIndex: 2
            }}>
              IntelliClaim
            </h1>

            {/* Decorative Car Shapes */}
            <div style={{
              display: "flex",
              justifyContent: "center",
              alignItems: "center",
              marginBottom: 25,
              position: "relative",
              zIndex: 2
            }}>
              {/* Left Car Shape */}
              <div style={{
                width: "60px",
                height: "30px",
                background: "linear-gradient(45deg, rgba(255,255,255,0.2) 0%, rgba(255,255,255,0.1) 100%)",
                borderRadius: "15px 15px 0 0",
                marginRight: "15px",
                position: "relative",
                border: "1px solid rgba(255,255,255,0.3)",
                animation: "slideLeft 3s ease-in-out infinite"
              }}>
                <div style={{
                  position: "absolute",
                  top: "5px",
                  left: "8px",
                  width: "8px",
                  height: "8px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
                <div style={{
                  position: "absolute",
                  top: "5px",
                  right: "8px",
                  width: "8px",
                  height: "8px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
              </div>

              {/* Center Gear Shape */}
              <div style={{
                width: "40px",
                height: "40px",
                borderRadius: "50%",
                background: "linear-gradient(45deg, rgba(255,255,255,0.15) 0%, rgba(255,255,255,0.05) 100%)",
                border: "2px solid rgba(255,255,255,0.3)",
                position: "relative",
                animation: "rotate 4s linear infinite"
              }}>
                <div style={{
                  position: "absolute",
                  top: "50%",
                  left: "50%",
                  transform: "translate(-50%, -50%)",
                  width: "12px",
                  height: "12px",
                  background: "rgba(255,255,255,0.3)",
                  borderRadius: "50%"
                }}></div>
                {/* Gear teeth */}
                <div style={{
                  position: "absolute",
                  top: "-2px",
                  left: "50%",
                  transform: "translateX(-50%)",
                  width: "4px",
                  height: "4px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
                <div style={{
                  position: "absolute",
                  bottom: "-2px",
                  left: "50%",
                  transform: "translateX(-50%)",
                  width: "4px",
                  height: "4px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
                <div style={{
                  position: "absolute",
                  left: "-2px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  width: "4px",
                  height: "4px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
                <div style={{
                  position: "absolute",
                  right: "-2px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  width: "4px",
                  height: "4px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
              </div>

              {/* Right Car Shape */}
              <div style={{
                width: "60px",
                height: "30px",
                background: "linear-gradient(45deg, rgba(255,255,255,0.2) 0%, rgba(255,255,255,0.1) 100%)",
                borderRadius: "15px 15px 0 0",
                marginLeft: "15px",
                position: "relative",
                border: "1px solid rgba(255,255,255,0.3)",
                animation: "slideRight 3s ease-in-out infinite"
              }}>
                <div style={{
                  position: "absolute",
                  top: "5px",
                  left: "8px",
                  width: "8px",
                  height: "8px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
                <div style={{
                  position: "absolute",
                  top: "5px",
                  right: "8px",
                  width: "8px",
                  height: "8px",
                  background: "rgba(255,255,255,0.4)",
                  borderRadius: "50%"
                }}></div>
              </div>
            </div>

            <p style={{
              color: "rgba(255,255,255,0.9)",
              fontSize: "1.3rem",
              fontWeight: 500,
              margin: "0 0 15px 0",
              textShadow: "0 2px 10px rgba(0,0,0,0.2)",
              position: "relative",
              zIndex: 2
            }}>
              Smart Claims Processing
            </p>

            <p style={{
              color: "rgba(255,255,255,0.7)",
              fontSize: "1rem",
              fontWeight: 400,
              margin: "0",
              textShadow: "0 1px 5px rgba(0,0,0,0.15)",
              position: "relative",
              zIndex: 2
            }}>
              Powered by Advanced AI Technology
            </p>
          </div>
        </div>

        {/* CSS Animations */}
        <style>{`
          @keyframes fadeInUp {
            from {
              opacity: 0;
              transform: translateY(40px) scale(0.95);
            }
            to {
              opacity: 1;
              transform: translateY(0) scale(1);
            }
          }

          @keyframes rotate {
            from {
              transform: rotate(0deg);
            }
            to {
              transform: rotate(360deg);
            }
          }

          @keyframes float {
            0% { transform: translateY(0px) rotate(0deg); }
            50% { transform: translateY(-20px) rotate(180deg); }
            100% { transform: translateY(0px) rotate(360deg); }
          }

          @keyframes slideLeft {
            0% { transform: translateX(0px); }
            50% { transform: translateX(-10px); }
            100% { transform: translateX(0px); }
          }

          @keyframes slideRight {
            0% { transform: translateX(0px); }
            50% { transform: translateX(10px); }
            100% { transform: translateX(0px); }
          }

          @keyframes pulse {
            0%, 100% { opacity: 0.4; transform: scale(1); }
            50% { opacity: 1; transform: scale(1.2); }
          }
        `}</style>
      </div>

      {/* Right Login Form */}
      <div style={{
        flex: 1,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#fff",
        height: "100vh"
      }}>
        <form onSubmit={handleSubmit} style={{
          width: 380,
          maxWidth: "90%",
          background: "#fff",
          borderRadius: 20,
          boxShadow: "0 10px 40px rgba(0,0,0,0.1), 0 0 0 1px rgba(255,255,255,0.05)",
          padding: "40px 36px 32px 36px",
          backdropFilter: "blur(10px)",
          border: "1px solid rgba(255,255,255,0.1)"
        }}>
          <div style={{ textAlign: 'center', marginBottom: 24 }}>
            <div style={{
              background: '#ff8a00',
              width: '60px',
              height: '60px',
              borderRadius: '50%',
              margin: '0 auto 16px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '24px'
            }}>
              👤
            </div>
            <h2 style={{
              fontWeight: 700,
              marginBottom: 8,
              color: '#333'
            }}>User Login</h2>
            <p style={{ color: '#666', fontSize: '14px', margin: 0 }}>
              Access your claims and dashboard
            </p>
          </div>
          {error && <div style={{ color: "red", marginBottom: 12, textAlign: "center" }}>{error}</div>}
          <div style={{ marginBottom: 18 }}>
            <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>Email</label>
            <input
              type="email"
              placeholder="you@email.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              style={{
                width: "100%",
                padding: "14px 16px",
                borderRadius: 10,
                border: "2px solid #f0f0f0",
                fontSize: "16px",
                transition: "all 0.3s ease",
                outline: "none",
                marginBottom: 8
              }}
              onFocus={(e) => e.target.style.borderColor = "#ff8a00"}
              onBlur={(e) => e.target.style.borderColor = "#f0f0f0"}
            />
          </div>
          <div style={{ marginBottom: 8 }}>
            <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>Password</label>
            <input
              type="password"
              placeholder="Password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              style={{
                width: "100%",
                padding: "14px 16px",
                borderRadius: 10,
                border: "2px solid #f0f0f0",
                fontSize: "16px",
                transition: "all 0.3s ease",
                outline: "none"
              }}
              onFocus={(e) => e.target.style.borderColor = "#ff8a00"}
              onBlur={(e) => e.target.style.borderColor = "#f0f0f0"}
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            style={{
              width: "100%",
              background: loading ? "#ccc" : "linear-gradient(135deg, #ff8a00 0%, #ff6b35 100%)",
              color: "#fff",
              fontWeight: 700,
              border: "none",
              borderRadius: 12,
              padding: "16px 0",
              fontSize: "1.1rem",
              cursor: loading ? "not-allowed" : "pointer",
              marginBottom: 12,
              transition: "all 0.3s ease",
              boxShadow: loading ? "none" : "0 4px 15px rgba(255, 138, 0, 0.3)"
            }}
            onMouseEnter={(e) => {
              if (!loading) {
                e.target.style.transform = "translateY(-2px)";
                e.target.style.boxShadow = "0 6px 20px rgba(255, 138, 0, 0.4)";
              }
            }}
            onMouseLeave={(e) => {
              if (!loading) {
                e.target.style.transform = "translateY(0)";
                e.target.style.boxShadow = "0 4px 15px rgba(255, 138, 0, 0.3)";
              }
            }}
          >
            {loading ? "Logging in..." : "Access User Dashboard"}
          </button>
          <div style={{
            textAlign: "center",
            marginBottom: 18,
            fontSize: "0.95rem"
          }}>
            Doesn't have an account? <a href="#" onClick={() => navigate("/signup")} style={{ color: "#ff8a00", textDecoration: "none" }}>Signup</a>
          </div>
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
                color: '#ff8a00',
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
