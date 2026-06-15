import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { createUserWithEmailAndPassword } from "firebase/auth";
import { setDoc, doc } from "firebase/firestore";
import { auth, db } from "../firebase";

export default function Signup() {
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSignup = async (e) => {
    e.preventDefault();
    setError("");

    if (firstName && lastName && email && password && confirmPassword) {
      if (password !== confirmPassword) {
        setError("Passwords do not match");
        return;
      }

      if (password.length < 6) {
        setError("Password must be at least 6 characters");
        return;
      }

      setLoading(true);
      try {
        // Create user with Firebase Auth
        const userCredential = await createUserWithEmailAndPassword(auth, email, password);
        const user = userCredential.user;

        // Store user data in Firestore
        await setDoc(doc(db, "users", user.uid), {
          firstName: firstName,
          lastName: lastName,
          email: email,
          createdAt: new Date(),
          uid: user.uid,
        });

        alert("Signup successful! Please login to access your dashboard.");
        navigate("/user-login");
      } catch (err) {
        if (err.code === "auth/email-already-in-use") {
          setError("Email is already registered. Please login instead.");
        } else if (err.code === "auth/invalid-email") {
          setError("Invalid email address");
        } else if (err.code === "auth/weak-password") {
          setError("Password is too weak. Use a stronger password.");
        } else {
          setError(err.message || "Failed to create account");
        }
        console.error("Signup error:", err);
      } finally {
        setLoading(false);
      }
    } else {
      setError("Please fill in all fields");
    }
  };

  return (
    <div style={{
      minHeight: "100vh",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      background: "#f7f7f7"
    }}>
      <form onSubmit={handleSignup} style={{
        background: "#fff",
        padding: "32px 32px 24px 32px",
        borderRadius: 16,
        boxShadow: "0 2px 16px rgba(0,0,0,0.06)",
        width: 340,
        maxWidth: "90%"
      }}>
        <h2 style={{ textAlign: "center", marginBottom: 24 }}>Sign Up</h2>
        {error && <div style={{ color: "red", marginBottom: 12 }}>{error}</div>}
        <div style={{ marginBottom: 18 }}>
          <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>First Name</label>
          <input
            type="text"
            placeholder="First Name"
            value={firstName}
            onChange={e => setFirstName(e.target.value)}
            required
            style={{
              width: "100%",
              padding: "10px 12px",
              borderRadius: 6,
              border: "1px solid #e0e0e0"
            }}
          />
        </div>
        <div style={{ marginBottom: 18 }}>
          <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>Last Name</label>
          <input
            type="text"
            placeholder="Last Name"
            value={lastName}
            onChange={e => setLastName(e.target.value)}
            required
            style={{
              width: "100%",
              padding: "10px 12px",
              borderRadius: 6,
              border: "1px solid #e0e0e0"
            }}
          />
        </div>
        <div style={{ marginBottom: 18 }}>
          <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>Email</label>
          <input
            type="email"
            placeholder="you@email.com"
            value={email}
            onChange={e => setEmail(e.target.value)}
            required
            style={{
              width: "100%",
              padding: "10px 12px",
              borderRadius: 6,
              border: "1px solid #e0e0e0"
            }}
          />
        </div>
        <div style={{ marginBottom: 18 }}>
          <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>Password</label>
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            required
            style={{
              width: "100%",
              padding: "10px 12px",
              borderRadius: 6,
              border: "1px solid #e0e0e0"
            }}
          />
        </div>
        <div style={{ marginBottom: 18 }}>
          <label style={{ fontWeight: 500, marginBottom: 4, display: "block" }}>Confirm Password</label>
          <input
            type="password"
            placeholder="Confirm Password"
            value={confirmPassword}
            onChange={e => setConfirmPassword(e.target.value)}
            required
            style={{
              width: "100%",
              padding: "10px 12px",
              borderRadius: 6,
              border: "1px solid #e0e0e0"
            }}
          />
        </div>
        <button
          type="submit"
          disabled={loading}
          style={{
            width: "100%",
            background: loading ? "#ccc" : "#ff8a00",
            color: "#fff",
            fontWeight: 700,
            border: "none",
            borderRadius: 6,
            padding: "12px 0",
            fontSize: "1.1rem",
            cursor: loading ? "not-allowed" : "pointer",
            marginBottom: 12
          }}
        >
          {loading ? "Creating Account..." : "Signup"}
        </button>
        <div style={{ textAlign: "center", marginTop: 8, fontSize: "0.97rem" }}>
          Already have an account? <a href="#" onClick={() => navigate("/user-login")} style={{ color: "#ff8a00", textDecoration: "none" }}>Login</a>
        </div>
      </form>
    </div>
  );
}
